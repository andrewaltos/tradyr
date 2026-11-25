import Foundation

/// Which speaker a caption belongs to.
public enum Lane: String, Codable, Sendable, CaseIterable {
    case you
    case them
    case single

    public var label: String {
        switch self {
        case .you: "You"
        case .them: "Them"
        case .single: ""
        }
    }
}

public enum SessionMode: String, Codable, Sendable, CaseIterable {
    case single
    case call
}

/// Translation direction. Both call lanes use `.frToEn`; single-input mode lets the user pick.
public enum Direction: String, Codable, Sendable, CaseIterable {
    case frToEn
    case enToFr

    public var sourceLocale: Locale {
        Locale(identifier: self == .frToEn ? "fr-FR" : "en-US")
    }

    public var sourceLanguage: Locale.Language { Locale.Language(identifier: self == .frToEn ? "fr" : "en") }
    public var targetLanguage: Locale.Language { Locale.Language(identifier: self == .frToEn ? "en" : "fr") }
    public var sourceCode: String { self == .frToEn ? "fr" : "en" }
    public var targetCode: String { self == .frToEn ? "en" : "fr" }
    public var label: String { self == .frToEn ? "FR → EN" : "EN → FR" }
}

/// One caption on the timeline. Volatile updates share a `segmentID` until a final one arrives.
public struct CaptionUpdate: Sendable, Equatable {
    public var lane: Lane
    /// The recogniser's phrase this belongs to. It advances each time the recogniser finalizes.
    public var segmentID: Int
    /// Index of the paragraph within the segment. One phrase can be split into several paragraphs.
    public var paragraph: Int
    public var source: String
    public var translation: String?
    public var isFinal: Bool
    /// Seconds since the session started, at the start of the utterance.
    public var start: TimeInterval
    public var end: TimeInterval
    /// Set when translation failed, so the UI can say why the second line is missing.
    public var warning: String?

    public init(
        lane: Lane, segmentID: Int, paragraph: Int = 0, source: String, translation: String? = nil,
        isFinal: Bool, start: TimeInterval, end: TimeInterval, warning: String? = nil
    ) {
        self.lane = lane
        self.segmentID = segmentID
        self.paragraph = paragraph
        self.source = source
        self.translation = translation
        self.isFinal = isFinal
        self.start = start
        self.end = end
        self.warning = warning
    }
}

extension CaptionUpdate: Identifiable {
    /// A phrase keeps its identity while the recogniser revises it, so the list updates in place.
    public var id: String { "\(lane.rawValue)-\(segmentID)-\(paragraph)" }
}

/// Shared time base so two lanes can be merged onto one timeline.
public struct SessionClock: Sendable {
    public let startedAt: Date

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    public func now() -> TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}
