import Foundation
import Testing
@testable import TradyrCore

@Suite struct TranscriptDocumentTests {
    let call = """
    # Call: Monday 12th October 2026, 20:04:48

    Mode: call · Them: FR→EN · You: FR→EN

    **[00:04] Them** · FR: Bonjour, je vous appelle.
    **[00:04] Them** · EN: Hello, I'm calling you.

    **[00:11] You** · FR: Oui, merci.
    **[00:11] You** · EN: (translation unavailable)

    ---
    Ended after 23:12.
    """

    @Test func parsesTitleDetailsAndFooter() {
        let document = TranscriptDocument.parse(call)

        #expect(document.title == "Call: Monday 12th October 2026, 20:04:48")
        #expect(document.kind == "Call")
        #expect(document.details == "Mode: call · Them: FR→EN · You: FR→EN")
        #expect(document.footer == "Ended after 23:12.")
        #expect(document.duration == "23:12")
        #expect(document.notes.isEmpty)
    }

    @Test func pairsSourceAndTranslationLines() {
        let document = TranscriptDocument.parse(call)

        #expect(document.entries.count == 2)
        #expect(document.entries[0].speaker == "Them")
        #expect(document.entries[0].time == "00:04")
        #expect(document.entries[0].sourceLanguage == "FR")
        #expect(document.entries[0].source == "Bonjour, je vous appelle.")
        #expect(document.entries[0].targetLanguage == "EN")
        #expect(document.entries[0].translation == "Hello, I'm calling you.")
    }

    @Test func missingTranslationBecomesNil() {
        let document = TranscriptDocument.parse(call)
        #expect(document.entries[1].speaker == "You")
        #expect(document.entries[1].translation == nil)
    }

    @Test func singleInputHasNoSpeaker() {
        let document = TranscriptDocument.parse("""
        # Captions: Monday 12th October 2026, 20:09:14

        Mode: single · FR→EN

        **[00:01]** · FR: Bonjour
        **[00:01]** · EN: Hello
        """)

        #expect(document.kind == "Captions")
        #expect(document.entries.count == 1)
        #expect(document.entries[0].speaker == nil)
        #expect(document.entries[0].translation == "Hello")
        #expect(document.footer == nil)
    }

    @Test func emptySessionHasNoEntries() {
        let document = TranscriptDocument.parse("# Captions: Monday 12th October 2026, 20:02\n\nMode: single · FR→EN\n\n---\nEnded after 00:11.\n")
        #expect(document.entries.isEmpty)
        #expect(document.duration == "00:11")
    }

    @Test func unrecognisedLinesAreKept() {
        let document = TranscriptDocument.parse("# Call: x\n\nMode: call\n\nA note I added by hand.\n")
        #expect(document.notes == ["A note I added by hand."])
    }
}
