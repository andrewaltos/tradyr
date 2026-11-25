import AVFoundation
import AudioToolbox
import CoreAudio

/// Captures what other processes are playing, via a Core Audio process tap (macOS 14.2+).
///
/// For "Calls from iPhone" the remote party's audio is rendered by `com.apple.avconferenced`,
/// not by the FaceTime app.
public final class ProcessTapSource: AudioSource, @unchecked Sendable {
    public static let callAudioBundleID = "com.apple.avconferenced"

    /// What to capture.
    public enum Target: Sendable {
        /// Specific processes by exact bundle id (used for call audio).
        case bundleIDs([String])
        /// An application and everything that plays audio on its behalf (helpers, GPU processes).
        case application(bundleID: String, pid: pid_t?)
        /// Everything the Mac is playing.
        case allSystemAudio
    }

    public let name: String

    private let target: Target
    private let queue = DispatchQueue(label: "tradyr.processtap")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    public init(target: Target, name: String) {
        self.target = target
        self.name = name
    }

    /// Convenience for tapping specific processes by exact bundle identifier.
    public convenience init(bundleIDs: [String], name: String? = nil) {
        self.init(target: .bundleIDs(bundleIDs), name: name ?? bundleIDs.joined(separator: ", "))
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        // Resolve every time: pids change between sessions, and helpers come and go.
        let own = getpid()
        let all = CoreAudioSystem.processes()
        let description: CATapDescription
        switch target {
        case .allSystemAudio:
            // Don't tap ourselves.
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: all.filter { $0.pid == own }.map(\.objectID))
        case .bundleIDs(let ids):
            let matches = all.filter { ids.contains($0.bundleID) }
            guard !matches.isEmpty else { throw AudioSourceError.processNotFound(name) }
            description = CATapDescription(stereoMixdownOfProcesses: matches.map(\.objectID))
        case .application(let bundleID, let pid):
            let matches = CoreAudioSystem.audioProcesses(forApplication: bundleID, pid: pid).filter { $0.pid != own }
            guard !matches.isEmpty else { throw AudioSourceError.processNotFound(name) }
            description = CATapDescription(stereoMixdownOfProcesses: matches.map(\.objectID))
        }
        guard let output = CoreAudioSystem.defaultOutputDevice() else {
            throw AudioSourceError.coreAudio("Reading the default output device", -1)
        }

        description.uuid = UUID()
        description.name = "tradyr-tap"
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw AudioSourceError.coreAudio("AudioHardwareCreateProcessTap", status) }

        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = CoreAudioSystem.address(kAudioTapPropertyFormat)
        status = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &asbdSize, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd), asbd.mBytesPerFrame > 0 else {
            await stop()
            throw AudioSourceError.unsupportedFormat("tap format unavailable (status \(status))")
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "tradyr-aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else {
            await stop()
            throw AudioSourceError.coreAudio("AudioHardwareCreateAggregateDevice", status)
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.continuation = continuation
        let bytesPerFrame = asbd.mBytesPerFrame

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inData, _, _, _ in
            // The system owns `inData` only for the duration of this callback, so copy it.
            let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard let first = source.first else { return }
            let frames = AVAudioFrameCount(first.mDataByteSize / bytesPerFrame)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            buffer.frameLength = frames
            let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for (index, src) in source.enumerated() where index < destination.count {
                guard let from = src.mData, let to = destination[index].mData else { continue }
                memcpy(to, from, Int(min(src.mDataByteSize, destination[index].mDataByteSize)))
            }
            continuation.yield(AudioChunk(buffer: buffer))
        }
        guard status == noErr, let procID else {
            await stop()
            throw AudioSourceError.coreAudio("AudioDeviceCreateIOProcIDWithBlock", status)
        }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            await stop()
            throw AudioSourceError.coreAudio("AudioDeviceStart", status)
        }
        return stream
    }

    public func stop() async {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        continuation?.finish()
        continuation = nil
    }
}
