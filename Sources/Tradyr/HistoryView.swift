import SwiftUI
import TradyrCore

/// The History window: sessions grouped by day on the left, the selected session rendered on the right.
struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                sidebar
                    .frame(minWidth: 210, idealWidth: 240, maxWidth: 360)
                detail
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Spacer()
                Button("Open folder") { model.openFolder() }
                Button("Close") { model.onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 680, minHeight: 420)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
            ForEach(model.days) { day in
                Section(day.name) {
                    ForEach(day.sessions) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.time)
                                .font(.system(.body, design: .monospaced))
                            Text(session.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(session.url)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let error = model.loadError {
            Text(error)
                .foregroundStyle(.red)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let document = model.document {
            DocumentView(document: document)
        } else {
            Text(model.isEmpty ? "Sessions you record will appear here." : "Select a session.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A session rendered as readable text instead of raw markdown.
private struct DocumentView: View {
    let document: TranscriptDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = document.title {
                        Text(title)
                            .font(.title2.weight(.semibold))
                    }
                    if let details = document.details {
                        Text(details)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)

                if document.entries.isEmpty {
                    Text("No captions were recorded in this session.")
                        .foregroundStyle(.secondary)
                }

                ForEach(document.entries) { entry in
                    EntryRow(entry: entry)
                }

                ForEach(Array(document.notes.enumerated()), id: \.offset) { _, note in
                    Text(note).textSelection(.enabled)
                }

                if let footer = document.footer {
                    Divider()
                    Text(footer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EntryRow: View {
    let entry: TranscriptDocument.Entry

    private var accent: Color {
        switch entry.speaker {
        case "Them": .cyan
        case "You": .orange
        default: .primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if let speaker = entry.speaker {
                    Text(speaker.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Text(entry.time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 52, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.source)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let translation = entry.translation {
                    Text(translation)
                        .font(.title3.weight(.medium))
                } else {
                    Text("Translation unavailable")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.tertiary)
                }
            }
            .textSelection(.enabled)
        }
    }
}
