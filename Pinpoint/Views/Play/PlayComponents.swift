import SwiftUI

/// Shared bits for the Play (on-course) experience.
enum PlayUI {
    static let cardRadius: CGFloat = PinpointTheme.Radius.card

    static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PinpointTheme.Space.page)
            .pinpointCard()
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
                    .foregroundStyle(.white.opacity(0.65))
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
                            .foregroundStyle(n == current ? PinpointTheme.primaryText : PinpointTheme.secondaryText)
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
    var unit: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.leading, 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Small blue circular badge with a white chevron used across the 18Birdies UI
/// as an "expand/action" indicator (top-right of cards).
struct BirdiesBlueBadge: View {
    var systemImage: String = "chevron.right"
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(PinpointTheme.primaryText, in: Circle())
    }
}

/// Standalone circular back / next control beside the hole-stats pill.
struct BirdiesCircleNavButton: View {
    var systemImage: String
    var accessibilityTitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.black.opacity(0.92), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

/// 18Birdies-style right-rail rounded-square card with a small blue chevron badge.
struct BirdiesRailButton: View {
    var systemImage: String
    var accessibilityTitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

/// Magnifier with the "+" inside the lens, matching the reference zoom button.
struct BirdiesZoomIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 23, weight: .medium))
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .offset(x: -2.5, y: -3.5)
        }
        .foregroundStyle(.white)
    }
}

/// Filled scorecard doc with text lines and a plus badge, matching the
/// reference "add score" button.
struct BirdiesDocIcon: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Image(systemName: "doc.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 12, height: 2.5)
                    RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 12, height: 2.5)
                }
                .offset(y: 1)
            }
            ZStack {
                Circle()
                    .fill(.black)
                    .frame(width: 15, height: 15)
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .offset(x: 6, y: 6)
        }
    }
}

/// Three-button vertical rail (zoom + score/shot entry + tools) in one dark
/// container, matching the reference right-edge control cluster.
struct BirdiesZoomRail: View {
    var zoomAction: () -> Void
    var docAction: () -> Void
    var toolsAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: zoomAction) {
                BirdiesZoomIcon()
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Zoom"))
            railDivider
            Button(action: docAction) {
                BirdiesDocIcon()
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add"))
            railDivider
            Button(action: toolsAction) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Tools"))
        }
        .frame(width: 58)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var railDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
            .padding(.horizontal, 8)
    }
}

/// Left-edge grouped card: recenter scope + scorecard in one dark container,
/// mirroring the right rail.
struct BirdiesLeftRail: View {
    var recenterAction: () -> Void
    var scorecardAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: recenterAction) {
                Image(systemName: "scope")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Recenter"))
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
                .padding(.horizontal, 8)
            Button(action: scorecardAction) {
                VStack(spacing: 3) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 19, weight: .medium))
                    Text("Scorecard")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: 50, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Scorecard"))
        }
        .frame(width: 58)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Bottom-bar Scorecard / Tools control: rounded-square black card with a
/// caption below and a small blue chevron indicator in the corner.
struct BirdiesDockButton: View {
    var systemImage: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        BirdiesBlueBadge()
                            .offset(x: 4, y: 4)
                    }
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Independent previous/score/next controls, matching the on-course score bar.
struct BirdiesHolePill: View {
    var par: Int
    var holeNumber: Int
    var score: Int?
    var canGoBack: Bool
    var canGoForward: Bool
    var back: () -> Void
    var forward: () -> Void
    var action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            navigationButton("chevron.left", label: "Previous hole", enabled: canGoBack, action: back)
            Button(action: action) {
                VStack(spacing: 4) {
                    Text(score == nil ? "Hole" : "Edit Hole \(holeNumber)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(String(score ?? holeNumber))
                        .background { if let score { ScoreMark(score: score, par: par, size: 36) } }
                        .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(PinpointTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(PinpointTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hole \(holeNumber), \(score.map { "score \($0), edit score" } ?? "enter score")")
            .accessibilityIdentifier("holeScoreButton")
            navigationButton("chevron.right", label: "Next hole", enabled: canGoForward, action: forward)
        }
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }

    private func navigationButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
                .frame(width: 44, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// Wind card on the right rail: "Wind >" label, diagonal wind arrow, mph.
struct BirdiesWindCard: View {
    var mph: Double?
    var fromDegrees: Double?
    var mapHeading: Double = 0
    var status: String = ""
    var body: some View {
        VStack(spacing: 6) {
            Text("Wind").font(.system(size: 13, weight: .semibold))
            if let fromDegrees, mph != nil {
                // A north wind blows south. arrow.down starts pointing south.
                Image(systemName: "arrow.down").font(.system(size: 27, weight: .bold))
                    .rotationEffect(.degrees(fromDegrees - mapHeading)).frame(height: 42)
            } else {
                Image(systemName: mph == nil ? "wind" : "circle.dotted").font(.title2).frame(height: 42)
            }
            Text(mph.map { "\(Int($0.rounded())) mph" } ?? "—")
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
            Text(status).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
        }.foregroundStyle(.white).frame(width: 68).padding(.vertical, 9)
            .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Landing-spot reticle on the play line, matching the 18Birdies satellite crosshair.
struct CenterCrosshair: View {
    private let diameter: CGFloat = 46
    private let tickLength: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 1.5)
                .frame(width: diameter, height: diameter)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
            // Four short diagonal ticks sitting on the ring (NE / SE / SW / NW),
            // oriented radially outward.
            ForEach(0..<4, id: \.self) { i in
                let radians = CGFloat((45 + Double(i) * 90)) * .pi / 180
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: tickLength)
                    .rotationEffect(.radians(radians - .pi / 2))
                    .offset(x: cos(radians) * diameter / 2, y: sin(radians) * diameter / 2)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
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
            HStack(spacing: -14) {
                ZStack(alignment: .center) {
                    Circle()
                        .fill(Color.black.opacity(0.95))
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text("\(yards)")
                            .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        Text("y")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.leading, -1)
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
                .zIndex(1)

                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Plays Like")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.55))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            HStack(alignment: .lastTextBaseline, spacing: 0) {
                                Text("\(playsLike)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                                Text("y")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            if let club, !club.isEmpty {
                                Text(club)
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(.black)
                    }
                    .padding(.leading, 22)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .padding(.trailing, 11)
                }
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
            }
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
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
