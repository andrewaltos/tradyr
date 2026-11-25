// Runs an audio file through the full pipeline (recognise → translate) and prints each update.
//
//   tradyr-probe <audio file> [fr|en] [lanes]
//
// `fr` (default) translates French → English, `en` translates English → French.
// `lanes` runs that many pipelines on the same file at once, to check concurrent recognisers.

import AppKit
import Foundation
import TradyrCore

let arguments = CommandLine.arguments

// `tradyr-probe --apps` lists running apps and the audio processes that belong to each.
if arguments.count == 2, arguments[1] == "--apps" {
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        guard let bundleID = app.bundleIdentifier else { continue }
        let processes = CoreAudioSystem.audioProcesses(forApplication: bundleID, pid: app.processIdentifier)
        let detail = processes.isEmpty
            ? "(no audio process)"
            : processes.map { "\($0.bundleID) [\($0.pid)]\($0.isRunningOutput ? " ▶" : "")" }.joined(separator: ", ")
        print("\(app.localizedName ?? bundleID): \(detail)")
    }
    exit(0)
}

// `tradyr-probe --parse <session.md>...` shows how the History window will read session files.
if arguments.count >= 3, arguments[1] == "--parse" {
    for path in arguments.dropFirst(2) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("\(path): unreadable")
            continue
        }
        let document = TranscriptDocument.parse(text)
        print("\(URL(fileURLWithPath: path).lastPathComponent): \(document.kind ?? "?"), \(document.entries.count) entries, "
            + "duration \(document.duration ?? "-"), \(document.notes.count) unparsed line(s)")
        for entry in document.entries.prefix(2) {
            print("    [\(entry.time)] \(entry.speaker ?? "-") \(entry.sourceLanguage): \(entry.source.prefix(50))")
            print("             → \(entry.translation?.prefix(50) ?? "(none)")")
        }
    }
    exit(0)
}

guard arguments.count >= 2 else {
    print("usage: tradyr-probe <audio file> [fr|en]")
    exit(2)
}

let direction: Direction = arguments.count > 2 && arguments[2] == "en" ? .enToFr : .frToEn
let laneCount = arguments.count > 3 ? Int(arguments[3]) ?? 1 : 1
let clock = SessionClock()

print("direction \(direction.label), file \(arguments[1]), lanes \(laneCount)")

await withTaskGroup(of: Void.self) { group in
    for index in 0..<laneCount {
        group.addTask {
            let pipeline = LanePipeline(
                lane: .single,
                source: FileSource(url: URL(fileURLWithPath: arguments[1])),
                direction: direction,
                clock: clock)
            var first: TimeInterval?
            var finals = 0
            var live = 0
            var blanked = 0                       // a translation that went blank after being shown
            var seenTranslation: Set<String> = []  // "segment-paragraph" keys that have shown text
            do {
                for try await update in pipeline.run() {
                    if first == nil { first = clock.now() }
                    let key = update.id
                    if update.source.isEmpty { continue }
                    if update.isFinal {
                        finals += 1
                        print("[lane \(index)] FINAL  #\(update.segmentID).\(update.paragraph) [\(String(format: "%5.1f", update.start))s]")
                        print("            \(update.source)")
                        print("          → \(update.translation ?? "(none)")")
                    } else {
                        live += 1
                        if update.translation != nil { seenTranslation.insert(key) }
                        else if seenTranslation.contains(key) { blanked += 1 }
                    }
                }
                print("[lane \(index)] done: first result at \(first.map { String(format: "%.1fs", $0) } ?? "never"), \(finals) final paragraph(s), \(live) live updates, \(blanked) translation blank-outs")
            } catch {
                print("[lane \(index)] ERROR: \(error)")
            }
        }
    }
}
