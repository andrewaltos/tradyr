import Foundation

/// Who spoke what, and in which languages. Used to label transcript lines.
public struct LaneInfo: Codable, Sendable, Equatable {
    public var lane: Lane
    public var sourceLanguage: String
    public var targetLanguage: String
    public var sourceName: String

    public init(lane: Lane, sourceLanguage: String, targetLanguage: String, sourceName: String) {
        self.lane = lane
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.sourceName = sourceName
    }
}

/// Pure formatting for the human-readable transcript, kept separate from file I/O so it can be tested.
public enum TranscriptFormat {
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Folder name for a day, e.g. "2026-10-12 Monday". The ISO date first makes Finder sort chronologically.
    public static func dayFolderName(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd EEEE"
        return formatter.string(from: date)
    }

    /// File name (without extension) for a session that started at `date`, e.g. "18.45.07".
    /// Colons are avoided because Finder shows them as slashes.
    public static func fileBaseName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d.%02d.%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// Long form used in the file header, e.g. "Sunday 25th May 2026".
    public static func longDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date)
        formatter.dateFormat = "MMMM yyyy"
        let monthYear = formatter.string(from: date)
        let day = calendar.component(.day, from: date)
        return "\(weekday) \(day)\(ordinalSuffix(day)) \(monthYear)"
    }

    static func ordinalSuffix(_ day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    public static func header(
        mode: SessionMode, startedAt: Date, lanes: [LaneInfo], calendar: Calendar = .current
    ) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: startedAt)
        let time = String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let title = mode == .call ? "Call" : "Captions"

        let directions = lanes.map { info -> String in
            let arrow = "\(info.sourceLanguage.uppercased())→\(info.targetLanguage.uppercased())"
            return info.lane == .single ? arrow : "\(info.lane.label): \(arrow)"
        }
        return """
        # \(title): \(longDate(startedAt, calendar: calendar)), \(time)

        Mode: \(mode.rawValue) · \(directions.joined(separator: " · "))


        """
    }

    /// Two lines per final caption: the source text, then its translation.
    public static func block(for update: CaptionUpdate, lanes: [LaneInfo]) -> String {
        let info = lanes.first { $0.lane == update.lane }
        let source = (info?.sourceLanguage ?? "??").uppercased()
        let target = (info?.targetLanguage ?? "??").uppercased()
        let speaker = update.lane == .single ? "" : " \(update.lane.label)"
        let stamp = "**[\(timestamp(update.start))]\(speaker)**"
        let translation = update.translation ?? "(translation unavailable)"

        return """
        \(stamp) · \(source): \(update.source)
        \(stamp) · \(target): \(translation)


        """
    }

    public static func footer(endedAt: Date, duration: TimeInterval) -> String {
        "---\nEnded after \(timestamp(duration)).\n"
    }
}
