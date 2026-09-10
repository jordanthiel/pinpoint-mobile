import SwiftUI

/// Shared bits for the Play (on-course) experience.
enum PlayUI {
    static let cardRadius: CGFloat = 18

    static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    static func scoreColor(score: Int, par: Int) -> Color {
        let diff = score - par
        switch diff {
        case ...(-2): return .yellow
        case -1: return .green
        case 0: return .primary
        case 1: return .orange
        default: return .red
        }
    }
}

struct WindBadge: View {
    var mph: Double
    var fromDegrees: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wind")
            VStack(alignment: .leading, spacing: 0) {
                Text("Wind")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PinpointTheme.secondaryText)
                Text("\(Int(mph)) mph")
                    .font(.subheadline.weight(.bold))
            }
            Image(systemName: "arrow.down")
                .rotationEffect(.degrees(fromDegrees))
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PinpointTheme.secondaryText)
            Text(value)
                .font(.title.weight(.bold).monospacedDigit())
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Horizontal hole picker (1..18 + Finish) used on the GPS view.
struct HolePickerBar: View {
    var holes: [Int]
    var current: Int
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(holes, id: \.self) { n in
                    Button {
                        onSelect(n)
                    } label: {
                        Text("\(n)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .frame(width: 40, height: 40)
                            .background(
                                n == current ? PinpointTheme.accent : PinpointTheme.surfaceElevated,
                                in: Circle()
                            )
                            .foregroundStyle(n == current ? .white : PinpointTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
