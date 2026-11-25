import AudioToolbox
import CoreAudio
import Foundation

/// A process that Core Audio knows about (anything that has used audio).
public struct AudioProcessInfo: Sendable, Identifiable, Hashable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String
    public let isRunningOutput: Bool
    public let isRunningInput: Bool

    public var id: AudioObjectID { objectID }
}

/// Thin wrappers over the Core Audio property API.
public enum CoreAudioSystem {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    static func readValue<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    static func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        readValue(id, selector, as: Unmanaged<CFString>.self).map { $0.takeRetainedValue() as String }
    }

    public static func processes() -> [AudioProcessInfo] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard let pid = readValue(id, kAudioProcessPropertyPID, as: pid_t.self) else { return nil }
            let bundle = readString(id, kAudioProcessPropertyBundleID) ?? ""
            let output = readValue(id, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) ?? 0
            let input = readValue(id, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 0
            return AudioProcessInfo(
                objectID: id, pid: pid, bundleID: bundle,
                isRunningOutput: output != 0, isRunningInput: input != 0)
        }
    }

    /// Audio processes that belong to an application.
    ///
    /// Apps rarely play audio from their main process: Safari plays through `com.apple.WebKit.GPU`,
    /// Chromium browsers through helper processes. A process belongs to the app if it is the app itself,
    /// has a bundle id under the app's (`<id>.helper`), or macOS attributes it to the app
    /// (the same "responsible process" Activity Monitor uses).
    public static func audioProcesses(forApplication bundleID: String, pid: pid_t?) -> [AudioProcessInfo] {
        // Call audio is rendered by a system daemon, not by the Phone or FaceTime app.
        let callApps: Set<String> = ["com.apple.mobilephone", "com.apple.FaceTime"]
        let callDaemon = "com.apple.avconferenced"

        return processes().filter { process in
            if process.bundleID == bundleID || process.bundleID.hasPrefix(bundleID + ".") { return true }
            if let pid {
                if process.pid == pid { return true }
                if let responsible = responsiblePID(for: process.pid), responsible == pid { return true }
            }
            return callApps.contains(bundleID) && process.bundleID == callDaemon
        }
    }

    /// `responsibility_get_pid_responsible_for_pid` is private but has been stable for many releases.
    /// If it ever disappears, matching falls back to bundle ids.
    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t

    private static let responsibilityFunction: ResponsibilityFunction? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()

    static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let responsibilityFunction else { return nil }
        let responsible = responsibilityFunction(pid)
        return responsible > 0 ? responsible : nil
    }

    /// UID and name of the current default output device.
    ///
    /// A process tap's aggregate device needs this as its clock source. Without it the tap runs but delivers zeros.
    static func defaultOutputDevice() -> (uid: String, name: String)? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let device = readValue(system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self),
              device != kAudioObjectUnknown,
              let uid = readString(device, kAudioDevicePropertyDeviceUID)
        else { return nil }
        return (uid, readString(device, kAudioObjectPropertyName) ?? "?")
    }
}
