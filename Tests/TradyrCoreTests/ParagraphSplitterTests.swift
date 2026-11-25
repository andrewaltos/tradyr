import Foundation
import Testing
import NaturalLanguage
@testable import TradyrCore

@Suite struct ParagraphSplitterTests {
    let splitter = ParagraphSplitter()

    @Test func emptyTextHasNoParagraphs() {
        #expect(splitter.split("").isEmpty)
        #expect(splitter.split("   \n ").isEmpty)
    }

    @Test func questionAndAnswerAreSeparated() {
        let text = "Pouvez-vous nous expliquer votre projet ? Bien sûr, nous construisons une application."
        let paragraphs = splitter.split(text, language: .french)

        #expect(paragraphs.count == 2)
        #expect(paragraphs.first == "Pouvez-vous nous expliquer votre projet ?")
        #expect(paragraphs.last == "Bien sûr, nous construisons une application.")
    }

    @Test func englishQuestionAlsoBreaks() {
        let paragraphs = splitter.split("How did you start? We began in a garage. It was small.", language: .english)
        #expect(paragraphs == ["How did you start?", "We began in a garage. It was small."])
    }

    @Test func longAnswerIsSplitAfterThreeSentences() {
        let text = "One is first. Two is second. Three is third. Four is fourth. Five is fifth."
        let paragraphs = splitter.split(text, language: .english)

        #expect(paragraphs.count == 2)
        #expect(paragraphs[0] == "One is first. Two is second. Three is third.")
        #expect(paragraphs[1] == "Four is fourth. Five is fifth.")
    }

    @Test func sentenceStillBeingSpokenNeverClosesAParagraph() {
        // Three sentences, the third has no ending yet: it must stay open so it keeps growing in place.
        let text = "Une phrase. Deux phrases. Et la troisième est encore en cours"
        let paragraphs = splitter.split(text, language: .french)
        #expect(paragraphs == ["Une phrase. Deux phrases. Et la troisième est encore en cours"])
    }

    @Test func closedParagraphsDoNotChangeWhenTextGrows() {
        let before = splitter.split("Quelle est votre idée ? Nous", language: .french)
        let after = splitter.split("Quelle est votre idée ? Nous voulons traduire en direct.", language: .french)

        #expect(before.first == after.first)
        #expect(after.count == 2)
    }

    @Test func questionBreakCanBeDisabled() {
        var custom = ParagraphSplitter()
        custom.breakAfterQuestion = false
        let paragraphs = custom.split("Why? Because.", language: .english)
        #expect(paragraphs == ["Why? Because."])
    }
}
