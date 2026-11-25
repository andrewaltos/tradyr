import Foundation
import Testing
@testable import TradyrCore

@Suite struct TranscriptFormatTests {
    let callLanes = [
        LaneInfo(lane: .you, sourceLanguage: "fr", targetLanguage: "en", sourceName: "Microphone"),
        LaneInfo(lane: .them, sourceLanguage: "fr", targetLanguage: "en", sourceName: "com.apple.avconferenced"),
    ]

    @Test func timestampFormatting() {
        #expect(TranscriptFormat.timestamp(4.9) == "00:04")
        #expect(TranscriptFormat.timestamp(125) == "02:05")
        #expect(TranscriptFormat.timestamp(3725) == "1:02:05")
        #expect(TranscriptFormat.timestamp(-3) == "00:00")
    }

    @Test func callBlockPairsSourceAndTranslation() {
        let update = CaptionUpdate(
            lane: .them, segmentID: 0, source: "Bonjour, je vous appelle.",
            translation: "Hello, I'm calling you.", isFinal: true, start: 4.2, end: 6.0)
        let block = TranscriptFormat.block(for: update, lanes: callLanes)

        #expect(block.contains("**[00:04] Them** · FR: Bonjour, je vous appelle."))
        #expect(block.contains("**[00:04] Them** · EN: Hello, I'm calling you."))
    }

    @Test func missingTranslationIsMarked() {
        let update = CaptionUpdate(lane: .you, segmentID: 1, source: "Oui", isFinal: true, start: 11, end: 12)
        let block = TranscriptFormat.block(for: update, lanes: callLanes)

        #expect(block.contains("**[00:11] You** · EN: (translation unavailable)"))
    }

    @Test func singleModeHasNoSpeakerLabel() {
        let lanes = [LaneInfo(lane: .single, sourceLanguage: "en", targetLanguage: "fr", sourceName: "Microphone")]
        let update = CaptionUpdate(
            lane: .single, segmentID: 0, source: "Hello", translation: "Bonjour", isFinal: true, start: 1, end: 2)
        let block = TranscriptFormat.block(for: update, lanes: lanes)

        #expect(block.contains("**[00:01]** · EN: Hello"))
        #expect(block.contains("**[00:01]** · FR: Bonjour"))
    }

    @Test func dayFolderAndFileNames() {
        let calendar = Calendar.current
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ sec: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: sec))!
        }

        #expect(TranscriptFormat.dayFolderName(for: date(2026, 5, 25, 9, 5)) == "2026-05-25 Monday")
        #expect(TranscriptFormat.dayFolderName(for: date(2026, 10, 1, 9, 5)) == "2026-10-01 Thursday")
        #expect(TranscriptFormat.dayFolderName(for: date(2026, 12, 31, 23, 59)) == "2026-12-31 Thursday")
        #expect(TranscriptFormat.fileBaseName(for: date(2026, 5, 25, 9, 5, 3)) == "09.05.03")
        #expect(TranscriptFormat.fileBaseName(for: date(2026, 5, 25, 18, 45, 59)) == "18.45.59")
    }

    @Test func headerShowsLongDateAndSeconds() {
        let started = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 18, minute: 45, second: 7))!
        let header = TranscriptFormat.header(mode: .call, startedAt: started, lanes: callLanes)
        #expect(header.hasPrefix("# Call: Monday 25th May 2026, 18:45:07"))
    }

    @Test func ordinalSuffixes() {
        let expected = [1: "st", 2: "nd", 3: "rd", 4: "th", 11: "th", 12: "th", 13: "th", 21: "st", 22: "nd", 23: "rd", 30: "th", 31: "st"]
        for (day, suffix) in expected {
            #expect(TranscriptFormat.ordinalSuffix(day) == suffix, "day \(day)")
        }
    }

    @Test func sessionStoreWritesOneFileInADayFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tradyr-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let started = Date()
        let store = try SessionStore(root: root, mode: .call, lanes: callLanes, startedAt: started)
        await store.record(CaptionUpdate(
            lane: .them, segmentID: 0, source: "Bonjour", translation: "Hello", isFinal: true, start: 1, end: 2))
        await store.record(CaptionUpdate(
            lane: .them, segmentID: 1, source: "partiel", isFinal: false, start: 3, end: 4))
        await store.finish()

        let day = TranscriptFormat.dayFolderName(for: started)
        let name = TranscriptFormat.fileBaseName(for: started)
        #expect(store.fileURL.deletingLastPathComponent().lastPathComponent == day)
        #expect(store.fileURL.lastPathComponent == "\(name).md")

        let markdown = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(markdown.contains("FR: Bonjour"))
        #expect(markdown.contains("EN: Hello"))
        #expect(!markdown.contains("partiel"))
        #expect(markdown.contains("Ended after"))

        // Nothing but the one markdown file in the day folder.
        let files = try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path)
        #expect(files == ["\(name).md"])
    }

    @Test func sameSecondSessionsDontCollide() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tradyr-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let started = Date()
        let first = try SessionStore(root: root, mode: .single, lanes: [], startedAt: started)
        let second = try SessionStore(root: root, mode: .single, lanes: [], startedAt: started)
        #expect(first.fileURL != second.fileURL)
        #expect(second.fileURL.lastPathComponent.hasSuffix("(2).md"))
    }
}
