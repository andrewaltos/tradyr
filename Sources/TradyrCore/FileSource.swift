import AVFoundation

/// Plays an audio file through the pipeline as if it were live. For diagnostics and tests.
public final class FileSource: AudioSource, @unchecked Sendable {
    public let name: String

    private let url: URL
    private let realtime: Bool
    private var task: Task<Void, Never>?

    /// - Parameter realtime: pace buffers at playback speed, like a live source.
    public init(url: URL, realtime: Bool = true) {
        self.url = url
        self.realtime = realtime
        self.name = url.lastPathComponent
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let framesPerChunk: AVAudioFrameCount = 4096
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .unbounded)
        let realtime = realtime

        task = Task.detached {
            while !Task.isCancelled, file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerChunk) else { break }
                do { try file.read(into: buffer, frameCount: framesPerChunk) } catch { break }
                if buffer.frameLength == 0 { break }
                continuation.yield(AudioChunk(buffer: buffer))
                if realtime {
                    try? await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate))
                }
            }
            continuation.finish()
        }
        return stream
    }

    public func stop() async {
        task?.cancel()
    }
}
