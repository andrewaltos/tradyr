import Foundation
import NaturalLanguage

/// One lane: audio source → speech recognition → paragraphs → translation → caption updates.
///
/// Live results are split into paragraphs (see `ParagraphSplitter`). Each paragraph is translated once and
/// then reused. While a growing paragraph is being re-translated, its previous translation stays on
/// screen, so the line doesn't flicker between text and "…".
public final class LanePipeline: @unchecked Sendable {
    public let lane: Lane
    public let direction: Direction
    public let source: any AudioSource

    private let clock: SessionClock
    private let onLevel: (@Sendable (Float) -> Void)?
    private let splitter = ParagraphSplitter()
    private var preparedStream: AsyncStream<AudioChunk>?

    /// - Parameter onLevel: called with the linear RMS level of every audio buffer, for level meters.
    public init(
        lane: Lane,
        source: any AudioSource,
        direction: Direction,
        clock: SessionClock,
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) {
        self.lane = lane
        self.source = source
        self.direction = direction
        self.clock = clock
        self.onLevel = onLevel
    }

    /// Starts the audio source without starting recognition.
    ///
    /// Lets the caller bring sources up one at a time: starting a process tap changes the audio
    /// hardware configuration, which can disturb a microphone engine that is already running.
    public func prepare() async throws {
        guard preparedStream == nil else { return }
        preparedStream = try await source.start()
    }

    public func run() -> AsyncThrowingStream<CaptionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.pump(into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() async {
        await source.stop()
    }

    // MARK: - Pump

    private func pump(into continuation: AsyncThrowingStream<CaptionUpdate, Error>.Continuation) async throws {
        let translator = SegmentTranslator(source: direction.sourceLanguage, target: direction.targetLanguage)
        let transcriber = LiveTranscriber(locale: direction.sourceLocale)
        let language = NLLanguage(rawValue: direction.sourceCode)

        let raw: AsyncStream<AudioChunk>
        if let preparedStream {
            raw = preparedStream
        } else {
            raw = try await source.start()
        }

        // Meter the audio on its way to the recogniser.
        var forwarder: Task<Void, Never>?
        defer { forwarder?.cancel() }
        let audio: AsyncStream<AudioChunk>
        if let onLevel {
            let (metered, meteredContinuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .unbounded)
            forwarder = Task {
                for await chunk in raw {
                    onLevel(AudioLevel.rms(chunk.buffer))
                    meteredContinuation.yield(chunk)
                }
                meteredContinuation.finish()
            }
            audio = metered
        } else {
            audio = raw
        }

        let laneOffset = OffsetBox()
        let events = transcriber.transcribe(audio) { [clock] in laneOffset.set(clock.now()) }

        let state = SegmentState()
        var worker: Task<Void, Never>?
        defer { worker?.cancel() }

        for try await event in events {
            let paragraphs = splitter.split(event.text, language: language)
            let offset = laneOffset.value
            let segmentStart = offset + event.audioStart
            let segmentEnd = offset + event.audioEnd

            if event.isFinal {
                worker?.cancel()
                worker = nil
                let generation = state.beginFinal()

                // Translate whatever isn't cached yet, then publish the finished paragraphs.
                var translations: [String] = []
                var warning: String?
                for text in paragraphs {
                    if let cached = state.cached(text) {
                        translations.append(cached)
                        continue
                    }
                    do {
                        let translated = try await translator.translate(text)
                        state.store(translated, for: text)
                        translations.append(translated)
                    } catch {
                        warning = "Translation unavailable: \(error.localizedDescription)"
                        translations.append("")
                    }
                }

                let segment = state.segmentID(for: generation)
                for (index, text) in paragraphs.enumerated() {
                    continuation.yield(CaptionUpdate(
                        lane: lane, segmentID: segment, paragraph: index, source: text,
                        translation: translations[index].isEmpty ? nil : translations[index],
                        isFinal: true,
                        start: Self.start(of: index, in: paragraphs, from: segmentStart, to: segmentEnd),
                        end: segmentEnd,
                        warning: warning))
                }
                // Paragraphs that existed live but are gone from the final text.
                for stale in paragraphs.count..<max(paragraphs.count, state.shownCount) {
                    continuation.yield(CaptionUpdate(
                        lane: lane, segmentID: segment, paragraph: stale, source: "",
                        isFinal: true, start: segmentStart, end: segmentEnd))
                }
                state.endFinal()
                continue
            }

            // Live result: show the new text immediately, with the best translation we already have.
            let segment = state.update(paragraphs: paragraphs, start: segmentStart, end: segmentEnd)
            for (index, text) in paragraphs.enumerated() {
                continuation.yield(CaptionUpdate(
                    lane: lane, segmentID: segment, paragraph: index, source: text,
                    translation: state.translationToShow(for: index, text: text),
                    isFinal: false,
                    start: Self.start(of: index, in: paragraphs, from: segmentStart, to: segmentEnd),
                    end: segmentEnd))
            }
            // Paragraphs that disappeared because the recogniser revised its punctuation.
            for stale in state.takeRetired() {
                continuation.yield(CaptionUpdate(
                    lane: lane, segmentID: segment, paragraph: stale, source: "",
                    isFinal: false, start: segmentStart, end: segmentEnd))
            }

            // One worker at a time translates whatever is still missing, closed paragraphs first.
            if worker == nil || state.workerFinished {
                state.workerStarted()
                worker = Task { [lane] in
                    while !Task.isCancelled {
                        guard let job = state.nextJob() else { break }
                        do {
                            let translated = try await translator.translate(job.text)
                            guard !Task.isCancelled, state.accepts(job) else { continue }
                            state.store(translated, for: job.text)
                            if let snapshot = state.snapshot(), job.index < snapshot.paragraphs.count,
                               snapshot.paragraphs[job.index] == job.text {
                                // Remember it as what's on screen, so newer text can fall back to it.
                                state.recordShown(translated, at: job.index)
                                continuation.yield(CaptionUpdate(
                                    lane: lane, segmentID: snapshot.segmentID, paragraph: job.index,
                                    source: job.text, translation: translated, isFinal: false,
                                    start: Self.start(
                                        of: job.index, in: snapshot.paragraphs,
                                        from: snapshot.start, to: snapshot.end),
                                    end: snapshot.end))
                            }
                        } catch {
                            guard !Task.isCancelled else { break }
                            state.markFailed(job.text)
                        }
                    }
                    state.workerEnded()
                }
            }
        }
    }

    /// Estimated start of a paragraph: its share of the segment's audio, by character count.
    /// Live results have no word timing, so this only needs to put paragraphs in sensible order.
    static func start(of index: Int, in paragraphs: [String], from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        guard index > 0, end > start else { return start }
        let total = max(1, paragraphs.reduce(0) { $0 + $1.count })
        let before = paragraphs.prefix(index).reduce(0) { $0 + $1.count }
        return start + (end - start) * Double(before) / Double(total)
    }
}

// MARK: - Shared state

/// State shared between the recognition loop and the translation worker.
private final class SegmentState: @unchecked Sendable {
    struct Job {
        let index: Int
        let text: String
        let generation: Int
    }

