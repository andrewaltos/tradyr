import AppKit
import Observation
import TradyrCore

/// One session file in the History list.
struct HistorySession: Identifiable, Hashable {
    let url: URL
    /// "21:17:07" (or "20:04" for sessions saved before seconds were recorded).
    let time: String
    let kind: String
    let duration: String?

    var id: URL { url }

    var subtitle: String {
        [kind, duration].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A day folder and its sessions, newest first.
struct HistoryDay: Identifiable {
    let name: String
    let sessions: [HistorySession]

    var id: String { name }
}

/// What the History window shows: every saved session, grouped by day, and the selected one rendered.
@MainActor
@Observable
final class HistoryModel {
    private(set) var days: [HistoryDay] = []
    private(set) var selection: URL?
    private(set) var document: TranscriptDocument?
    private(set) var loadError: String?

    /// Set by the window so the Close button can close it.
    var onClose: () -> Void = {}

    private let root: URL

    init(root: URL = SessionStore.defaultRoot) {
        self.root = root
    }

    var isEmpty: Bool { days.isEmpty }

    /// Re-reads the sessions folder, keeping the current selection if it still exists.
    func reload() {
        let fm = FileManager.default
        let dayURLs = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

        var found: [HistoryDay] = []
        for dayURL in dayURLs {
            guard (try? dayURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = (try? fm.contentsOfDirectory(
                at: dayURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let sessions = files
                .filter { $0.pathExtension.lowercased() == "md" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map(Self.session(at:))
            if !sessions.isEmpty { found.append(HistoryDay(name: dayURL.lastPathComponent, sessions: sessions)) }
        }
        // "2026-10-12 Monday" sorts chronologically, so newest day first is reverse order.
        days = found.sorted { $0.name > $1.name }

        let all = days.flatMap(\.sessions)
        if let selection, all.contains(where: { $0.url == selection }) {
            load(selection)
        } else {
            select(all.first?.url)
        }
    }

    func select(_ url: URL?) {
        selection = url
        guard let url else {
            document = nil
            return
        }
        load(url)
    }

    /// Opens the folder holding the selected session with it highlighted, or the sessions folder.
    func openFolder() {
        if let selection {
            NSWorkspace.shared.activateFileViewerSelecting([selection])
            return
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    // MARK: - Loading

    private func load(_ url: URL) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            document = TranscriptDocument.parse(markdown)
            loadError = nil
        } catch {
            document = nil
            loadError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private static func session(at url: URL) -> HistorySession {
        let parsed = (try? String(contentsOf: url, encoding: .utf8)).map(TranscriptDocument.parse)
        return HistorySession(
            url: url,
            time: displayTime(fromFileName: url.deletingPathExtension().lastPathComponent),
            kind: parsed?.kind ?? "Session",
            duration: parsed?.duration)
    }

    /// "21.17.07" → "21:17:07", "20.03 (2)" → "20:03 (2)".
    static func displayTime(fromFileName name: String) -> String {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        let time = parts[0].replacingOccurrences(of: ".", with: ":")
        return parts.count > 1 ? "\(time) \(parts[1])" : time
    }
}
