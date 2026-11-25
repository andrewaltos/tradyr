import SwiftUI
import Translation
import TradyrCore

/// Shows whether the FR ↔ EN translation models are installed and downloads them.
///
/// Lives in its own window because the system's download sheet needs a window that stays open;
/// the menu popover closes as soon as the sheet appears.
struct LanguagePacksView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Translation language packs")
                .font(.headline)
            Text("Translation runs on this Mac. Each direction needs the French and English models installed once.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Direction.allCases, id: \.self) { direction in
                    HStack {
                        Text(direction.label)
                        Spacer()
                        Text(label(for: model.packStatus[direction] ?? .checking))
                            .foregroundStyle(color(for: model.packStatus[direction] ?? .checking))
                    }
                }
            }

            HStack {
                Button(model.packDownloading ? "Downloading…" : "Download French ↔ English") {
                    model.requestLanguagePacks()
                }
                .disabled(model.packDownloading || model.packsReady)
                if model.packDownloading { ProgressView().controlSize(.small) }
            }

            if let message = model.packMessage {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 400, height: 260, alignment: .topLeading)
        .translationTask(model.packConfiguration) { session in
            model.packDownloadStarted()
            do {
                try await session.prepareTranslation()
                await model.packDownloadFinished(error: nil)
            } catch {
                await model.packDownloadFinished(error: error)
            }
        }
    }

    private func label(for status: AppModel.PackStatus) -> String {
        switch status {
        case .checking: "Checking…"
        case .installed: "Installed ✓"
        case .needsDownload: "Not installed"
        case .unsupported: "Not supported"
        }
    }

    private func color(for status: AppModel.PackStatus) -> Color {
        switch status {
        case .installed: .green
        case .needsDownload: .orange
        case .unsupported: .red
        case .checking: .secondary
        }
    }
}
