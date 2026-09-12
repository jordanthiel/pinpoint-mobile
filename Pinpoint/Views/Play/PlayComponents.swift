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

/// 18-hole grid overlay used to jump holes from the GPS view.
struct HoleGridPicker: View {
    var holes: [Int]
    var current: Int
    var onSelect: (Int) -> Void
    var onFinish: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(holes, id: \.self) { n in
                    Button {
                        onSelect(n)
                    } label: {
                        Text("\(n)")
                            .font(.headline.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .foregroundStyle(n == current ? PinpointTheme.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: onFinish) {
                Text("Finish Round")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct MapHUDChip: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(minWidth: 58)
    }
}

/// Compact Mid / Green / Par / tee / handicap column used in the GPS top bar.
struct BirdiesTopStat: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 18Birdies-style right-rail circle (solid black on satellite).
struct BirdiesRailButton: View {
    var systemImage: String
    var accessibilityTitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.black, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

/// Bottom-bar Scorecard / Tools control: circle + caption.
struct BirdiesDockButton: View {
    var systemImage: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.black, in: Circle())
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Wind card on the right rail: label, heading arrow, mph.
struct BirdiesWindCard: View {
    var mph: Double
    var fromDegrees: Double

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 2) {
                Text("Wind")
                    .font(.caption2.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            Image(systemName: "arrow.down")
                .font(.body.weight(.bold))
                .rotationEffect(.degrees(fromDegrees))
            Text("\(Int(mph.rounded()))mph")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .frame(width: 50)
        .padding(.vertical, 10)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Fixed camera-center rangefinder, matching the 18Birdies satellite crosshair.
struct CenterCrosshair: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 1.6)
                .frame(width: 46, height: 46)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: i.isMultiple(of: 2) ? 1.6 : 11, height: i.isMultiple(of: 2) ? 11 : 1.6)
                    .offset(
                        x: i == 1 ? 23 : i == 3 ? -23 : 0,
                        y: i == 0 ? -23 : i == 2 ? 23 : 0
                    )
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 1.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Distance + Plays Like chip that sits on the play line (circle on the left).
struct PlaysLikeLinePill: View {
    var yards: Int
    var playsLike: Int
    var club: String?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: -6) {
                Text("\(yards)y")
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Color.black, in: Circle())
                    .zIndex(1)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text("Plays like")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    HStack(spacing: 4) {
                        Text("\(playsLike)y")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        if let club, !club.isEmpty {
                            Text(club)
                                .font(.subheadline.weight(.bold))
                        }
                    }
                }
                .foregroundStyle(.black)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
            }
            .shadow(color: .black.opacity(0.28), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        if let club, !club.isEmpty {
            return "\(yards) yards, plays like \(playsLike) yards, \(club)"
        }
        return "\(yards) yards, plays like \(playsLike) yards"
    }
}

struct MapCircleButton: View {
    var systemImage: String
    var label: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 50, height: 50)
                    .background(Color.black, in: Circle())
                    .foregroundStyle(.white)
                if let label {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
