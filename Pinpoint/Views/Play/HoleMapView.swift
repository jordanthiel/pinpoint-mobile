import MapKit
import SwiftUI

/// Full-bleed satellite hole map. The rangefinder is a fixed center crosshair:
/// panning the map moves the landing spot under the reticle and live-updates
/// the Plays Like pills on the play line.
struct HoleMapView: View {
    @Binding var position: MapCameraPosition
    var layout: HoleLayout
    var pin: GeoPoint
    var tee: GeoPoint
    var ball: GeoPoint
    var shots: [TrackedShot]
    var target: GeoPoint
    var showsUserLocation: Bool
    var bag: ClubBag = .standard
    var windMph: Double = 0
    var windHelping: Double = 0
    var onMeasure: (GeoPoint) -> Void
    var onSelectShot: ((TrackedShot) -> Void)?
    var onOpenBag: () -> Void = {}

    @State private var selectedShotID: UUID?
    @State private var mapSize: CGSize = .zero

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position, interactionModes: [.pan, .zoom], selection: $selectedShotID) {
                    MapPolyline(coordinates: [ball.coordinate, target.coordinate, pin.coordinate])
                        .stroke(.white.opacity(0.96), lineWidth: 2)

                    ForEach(placedShots) { item in
                        Marker(item.markerTitle, monogram: Text(item.monogram), coordinate: item.point.coordinate)
                            .tint(item.isPutt ? Color(red: 0.18, green: 0.72, blue: 0.38) : Color(red: 0.13, green: 0.45, blue: 0.98))
                            .tag(item.id)
                    }

                    if showsUserLocation {
                        UserAnnotation()
                    }
                }
                .mapStyle(.imagery(elevation: .realistic))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mapControls {
                    MapCompass()
                        .mapControlVisibility(.hidden)
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    let center = context.camera.centerCoordinate
                    onMeasure(GeoPoint(latitude: center.latitude, longitude: center.longitude))
                }
                .onChange(of: selectedShotID) { _, id in
                    if let id, let shot = shots.first(where: { $0.id == id }) {
                        onSelectShot?(shot)
                    }
                }
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { mapSize = geo.size }
                            .onChange(of: geo.size) { _, size in mapSize = size }
                    }
                }

                lineFurniture(proxy: proxy, size: mapSize)

                CenterCrosshair()
            }
        }
    }

    @ViewBuilder
    private func lineFurniture(proxy: MapProxy, size: CGSize) -> some View {
        if let ballScreen = proxy.convert(ball.coordinate, to: .local) {
            corridorDot(diameter: 10)
                .position(ballScreen)
                .allowsHitTesting(false)
        }
        if let pinScreen = proxy.convert(pin.coordinate, to: .local) {
            corridorDot(diameter: 12)
                .position(pinScreen)
                .allowsHitTesting(false)
        }

        let carryYards = ball.yards(to: target)
        let remainYards = target.yards(to: pin)

        if carryYards > 8,
           let a = proxy.convert(ball.coordinate, to: .local),
           let b = proxy.convert(target.coordinate, to: .local) {
            let spot = leftOfLine(from: a, to: b, t: 0.52, distance: 86, in: size)
            let info = playsLike(for: carryYards)
            PlaysLikeLinePill(yards: info.raw, playsLike: info.like, club: info.club, action: onOpenBag)
                .position(spot)
        }

        if remainYards > 8,
           let a = proxy.convert(target.coordinate, to: .local),
           let b = proxy.convert(pin.coordinate, to: .local) {
            let spot = leftOfLine(from: a, to: b, t: 0.48, distance: 86, in: size)
            let info = playsLike(for: remainYards)
            PlaysLikeLinePill(yards: info.raw, playsLike: info.like, club: info.club, action: onOpenBag)
                .position(spot)
        }
    }

    private func corridorDot(diameter: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(Color.black.opacity(0.28), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private func playsLike(for yards: Double) -> (raw: Int, like: Int, club: String?) {
        let like = CaddieEngine.playsLike(yards: yards, windMph: windMph, windHelping: windHelping)
        let club = CaddieEngine.recommendEntry(for: like, bag: bag)?.entry.shortLabel
        return (Int(yards.rounded()), Int(like.rounded()), club)
    }

    /// Place a pill to the screen-left of the play line, clamped on-screen.
    private func leftOfLine(from a: CGPoint, to b: CGPoint, t: CGFloat, distance: CGFloat, in size: CGSize) -> CGPoint {
        let px = a.x + (b.x - a.x) * t
        let py = a.y + (b.y - a.y) * t
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let n1 = CGPoint(x: px - dy / len * distance, y: py + dx / len * distance)
        let n2 = CGPoint(x: px + dy / len * distance, y: py - dx / len * distance)
        let chosen = n1.x <= n2.x ? n1 : n2
        guard size.width > 80, size.height > 80 else { return chosen }
        return CGPoint(
            x: min(max(chosen.x, 92), max(92, size.width - 92)),
            y: min(max(chosen.y, 120), max(120, size.height - 140))
        )
    }

    // MARK: - Shot trail

    private struct PlacedShot: Identifiable {
        var id: UUID
        var number: Int
        var point: GeoPoint
        var isPutt: Bool
        var caption: String?

        var monogram: String { isPutt ? "P" : "\(number)" }
        var markerTitle: String {
            if let caption { return "Shot \(number) · \(caption)" }
            return "Shot \(number)"
        }
    }

    private var placedShots: [PlacedShot] {
        var items: [PlacedShot] = []
        var cursor = tee
        var remaining = tee.yards(to: pin)
        for shot in shots {
            if let end = shot.end {
                cursor = end
            } else {
                let carry = shot.carryYards ?? shot.club?.stockYards ?? 120
                remaining = max(0, remaining - carry)
                cursor = layout.point(afterTravelling: tee.yards(to: pin) - remaining, toward: pin)
            }
            if shot.end != nil || !shot.isPutt {
                var caption: String?
                if let carry = shot.carryYards {
                    caption = "\(shot.lie.code) · \(Int(carry))"
                } else {
                    caption = shot.lie.code
                }
                items.append(PlacedShot(id: shot.id, number: shot.number, point: cursor,
                                        isPutt: shot.isPutt, caption: caption))
            }
        }
        return items
    }
}