    struct Snapshot {
        let segmentID: Int
        let paragraphs: [String]
        let start: TimeInterval
        let end: TimeInterval
    }

    private let lock = NSLock()
    private var segment = 0
    private var generation = 0
    private var paragraphs: [String] = []
    private var start: TimeInterval = 0
    private var end: TimeInterval = 0
    private var cache: [String: String] = [:]
    private var failed: Set<String> = []
    /// The translation last published for each paragraph index, kept on screen while a newer one is computed.
    private var shown: [Int: String] = [:]
    private var retired: [Int] = []
    private var running = false

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var shownCount: Int { locked { (shown.keys.max() ?? -1) + 1 } }
    var workerFinished: Bool { locked { !running } }

    func workerStarted() { locked { running = true } }
    func workerEnded() { locked { running = false } }

    func cached(_ text: String) -> String? { locked { cache[text] } }

    func store(_ translation: String, for text: String) {
        locked {
            cache[text] = translation
            failed.remove(text)
            // Bound memory over a long session.
            if cache.count > 400 { cache.removeAll(keepingCapacity: true); cache[text] = translation }
        }
    }

    func markFailed(_ text: String) { locked { _ = failed.insert(text) } }

    /// Records the latest live paragraphs. Returns the segment id they belong to.
    func update(paragraphs new: [String], start: TimeInterval, end: TimeInterval) -> Int {
        locked {
            if new.count < paragraphs.count { retired.append(contentsOf: new.count..<paragraphs.count) }
            paragraphs = new
            self.start = start
            self.end = end
            // A paragraph that vanished no longer has a translation on screen.
            for index in shown.keys where index >= new.count { shown[index] = nil }
            return segment
        }
    }

    func takeRetired() -> [Int] {
        locked {
            defer { retired = [] }
            return retired
        }
    }

    /// The translation to display now: the exact one if cached, otherwise the previous one for this slot.
    func translationToShow(for index: Int, text: String) -> String? {
        locked {
            if let exact = cache[text] {
                shown[index] = exact
                return exact
            }
            return shown[index]
        }
    }

    func recordShown(_ translation: String, at index: Int) {
        locked { shown[index] = translation }
    }

    func snapshot() -> Snapshot? {
        locked { paragraphs.isEmpty ? nil : Snapshot(segmentID: segment, paragraphs: paragraphs, start: start, end: end) }
    }

    /// The next paragraph that has no translation yet. Closed paragraphs come before the one in progress.
    func nextJob() -> Job? {
        locked {
            for (index, text) in paragraphs.enumerated() where cache[text] == nil && !failed.contains(text) {
                return Job(index: index, text: text, generation: generation)
            }
            return nil
        }
    }

    /// False if a final result arrived while the job was running.
    func accepts(_ job: Job) -> Bool { locked { job.generation == generation } }

    // MARK: Final results

    func beginFinal() -> Int {
        locked {
            generation += 1
            return generation
        }
    }

    func segmentID(for generation: Int) -> Int { locked { segment } }

    func endFinal() {
        locked {
            segment += 1
            paragraphs = []
            shown = [:]
            retired = []
            failed = []
        }
    }
}

/// A tiny lock-protected value, written once from the audio thread and read from the pipeline task.
private final class OffsetBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TimeInterval = 0

    var value: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ newValue: TimeInterval) {
        lock.lock()
        stored = newValue
        lock.unlock()
    }
}
