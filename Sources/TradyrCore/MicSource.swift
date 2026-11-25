import AVFoundation
import os

/// Captures the default input device with `AVAudioEngine`.
///
/// `AVAudioEngine` stops itself whenever the audio hardware configuration changes (a device or its
/// sample rate changes, another app starts a voice call, a process tap's aggregate device appears).
/// This source listens for that and restarts the engine, so a call starting doesn't silence the mic.
public final class MicSource: AudioSource, @unchecked Sendable {
    public let name = "Microphone"

    private static let log = Logger(subsystem: "dev.tradyr.app", category: "mic")

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var observer: NSObjectProtocol?
    private let lock = NSLock()

    public init() {}

    public func start() async throws -> AsyncStream<AudioChunk> {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw AudioSourceError.permissionDenied("Microphone")
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lock.withLock { self.continuation = continuation }

        installTap()
        engine.prepare()
        try engine.start()

        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
        return stream
    }

    public func stop() async {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    private func installTap() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        Self.log.info("mic format: \(format.sampleRate) Hz, \(format.channelCount) ch")
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let continuation = self.lock.withLock { self.continuation }
            continuation?.yield(AudioChunk(buffer: buffer))
        }
    }

    private func restartAfterConfigurationChange() {
        guard lock.withLock({ continuation != nil }) else { return }
        Self.log.info("audio configuration changed; restarting the mic engine")
        engine.inputNode.removeTap(onBus: 0)
        installTap()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Self.log.error("mic engine failed to restart: \(error.localizedDescription)")
        }
    }
}
