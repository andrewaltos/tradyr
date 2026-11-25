import Foundation
import NaturalLanguage

/// Splits recognised speech into paragraphs.
///
/// The recogniser only commits a final result after a long silence, and live results carry no word
/// timing, so a whole interview exchange otherwise arrives as one block. Punctuation is available live,
/// so paragraphs are cut from that: always after a question (usually a change of speaker in an
/// interview), and after a few sentences otherwise so long answers don't become a wall of text.
public struct ParagraphSplitter: Sendable {
    /// A paragraph is closed after this many complete sentences.
    public var maxSentences = 3
    /// A paragraph is closed once it is this long and its last sentence is complete.
    public var maxCharacters = 280
    /// Close the paragraph after a question.
    public var breakAfterQuestion = true

    public init() {}

    /// - Parameter language: the language of the text, which helps with sentence boundaries.
    public func split(_ text: String, language: NLLanguage? = nil) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        if let language { tokenizer.setLanguage(language) }

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }

        var paragraphs: [String] = []
        var current: [String] = []
        for sentence in sentences {
            current.append(sentence)

            let complete = Self.isComplete(sentence)
            let length = current.joined(separator: " ").count

            let closes = complete && (
                (breakAfterQuestion && Self.isQuestion(sentence))
                    || current.count >= maxSentences
                    || length >= maxCharacters)
            if closes {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs
    }

    private static let closers: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]"]

    private static func terminal(of sentence: String) -> Character? {
        sentence.last { !closers.contains($0) }
    }

    static func isComplete(_ sentence: String) -> Bool {
        guard let char = terminal(of: sentence) else { return false }
        return ".?!…？！。".contains(char)
    }

    static func isQuestion(_ sentence: String) -> Bool {
        guard let char = terminal(of: sentence) else { return false }
        return char == "?" || char == "？"
    }
}
