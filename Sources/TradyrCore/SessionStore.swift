import Foundation

/// Writes one session to a single markdown file, incrementally, so a crash loses at most the last few seconds.
///
/// ```
/// <root>/2026-05-25 Monday/18.45.07.md
/// ```
/// Sessions are grouped in a folder per day, and each file is named after the time (to the second) the session started.
/// Audio is never stored.
public actor SessionStore {
    public nonisolated let fileURL: URL

    private let lanes: [LaneInfo]
    private let startedAt: Date
    private let handle: FileHandle
    private var finished = false

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tradyr/Sessions", isDirectory: true)
    }

    public init(root: URL = SessionStore.defaultRoot, mode: SessionMode, lanes: [LaneInfo], startedAt: Date = Date()) throws {
        let fm = FileManager.default
        let dayFolder = root.appendingPathComponent(TranscriptFormat.dayFolderName(for: startedAt), isDirectory: true)
        try fm.createDirectory(at: dayFolder, withIntermediateDirectories: true)

        // Two sessions can start in the same second.
        let base = TranscriptFormat.fileBaseName(for: startedAt)
        var candidate = dayFolder.appendingPathComponent("\(base).md")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dayFolder.appendingPathComponent("\(base) (\(suffix)).md")
            suffix += 1
        }
        fm.createFile(atPath: candidate.path, contents: nil)

        self.fileURL = candidate
        self.lanes = lanes
        self.startedAt = startedAt
        self.handle = try FileHandle(forWritingTo: candidate)

        try handle.write(contentsOf: Data(TranscriptFormat.header(mode: mode, startedAt: startedAt, lanes: lanes).utf8))
    }

    /// Records a caption. Volatile (non-final) updates are ignored.
    public func record(_ update: CaptionUpdate) {
        guard update.isFinal, !finished else { return }
        do {
            try handle.write(contentsOf: Data(TranscriptFormat.block(for: update, lanes: lanes).utf8))
        } catch {
            // Disk errors shouldn't take down live captions.
            NSLog("SessionStore: write failed: \(error)")
        }
    }

    public func finish(endedAt: Date = Date()) {
        guard !finished else { return }
        finished = true
        let duration = endedAt.timeIntervalSince(startedAt)
        try? handle.write(contentsOf: Data(TranscriptFormat.footer(endedAt: endedAt, duration: duration).utf8))
        try? handle.close()
    }
}
