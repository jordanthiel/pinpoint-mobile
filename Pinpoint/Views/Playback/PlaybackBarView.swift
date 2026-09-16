import SwiftUI

struct PlaybackBarView: View {
    let isPlaying: Bool
    let currentFrame: Int
    let totalFrames: Int
    let currentTimeLabel: String
    let durationLabel: String
    let playbackRate: Float
    let onTogglePlay: () -> Void
    let onScrubStart: () -> Void
    let onSeekProgress: (Double) -> Void
    let onScrubEnd: () -> Void
    let onSetRate: (Float) -> Void

    @State private var isDraggingTimeline = false

    private static let rates: [(rate: Float, label: String)] = [
        (0.125, "⅛×"),
        (0.25, "¼×"),
        (0.5, "½×"),
        (1.0, "1×")
    ]

    private var progress: Double {
        guard totalFrames > 1 else { return 0 }
        return Double(currentFrame) / Double(totalFrames - 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 5)
                    Capsule()
                        .fill(PinpointTheme.accent)
                        .frame(width: max(5, width * progress), height: 5)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: max(0, width * progress - 8))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingTimeline {
                                isDraggingTimeline = true
                                onScrubStart()
                            }
                            let x = min(max(value.location.x, 0), width)
                            onSeekProgress(Double(x / width))
                        }
                        .onEnded { _ in
                            isDraggingTimeline = false
                            onScrubEnd()
                        }
                )
            }
            .frame(height: 24)

            HStack(spacing: 16) {
                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(PinpointTheme.mapSurface, in: Circle())
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Text("\(currentTimeLabel)  ·  \(durationLabel)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)

                Spacer()

                Menu {
                    ForEach(Self.rates, id: \.rate) { option in
                        Button {
                            onSetRate(option.rate)
                        } label: {
                            if abs(playbackRate - option.rate) < 0.02 {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(rateLabel)
                            .font(.caption.weight(.bold).monospacedDigit())
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PinpointTheme.accent, in: Capsule())
                }
                .accessibilityLabel("Playback speed \(rateLabel)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PinpointTheme.hairline)
                .frame(height: 1)
        }
    }

    private var rateLabel: String {
        Self.rates.first { abs(playbackRate - $0.rate) < 0.02 }?.label ?? "1×"
    }
}
