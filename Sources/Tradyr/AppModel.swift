import AppKit
import Observation
import SwiftUI
import Translation
import TradyrCore

/// What the single-input mode listens to.
enum SingleSource: Hashable {
    case microphone
    case allApplications
    case app(bundleID: String)
}

/// A running, user-facing application, for the source picker.
struct RunningApp: Identifiable, Hashable {
    let name: String
    let bundleID: String

    var id: String { bundleID }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var mode: SessionMode = .single
    var singleDirection: Direction = .frToEn
    var singleSource: SingleSource = .microphone
    var saveTranscripts = true

    private(set) var isRunning = false
    private(set) var isStarting = false
    private(set) var status: String?
    /// Every caption of the session in chronological order, both lanes interleaved.
    private(set) var timeline: [CaptionUpdate] = []
    private(set) var apps: [RunningApp] = []
    /// The menu row the pointer is over, for hover highlighting.
    private(set) var hoveredItem: String?
    /// Latest audio level per lane, linear RMS 0…1. Lets you see whether audio reaches each lane.
    private(set) var laneLevels: [Lane: Float] = [:]
    /// Problems per lane (source couldn't start, recogniser failed, no audio arriving).
    private(set) var laneProblems: [Lane: String] = [:]

    /// Set to ask the system to download the FR ↔ EN language packs (drives `.translationTask`).
    var packConfiguration: TranslationSession.Configuration?

    private var pipelines: [LanePipeline] = []
    private var tasks: [Task<Void, Never>] = []
    private var store: SessionStore?
    private var clock: SessionClock?
    private var overlay: OverlayPanel?
    private var packsWindow: NSWindow?
    private var historyWindow: NSWindow?
    let history = HistoryModel()
    private var watchdog: Task<Void, Never>?
    private var lanesWithAudio: Set<Lane> = []

    var activeLanes: [Lane] { mode == .call ? [.them, .you] : [.single] }

    // MARK: - Session lifecycle

    func start() async {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        status = nil
        timeline = []

        let clock = SessionClock()
        let built = makePipelines(clock: clock)

        // Fail early, with a useful message, if the translation packs aren't installed.
        for direction in Set(built.map(\.direction)) {
            let availability = await SegmentTranslator.status(from: direction.sourceLanguage, to: direction.targetLanguage)
            if availability != .installed {
                status = "Translation \(direction.label) isn't installed yet. Open “Language packs…” and download them."
                return
            }
        }

        let infos = built.map {
            LaneInfo(
                lane: $0.lane, sourceLanguage: $0.direction.sourceCode,
                targetLanguage: $0.direction.targetCode, sourceName: $0.source.name)
        }
        var store: SessionStore?
        if saveTranscripts {
            do {
                store = try SessionStore(mode: mode, lanes: infos, startedAt: clock.startedAt)
            } catch {
                status = "Couldn't create the session folder: \(error.localizedDescription)"
                return
            }
        }

        self.clock = clock
        self.store = store
        laneLevels = [:]
        laneProblems = [:]
        lanesWithAudio = []
        status = nil

        // Bring the sources up one at a time, call audio first. Starting a process tap changes the
        // audio hardware configuration, and a mic engine that's already running can be knocked over by it.
        var ready: [LanePipeline] = []
        for pipeline in built {
            do {
                try await pipeline.prepare()
                ready.append(pipeline)
            } catch {
                laneProblems[pipeline.lane] = error.localizedDescription
            }
        }
        guard !ready.isEmpty else {
            status = laneProblems.values.first ?? "Couldn't start any audio source."
            await store?.finish()
            self.store = nil
            return
        }

        self.pipelines = ready
        isRunning = true
        showOverlay()

        for pipeline in ready {
            tasks.append(Task { [weak self] in
                do {
                    for try await update in pipeline.run() {
                        await store?.record(update)
                        self?.apply(update)
                    }
                } catch {
                    self?.fail(pipeline.lane, error)
                }
            })
        }
        startWatchdog()
    }

