import SwiftUI
import TradyrCore

/// Caption history, newest at the bottom, as one chronological list.
/// In call mode each entry is labelled and coloured by speaker.
struct OverlayView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.15))
            history
        }
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip()
                .frame(width: 18, height: 18)
                .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ForEach(model.activeLanes, id: \.self) { lane in
                HStack(spacing: 6) {
                    if !lane.label.isEmpty {
                        Text(lane.label.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(OverlayStyle.accent(for: lane))
                    }
                    LevelBar(level: model.laneLevels[lane] ?? 0, tint: OverlayStyle.accent(for: lane))
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.stop() }
            } label: {
                Label("Stop translation", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Dragging the header moves the window. (The rest of the window drags via its background.)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
    }

    // MARK: History

    private var history: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(model.laneProblems.keys), id: \.self) { lane in
                    Text("\(lane.label.isEmpty ? "Audio" : lane.label): \(model.laneProblems[lane] ?? "")")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.timeline.isEmpty, model.laneProblems.isEmpty {
                    Text("Listening…")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.4))
                }

                ForEach(model.timeline) { entry in
                    EntryView(entry: entry, showsSpeaker: model.mode == .call)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Stay pinned to the newest caption; scrolling up to read history holds your place.
        .defaultScrollAnchor(.bottom)
    }
}

private struct EntryView: View {
    let entry: CaptionUpdate
    let showsSpeaker: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if showsSpeaker {
                    Text(entry.lane.label.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(OverlayStyle.accent(for: entry.lane))
                }
                Text(TranscriptFormat.timestamp(entry.start))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(width: 44, alignment: .leading)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.source)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                Text(entry.translation ?? "…")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(OverlayStyle.accent(for: entry.lane))
            }
            .opacity(entry.isFinal ? 1 : 0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum OverlayStyle {
    static func accent(for lane: Lane) -> Color {
        switch lane {
        case .them: .cyan
        case .you: .orange
        case .single: .white
        }
    }
}

/// A thin vertical meter. Moves when audio is arriving on the lane, so silence is visible at a glance.
struct LevelBar: View {
    let level: Float
    let tint: Color

    private var fraction: CGFloat {
        let decibels = max(-60, 20 * log10(max(level, 0.000_001)))
        return CGFloat((decibels + 60) / 60)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.12))
            Capsule().fill(tint).frame(height: max(2, 22 * fraction))
        }
        .frame(width: 5, height: 22)
    }
}
