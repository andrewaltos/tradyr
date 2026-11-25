import AVFoundation
import Speech

public struct TranscriptEvent: Sendable {
    public var text: String
    public var isFinal: Bool
    /// Audio time relative to the first buffer fed to the analyzer.
    public var audioStart: TimeInterval
    public var audioEnd: TimeInterval
}

public enum TranscriberError: LocalizedError {
    case noCompatibleFormat
    case unsupportedLocale(String)

    public var errorDescription: String? {
        switch self {
        case .noCompatibleFormat: "Speech recognition has no audio format available for this locale."
        case .unsupportedLocale(let id): "Speech recognition doesn't support \(id) on this Mac."
        }
    }
}

/// Streaming on-device speech recognition with Apple's `SpeechAnalyzer` (macOS 26+).
///
/// Emits volatile results as the speaker talks and a final result at the end of each phrase.
public final class LiveTranscriber: @unchecked Sendable {
    private let locale: Locale

    public init(locale: Locale) {
        self.locale = locale
    }

    /// - Parameter onFirstAudio: called once, just before the first buffer reaches the analyzer.
    ///   Audio times in the events are relative to that moment.
    public func transcribe(
        _ audio: AsyncStream<AudioChunk>,
        onFirstAudio: @escaping @Sendable () -> Void = {}
    ) -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(audio: audio, onFirstAudio: onFirstAudio, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        audio: AsyncStream<AudioChunk>,
        onFirstAudio: @escaping @Sendable () -> Void,
        into continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) async throws {
        // `.fastResults` is required for live captions. Without it the analyzer holds back
        // all output until it has seen many seconds of audio (about 12 s in testing).
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [])

        // First use downloads the on-device model for this locale.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriberError.noCompatibleFormat
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputs, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputs)

        let results = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                continuation.yield(TranscriptEvent(
                    text: text,
                    isFinal: result.isFinal,
                    audioStart: result.range.start.seconds,
                    audioEnd: result.range.end.seconds))
            }
        }

        let converter = BufferConverter()
        var started = false
        do {
            for await chunk in audio {
                if Task.isCancelled { break }
                if !started {
                    started = true
                    onFirstAudio()
                }
                let converted = try converter.convert(chunk.buffer, to: format)
                inputBuilder.yield(AnalyzerInput(buffer: converted))
            }
        } catch {
            inputBuilder.finish()
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        inputBuilder.finish()
        if Task.isCancelled {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            return
        }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await results.value
    }
}