    /// After a few seconds, flag any lane that has heard nothing at all. Silence from the source
    /// (muted mic, wrong input device, nobody talking yet) is otherwise indistinguishable from "broken".
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            for pipeline in self.pipelines where !self.lanesWithAudio.contains(pipeline.lane) {
                if self.laneProblems[pipeline.lane] == nil {
                    self.laneProblems[pipeline.lane] =
                        "No sound from \(pipeline.source.name) yet. Check the input device and that nothing is muted."
                }
            }
        }
    }

    private func recordLevel(_ level: Float, for lane: Lane) {
        laneLevels[lane] = level
        if AudioLevel.decibels(level) > -70 {
            lanesWithAudio.insert(lane)
            if laneProblems[lane]?.hasPrefix("No sound") == true { laneProblems[lane] = nil }
        }
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        watchdog?.cancel()
        watchdog = nil
        // Ending the audio stream makes the recogniser finalize the phrase in progress.
        // Give that a moment to land in the transcript before tearing the tasks down.
        for pipeline in pipelines { await pipeline.stop() }
        let running = tasks
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for task in running { await task.value } }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
        for task in running { task.cancel() }
        tasks = []
        pipelines = []
        await store?.finish()
        store = nil
        history.reload()
        overlay?.orderOut(nil)
        laneLevels = [:]
        status = nil
    }

    private func apply(_ update: CaptionUpdate) {
        // An empty source retracts a paragraph that the recogniser has since merged or re-split.
        if update.source.isEmpty {
            timeline.removeAll { $0.id == update.id }
            return
        }
        if let index = timeline.lastIndex(where: { $0.id == update.id }) {
            // A live update that arrives after the final must not overwrite it.
            if timeline[index].isFinal, !update.isFinal { return }
            // Same paragraph, revised by the recogniser or now translated: update in place.
            timeline[index] = update
        } else {
            let position = timeline.lastIndex(where: { $0.start <= update.start }).map { $0 + 1 } ?? 0
            timeline.insert(update, at: position)
            if timeline.count > 1_000 { timeline.removeFirst(timeline.count - 1_000) }
        }
    }

    private func fail(_ lane: Lane, _ error: Error) {
        laneProblems[lane] = error.localizedDescription
    }

    private func makePipelines(clock: SessionClock) -> [LanePipeline] {
        switch mode {
        case .call:
            return [
                LanePipeline(
                    lane: .them,
                    source: ProcessTapSource(
                        bundleIDs: [ProcessTapSource.callAudioBundleID], name: ProcessTapSource.callAudioBundleID),
                    direction: .frToEn, clock: clock, onLevel: levelHandler(for: .them)),
                LanePipeline(
                    lane: .you, source: MicSource(), direction: .frToEn, clock: clock,
                    onLevel: levelHandler(for: .you)),
            ]
        case .single:
            return [LanePipeline(
                lane: .single, source: singleAudioSource(), direction: singleDirection, clock: clock,
                onLevel: levelHandler(for: .single))]
        }
    }

    private func singleAudioSource() -> any AudioSource {
        switch singleSource {
        case .microphone:
            return MicSource()
        case .allApplications:
            return ProcessTapSource(target: .allSystemAudio, name: "All applications")
        case .app(let bundleID):
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            let name = running?.localizedName ?? apps.first { $0.bundleID == bundleID }?.name ?? bundleID
            return ProcessTapSource(
                target: .application(bundleID: bundleID, pid: running?.processIdentifier), name: name)
        }
    }

    /// Hops audio-thread level callbacks onto the main actor, at most ~10 per second per lane.
    private nonisolated func levelHandler(for lane: Lane) -> @Sendable (Float) -> Void {
        let gate = LevelGate()
        return { level in
            guard gate.shouldEmit() else { return }
            Task { @MainActor in AppModel.shared.recordLevel(level, for: lane) }
        }
    }

    // MARK: - Overlay

    /// The overlay is shown for every session and hidden when it ends.
    private func showOverlay() {
        if overlay == nil { overlay = OverlayPanel(model: self) }
        overlay?.orderFrontRegardless()
    }

    // MARK: - History

    /// Opens the History window: saved sessions on the left, the selected one rendered on the right.
    func showHistory() {
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false)
            window.title = "History"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView(model: history))
            window.setFrameAutosaveName("TradyrHistory")
            window.center()
            history.onClose = { [weak window] in window?.close() }
            historyWindow = window
        }
        history.reload()
        NSApplication.shared.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Language packs

    enum PackStatus: Equatable {
        case checking
        case installed
        case needsDownload
        case unsupported
    }

    /// Install state of the translation models, per direction.
    private(set) var packStatus: [Direction: PackStatus] = [:]
    private(set) var packDownloading = false
    private(set) var packMessage: String?

    var packsReady: Bool {
        Direction.allCases.allSatisfy { packStatus[$0] == .installed }
    }

    func refreshPackStatus() async {
        for direction in Direction.allCases {
            let status = await SegmentTranslator.status(from: direction.sourceLanguage, to: direction.targetLanguage)
            switch status {
            case .installed: packStatus[direction] = .installed
            case .supported: packStatus[direction] = .needsDownload
            default: packStatus[direction] = .unsupported
            }
        }
    }

    /// Opens the language packs window. It stays open, unlike the menu popover, so the system's
    /// download sheet has a window to attach to.
    func showLanguagePacks() {
        if packsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.title = "Language packs"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LanguagePacksView(model: self))
            window.center()
            packsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        packsWindow?.makeKeyAndOrderFront(nil)
        Task { await refreshPackStatus() }
    }

    /// Asks the system to download the FR ↔ EN models. Drives `.translationTask` in `LanguagePacksView`.
    func requestLanguagePacks() {
        packMessage = nil
        if packConfiguration != nil {
            packConfiguration?.invalidate()
        } else {
            packConfiguration = TranslationSession.Configuration(
                source: Direction.frToEn.sourceLanguage, target: Direction.frToEn.targetLanguage)
        }
    }

    func packDownloadStarted() {
        packDownloading = true
        packMessage = "Waiting for the system download prompt…"
    }

    func packDownloadFinished(error: Error?) async {
        packDownloading = false
        await refreshPackStatus()
        if let error {
            packMessage = "Download didn't complete: \(error.localizedDescription)"
        } else if packsReady {
            packMessage = "Language packs installed."
        } else {
            packMessage = "The download prompt was dismissed. Try again, or install them in System Settings → General → Language & Region → Translation Languages."
        }
    }

    // MARK: - Source list for single-input mode

    func setHovered(_ id: String, inside: Bool) {
        if inside {
            hoveredItem = id
        } else if hoveredItem == id {
            hoveredItem = nil
        }
    }

    /// Refreshes the list of running, user-facing apps for the source picker.
    func refreshApps() {
        var list = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return RunningApp(name: name, bundleID: bundleID)
            }

        // Keep the current choice in the list even if that app has quit, so the picker still shows it.
        if case .app(let bundleID) = singleSource, !list.contains(where: { $0.bundleID == bundleID }) {
            list.append(RunningApp(name: "\(bundleID) (not running)", bundleID: bundleID))
        }
        apps = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Rate limiter for level updates coming off the audio thread.
private final class LevelGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast

    func shouldEmit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return false }
        last = now
        return true
    }
}
