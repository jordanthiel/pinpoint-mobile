import SwiftUI

/// Green view: schematic green with slope rings, draggable pin, ball marker,
/// first-putt confirmation and an AI green read.
struct GreenView: View {
    var holeNumber: Int
    var pinX: Double
    var pinY: Double
    var firstPuttFeet: Double?
    var onMovePin: (Double, Double) -> Void
    var onConfirmPutt: (Double) -> Void
    var onSkip: () -> Void = {}

    @State private var dragPin: CGPoint?
    @State private var ballOffset = CGSize(width: 0, height: 34)

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Color(red: 0.12, green: 0.26, blue: 0.16)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        // Mow rings.
                        for (i, r) in [0.46, 0.38, 0.30, 0.22].enumerated() {
                            let rect = CGRect(x: c.x - size.width * r, y: c.y - size.height * r,
                                              width: size.width * r * 2, height: size.height * r * 2)
                            ctx.fill(Path(ellipseIn: rect),
                                     with: .color(Color(red: 0.30 + Double(i) * 0.03,
                                                        green: 0.55 + Double(i) * 0.02, blue: 0.30)))
                        }
                        // Fall-line arrow (deterministic per hole).
                        let read = CaddieEngine.readGreen(holeNumber: holeNumber, pinX: pinX, pinY: pinY, puttFeet: nil)
                        let ang = fallAngle(read.breakDirection)
                        let arrow = Path { p in
                            p.move(to: CGPoint(x: c.x - cos(ang) * 60, y: c.y - sin(ang) * 60))
                            p.addLine(to: CGPoint(x: c.x + cos(ang) * 40, y: c.y + sin(ang) * 40))
                        }
                        ctx.stroke(arrow, with: .color(.white.opacity(0.5)), lineWidth: 2)
                    }
                    // Pin (draggable).
                    let pinPos = dragPin ?? CGPoint(x: w * pinX, y: h * (1 - pinY))
                    VStack(spacing: 0) {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.yellow)
                            .font(.title3)
                        Circle()
                            .fill(.black)
                            .frame(width: 14, height: 7)
                    }
                    .position(pinPos)
                    .gesture(
                        DragGesture().onChanged { g in
                            dragPin = CGPoint(
                                x: min(max(g.location.x, w * 0.15), w * 0.85),
                                y: min(max(g.location.y, h * 0.15), h * 0.85))
                        }.onEnded { _ in
                            if let d = dragPin {
                                onMovePin(d.x / w, 1 - d.y / h)
                                dragPin = nil
                            }
                        }
                    )
                    // Ball marker (draggable for putt distance).
                    Circle()
                        .fill(.red)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(x: pinPos.x + ballOffset.width, y: pinPos.y + ballOffset.height)
                        .gesture(DragGesture().onChanged { g in
                            ballOffset = CGSize(width: g.translation.width, height: 34 + g.translation.height)
                        })
                    // Distance label.
                    Text("\(Int(puttDistanceFeet(pin: pinPos, width: w, height: h))) Ft")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .position(x: w / 2, y: 28)
                }
            }
            .frame(height: 380)

            let read = CaddieEngine.readGreen(holeNumber: holeNumber, pinX: pinX, pinY: pinY,
                                              puttFeet: firstPuttFeet)
            PlayUI.card {
                Label("Green Read", systemImage: "flag")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PinpointTheme.accent)
                Text(read.summary)
                    .font(.subheadline)
                Text("Estimated break — not measured from green data.")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }

            Button {
                onConfirmPutt(puttDistanceFeetDefault())
            } label: {
                Label(firstPuttFeet == nil ? "Confirm 1st Putt" : "Update 1st Putt (\(Int(firstPuttFeet ?? 0)) ft)",
                      systemImage: "mappin")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Skip", action: onSkip)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PinpointTheme.accent)
        }
    }

    private func puttDistanceFeet(pin: CGPoint, width: CGFloat, height: CGFloat) -> Double {
        // Schematic green ≈ 30 yards deep; scale pixel distance accordingly.
        let dx = ballOffset.width / width
        let dy = ballOffset.height / height
        return max(1, sqrt(dx * dx + dy * dy) * 90)
    }

    private func puttDistanceFeetDefault() -> Double {
        let dx = ballOffset.width / 300
        let dy = ballOffset.height / 380
        return max(1, sqrt(dx * dx + dy * dy) * 90)
    }

    private func fallAngle(_ dir: String) -> Double {
        switch dir {
        case "left-to-right": return 0
        case "straight downhill": return .pi / 2
        case "right-to-left": return .pi
        default: return -.pi / 2
        }
    }
}
