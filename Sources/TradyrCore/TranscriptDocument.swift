import Foundation

/// A parsed session file, for showing in the History window.
///
/// Reads the format written by `TranscriptFormat`. Anything it doesn't recognise is kept in `notes`
/// rather than dropped, so a hand-edited file still shows everything.
public struct TranscriptDocument: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: Int
        /// Seconds since the session started, as written ("00:42" or "1:02:05").
        public var time: String
        /// "You", "Them", or nil for single-input sessions.
        public var speaker: String?
        public var sourceLanguage: String
        public var source: String
        public var targetLanguage: String?
        public var translation: String?
    }

    public var title: String?
    public var details: String?
    public var entries: [Entry] = []
    public var footer: String?
    public var notes: [String] = []

    public init() {}

    /// "Call" or "Captions", from the title.
    public var kind: String? {
        title.flatMap { $0.split(separator: ":").first.map(String.init) }
    }

    /// "23:12" from a footer such as "Ended after 23:12.".
    public var duration: String? {
        guard let footer, let range = footer.range(of: "Ended after ") else { return nil }
        return String(footer[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    // MARK: Parsing

    private static let entryPattern = try! NSRegularExpression(
        pattern: #"^\*\*\[([0-9:]+)\]( [^*]+)?\*\* · ([A-Za-z]{2,3}): (.*)$"#)

    private struct EntryLine {
        let time: String
        let speaker: String?
        let language: String
        let text: String
    }

    private static func entryLine(_ line: String) -> EntryLine? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = entryPattern.firstMatch(in: line, range: range) else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: line).map { String(line[$0]) }
        }
        guard let time = group(1), let language = group(3), let text = group(4) else { return nil }
        let speaker = group(2)?.trimmingCharacters(in: .whitespaces)
        return EntryLine(time: time, speaker: speaker?.isEmpty == true ? nil : speaker, language: language, text: text)
    }

    public static func parse(_ markdown: String) -> TranscriptDocument {
        var document = TranscriptDocument()
        let lines = markdown.components(separatedBy: .newlines)
        var index = 0
        var expectFooter = false

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty { continue }

            if line.hasPrefix("# "), document.title == nil {
                document.title = String(line.dropFirst(2))
            } else if line == "---" {
                expectFooter = true
            } else if expectFooter {
                document.footer = line
                expectFooter = false
            } else if let source = entryLine(line) {
                // A caption is two lines: the source text, then its translation.
                var entry = Entry(
                    id: document.entries.count, time: source.time, speaker: source.speaker,
                    sourceLanguage: source.language.uppercased(), source: source.text)
                if index < lines.count, let next = entryLine(lines[index].trimmingCharacters(in: .whitespaces)),
                   next.time == source.time, next.speaker == source.speaker, next.language != source.language {
                    entry.targetLanguage = next.language.uppercased()
                    let unavailable = "(translation unavailable)"
                    entry.translation = next.text == unavailable ? nil : next.text
                    index += 1
                }
                document.entries.append(entry)
            } else if document.details == nil, line.hasPrefix("Mode:") {
                document.details = line
            } else {
                document.notes.append(line)
            }
        }
        return document
    }
}
