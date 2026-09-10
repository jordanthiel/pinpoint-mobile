import SwiftUI

/// Schematic hole map (no tile dependency): fairway with dogleg, bunkers,
/// green, shot trail with per-leg distances, tee / ball / pin markers.
struct HoleMapView: View {
    var hole: GolfHole
    var shots: [TrackedShot]
    /// Remaining yards ball -> pin, drives the ball marker position.
    var remainingYards: Double
    var pinX: Double
    var pinY: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Grass backdrop.
                LinearGradient(colors: [Color(red: 0.16, green: 0.32, blue: 0.20),
                                        Color(red: 0.10, green: 0.22, blue: 0.14)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Canvas { ctx, size in
                    let tee = CGPoint(x: size.width * 0.5, y: size.height * 0.92)
                    let green = CGPoint(x: size.width * (0.5 + hole.dogleg * 0.18), y: size.height * 0.10)
                    let mid = CGPoint(x: (tee.x + green.x) / 2 + CGFloat(hole.dogleg) * size.width * 0.22,
                                      y: (tee.y + green.y) / 2)

                    // Fairway ribbon tee -> mid -> green.
                    var fairway = Path()
                    fairway.move(to: tee)
                    fairway.addQuadCurve(to: mid, control: CGPoint(x: (tee.x + mid.x) / 2, y: (tee.y + mid.y) / 2))
                    fairway.addQuadCurve(to: green, control: CGPoint(x: (mid.x + green.x) / 2, y: (mid.y + green.y) / 2))
                    ctx.stroke(fairway, with: .color(Color(red: 0.30, green: 0.55, blue: 0.30)), lineWidth: size.width * 0.16)
                    ctx.stroke(fairway, with: .color(Color(red: 0.36, green: 0.62, blue: 0.34)), lineWidth: size.width * 0.11)

                    // Bunkers flanking the green.
                    for (dx, dy, r) in [(-0.10, 0.02, 0.045), (0.11, -0.01, 0.055), (0.02, 0.07, 0.04)] as [(Double, Double, Double)] {
                        let c = CGPoint(x: green.x + CGFloat(dx) * size.width, y: green.y + CGFloat(dy) * size.height)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - CGFloat(r) * size.width, y: c.y - CGFloat(r) * size.width,
                                                        width: CGFloat(r) * 2 * size.width, height: CGFloat(r) * 1.5 * size.width)),
                                 with: .color(Color(red: 0.85, green: 0.80, blue: 0.62)))
                    }

                    // Green.
                    let gr = size.width * 0.13
                    ctx.fill(Path(ellipseIn: CGRect(x: green.x - gr, y: green.y - gr * 0.8, width: gr * 2, height: gr * 1.6)),
                             with: .color(Color(red: 0.42, green: 0.70, blue: 0.38)))

                    // Shot trail.
                    let points = trailPoints(size: size, tee: tee, green: green)
                    if points.count >= 2 {
                        var trail = Path()
                        trail.move(to: points[0])
                        for p in points.dropFirst() { trail.addLine(to: p) }
                        ctx.stroke(trail, with: .color(.white.opacity(0.9)), lineWidth: 2)
                        for (i, p) in points.enumerated() {
                            let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                            ctx.fill(dot, with: .color(i == points.count - 1 ? .blue : .white))
                        }
                    }
                }

                // Overlays: tee marker, ball, pin, leg distances.
                mapOverlays(width: w, height: h)
            }
        }
    }

    // MARK: - Trail math (mirrors the Canvas geometry)

    private func fairwayPoint(_ t: Double, size: CGSize) -> CGPoint {
        // Piecewise: tee(0) -> apex(0.5) -> green(1), lateral dogleg bow.
        let tee = CGPoint(x: size.width * 0.5, y: size.height * 0.92)
        let green = CGPoint(x: size.width * (0.5 + hole.dogleg * 0.18), y: size.height * 0.10)
        let bow = CGFloat(hole.dogleg) * size.width * 0.22
        let x = tee.x + (green.x - tee.x) * t + bow * sin(t * .pi)
        let y = tee.y + (green.y - tee.y) * t
        return CGPoint(x: x, y: y)
    }

    private func trailPoints(size: CGSize, tee: CGPoint, green: CGPoint) -> [CGPoint] {
        guard !shots.isEmpty else { return [tee] }
        var points = [tee]
        var travelled: Double = 0
        let total = max(1, Double(hole.yardage))
        for shot in shots {
            travelled += min(total - travelled, shot.carryYards ?? shot.club?.stockYards ?? 120)
            let t = min(1, travelled / total)
            // Lateral scatter for offline shapes.
            var p = fairwayPoint(t, size: size)
            if shot.shape == .slice || shot.shape == .push { p.x += size.width * 0.06 }
            if shot.shape == .hook || shot.shape == .pull { p.x -= size.width * 0.06 }
            points.append(p)
        }
        // Live ball marker: interpolate toward remaining distance.
        let done = min(1, (total - remainingYards) / total)
        points.append(fairwayPoint(max(0, done), size: size))
        return points
    }

    @ViewBuilder
    private func mapOverlays(width: CGFloat, height: CGFloat) -> some View {
        let size = CGSize(width: width, height: height)
        let pts = trailPoints(size: size,
                              tee: CGPoint(x: width * 0.5, y: height * 0.92),
                              green: CGPoint(x: width * (0.5 + hole.dogleg * 0.18), y: height * 0.10))
        // Per-leg distance labels between consecutive shot points.
        ForEach(1..<pts.count, id: \.self) { i in
            let a = pts[i - 1]
            let b = pts[i]
            let frac = i <= shots.count ? legFraction(i) : remainingFraction
            Text(frac)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .position(x: (a.x + b.x) / 2 + 34, y: (a.y + b.y) / 2)
        }
        // Tee + ball markers.
        if let first = pts.first {
            mapPin(number: nil, color: .white, position: first, label: "T")
        }
        if let last = pts.last, pts.count > 1 {
            mapPin(number: shots.count, color: .blue, position: last, label: nil)
        }
        // Pin flag on the green.
        let green = CGPoint(x: width * (0.5 + hole.dogleg * 0.18), y: height * 0.10)
        Image(systemName: "flag.fill")
            .foregroundStyle(.yellow)
            .position(x: green.x + CGFloat(pinX - 0.5) * 40, y: green.y + CGFloat(0.5 - pinY) * 30)
    }

    private func legFraction(_ i: Int) -> String {
        let idx = i - 1
        guard shots.indices.contains(idx) else { return "" }
        let s = shots[idx]
        if let c = s.carryYards { return "\(Int(c))" }
        if let d = s.distanceToPinBeforeYards, shots.indices.contains(idx + 1),
           let n = shots[idx + 1].distanceToPinBeforeYards {
            return "\(Int(max(0, d - n)))"
        }
        return s.club.map { "\(Int($0.stockYards))" } ?? ""
    }

    private var remainingFraction: String { "\(Int(max(0, remainingYards)))" }

    private func mapPin(number: Int?, color: Color, position: CGPoint, label: String?) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
            Text(number.map(String.init) ?? label ?? "")
                .font(.caption.weight(.bold))
                .foregroundStyle(color == .white ? .black : .white)
        }
        .position(position)
    }
}
