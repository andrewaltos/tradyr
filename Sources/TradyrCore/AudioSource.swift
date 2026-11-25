import AVFoundation

/// A buffer of captured audio. `AVAudioPCMBuffer` isn't `Sendable`, but we never mutate a buffer after yielding it.
public struct AudioChunk: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer

    public init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

public enum AudioSourceError: LocalizedError {
    case permissionDenied(String)
    case processNotFound(String)
    case coreAudio(String, OSStatus)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let what):
            "\(what) permission was denied. Allow it in System Settings → Privacy & Security."
        case .processNotFound(let name):
            "\(name) isn't playing audio yet. Start playback (or the call), then press Start."
        case .coreAudio(let call, let status):
            "\(call) failed with status \(status)."
        case .unsupportedFormat(let detail):
            "Unsupported audio format: \(detail)"
        }
    }
}

/// Anything that produces live audio: the microphone, or another app's output.
public protocol AudioSource: Sendable {
    var name: String { get }

    /// Starts capture. The stream ends when `stop()` is called.
    func start() async throws -> AsyncStream<AudioChunk>
    func stop() async
}
