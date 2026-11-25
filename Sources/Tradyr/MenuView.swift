import SwiftUI
import Translation
import TradyrCore

struct MenuView: View {
    let model: AppModel

    /// Two-way binding to an `AppModel` property. (`@Bindable` needs a SwiftUI macro plugin that
    /// the command-line tools don't ship, so bindings are built by hand.)
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: binding(\.mode)) {
                Text("Single input").tag(SessionMode.single)
                Text("Phone call").tag(SessionMode.call)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isRunning)

            if model.mode == .call {
                Text("Them: call audio (FR → EN). You: microphone (FR → EN).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                singleOptions
            }

            Button {
                Task { model.isRunning ? await model.stop() : await model.start() }
            } label: {
                Text(model.isRunning ? "Stop" : (model.isStarting ? "Starting…" : "Start"))
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(model.isRunning ? .red : .accentColor)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isStarting)

            HoverRow(model: model, id: "save") {
                Toggle("Save transcript", isOn: binding(\.saveTranscripts))
                    .toggleStyle(.checkbox)
                    .disabled(model.isRunning)
            }
            .padding(.horizontal, -8)  // let the highlight reach the edges of the content area

            if model.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.activeLanes, id: \.self) { lane in
                        HStack(spacing: 8) {
                            Text(lane.label.isEmpty ? "Audio" : lane.label)
                                .font(.caption)
                                .frame(width: 44, alignment: .leading)
                            LevelBar(level: model.laneLevels[lane] ?? 0, tint: .accentColor)
                            if let problem = model.laneProblems[lane] {
                                Text(problem)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else if !model.laneProblems.isEmpty {
                ForEach(Array(model.laneProblems.keys), id: \.self) { lane in
                    Text("\(lane.label.isEmpty ? "Audio" : lane.label): \(model.laneProblems[lane] ?? "")")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Plain text rows that highlight on hover, like a native menu.
            VStack(alignment: .leading, spacing: 0) {
                MenuItem(model: model, id: "packs", title: packsTitle) { model.showLanguagePacks() }
                MenuItem(model: model, id: "history", title: "History") { model.showHistory() }
            }
            .padding(.horizontal, -8)  // let the highlight reach the edges of the content area

            Divider()

            MenuItem(model: model, id: "quit", title: "Quit Tradyr", shortcutKey: "q") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, -8)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            model.refreshApps()
            Task { await model.refreshPackStatus() }
        }
    }

    private var packsTitle: String {
        model.packsReady ? "Language packs… (installed ✓)" : "Language packs… (not installed)"
    }

    @ViewBuilder private var singleOptions: some View {
        Picker("Direction", selection: binding(\.singleDirection)) {
            ForEach(Direction.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .disabled(model.isRunning)

        Picker("Source", selection: binding(\.singleSource)) {
            Text("Microphone (System Input)").tag(SingleSource.microphone)
            Divider()
            Text("All Applications").tag(SingleSource.allApplications)
            Divider()
            ForEach(model.apps) { app in
                Text(app.name).tag(SingleSource.app(bundleID: app.bundleID))
            }
        }
        .disabled(model.isRunning)
    }
}

// MARK: - Menu rows

/// A text-only menu item: no button chrome, with an accent highlight while the pointer is over it.
private struct MenuItem: View {
    let model: AppModel
    let id: String
    let title: String
    /// Command-key shortcut, shown at the right of the row.
    var shortcutKey: Character?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                if let shortcutKey {
                    Text("⌘\(String(shortcutKey).uppercased())")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .hoverHighlight(model: model, id: id)
        .keyboardShortcut(shortcutKey.map { KeyboardShortcut(KeyEquivalent($0), modifiers: .command) })
    }
}

/// Wraps any control (a toggle, say) in the same hover treatment as `MenuItem`.
private struct HoverRow<Content: View>: View {
    let model: AppModel
    let id: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .hoverHighlight(model: model, id: id)
    }
}

private extension View {
    /// A native-menu-style highlight: accent-colored rounded rect with white text while hovered.
    func hoverHighlight(model: AppModel, id: String) -> some View {
        let hovered = model.hoveredItem == id
        return self
            .foregroundStyle(hovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if hovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                }
            }
            .onHover { model.setHovered(id, inside: $0) }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
