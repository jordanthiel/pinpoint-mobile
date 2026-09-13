import MapKit
import SwiftUI

/// Full-bleed satellite hole map with an 18Birdies-style fixed-center rangefinder.
/// Panning the map moves the landing spot under the crosshair; the play line
/// tee → target → pin and the "plays like" pills live-update from that measure.
struct HoleMapView: View {
    @Binding var position: MapCameraPosition
    var layout: HoleLayout
    var pin: GeoPoint
    var tee: GeoPoint
    var shots: [TrackedShot]
    var target: GeoPoint
    var showsUserLocation: Bool
    var bag: ClubBag = .standard
    var windMph: Double = 0
    var windHelping: Double = 0
    var onMoveTarget: (GeoPoint) -> Void
    var onMoveTee: (GeoPoint) -> Void
    var onSelectShot: ((TrackedShot) -> Void)?
    var onOpenBag: () -> Void = {}

    @State private var selectedShotID: UUID?
    @State private var mapSize: CGSize = .zero
    @State private var cameraTick = 0
    @State private var draggingMarker = false

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position, interactionModes: draggingMarker ? [] : [.pan, .zoom], selection: $selectedShotID) {
                    MapPolyline(coordinates: [tee.coordinate, target.coordinate, pin.coordinate])
                        .stroke(.white.opacity(0.96), lineWidth: 1.5)

                    // Green: translucent halo + solid white dot.
                    MapCircle(center: pin.coordinate, radius: 7)
                        .foregroundStyle(.white.opacity(0.28))
                    MapCircle(center: pin.coordinate, radius: 2.0)
                        .foregroundStyle(.white)
                        .stroke(.white, lineWidth: 1)

                    // Tee marker is projected as an overlay (TeePinView) below.

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
                .onMapCameraChange(frequency: .continuous) { _ in
                    // Camera motion only refreshes overlay projections here.
                    // The target moves solely by dragging its marker, so the
                    // map can pan and zoom freely underneath a fixed target.
                    cameraTick &+= 1
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

                // Target crosshair, tee marker, and "Plays Like" pills,
                // live-updated as the drag handles move. NOTE: keep this free
                // of .id() — identity churn across camera ticks froze the
                // overlay on an early frame instead of tracking the camera.
                overlayPills(proxy: proxy, size: mapSize)
            }
            .coordinateSpace(name: MapDragSpace.name)
        }
    }

    @ViewBuilder
    private func overlayPills(proxy: MapProxy, size: CGSize) -> some View {
        let carryYards = tee.yards(to: target)
        let remainYards = target.yards(to: pin)

        // Draggable target crosshair, geo-anchored instead of fixed at the
        // screen center. Dragging moves only the target — the camera is
        // untouched, so the map stays where it is.
        let targetSpot = markerSpot(for: target.coordinate, yOffset: 0, proxy: proxy, size: size)
        ZStack { CenterCrosshair() }
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
            .position(targetSpot.point)
            .opacity(targetSpot.visible ? 1 : 0)
            .allowsHitTesting(targetSpot.visible)
            .highPriorityGesture(markerDrag(proxy: proxy, onMove: onMoveTarget, isDragging: $draggingMarker))
            .accessibilityLabel(Text("Target"))

        // Draggable tee marker with the same direct-drag interaction.
        let teeSpot = markerSpot(for: tee.coordinate, yOffset: -9.5, proxy: proxy, size: size)
        ZStack { TeePinView() }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .position(teeSpot.point)
            .opacity(teeSpot.visible ? 1 : 0)
            .allowsHitTesting(teeSpot.visible)
            .highPriorityGesture(markerDrag(proxy: proxy, onMove: onMoveTee, isDragging: $draggingMarker))
            .accessibilityLabel(Text("Tee"))

        if carryYards > 8 {
            let info = playsLike(for: carryYards)
            let spot = lineSpot(proxy: proxy, from: tee.coordinate, to: target.coordinate,
                                t: 0.52, in: size) ?? fallbackSpot(fraction: 0.63, in: size)
            PlaysLikeLinePill(yards: info.raw, playsLike: info.like, club: info.club, action: onOpenBag)
                .position(spot)
        }

        if remainYards > 8 {
            let info = playsLike(for: remainYards)
            let spot = lineSpot(proxy: proxy, from: target.coordinate, to: pin.coordinate,
                                t: 0.48, in: size) ?? fallbackSpot(fraction: 0.35, in: size)
            PlaysLikeLinePill(yards: info.raw, playsLike: info.like, club: info.club, action: onOpenBag)
                .position(spot)
        }
    }

    private func playsLike(for yards: Double) -> (raw: Int, like: Int, club: String?) {
        let like = CaddieEngine.playsLike(yards: yards, windMph: windMph, windHelping: windHelping)
        let club = CaddieEngine.recommendEntry(for: like, bag: bag)?.entry.shortLabel
        return (Int(yards.rounded()), Int(like.rounded()), club)
    }

    /// Projected overlay anchor for a draggable map marker: the screen point
    /// plus visibility, computed in a helper so the builder stays branch-free.
    private func markerSpot(for coordinate: CLLocationCoordinate2D, yOffset: CGFloat,
                            proxy: MapProxy, size: CGSize) -> (point: CGPoint, visible: Bool) {
        let hidden = (CGPoint(x: size.width / 2, y: size.height - 120), false)
        guard size.width > 80, size.height > 80,
              let p = proxy.convert(coordinate, to: .local),
              p.y > -40, p.y < size.height + 40,
              p.x > -40, p.x < size.width + 40
        else { return hidden }
        return (CGPoint(x: p.x, y: p.y + yOffset), true)
    }

    /// Direct drag of a map marker: the finger point converts back to GPS and
    /// only the marker's point moves — the camera is never touched, so the
    /// map stays where it is. Map pan/zoom is additionally suspended for the
    /// drag duration via `draggingMarker`.
    private func markerDrag(proxy: MapProxy, onMove: @escaping (GeoPoint) -> Void,
                            isDragging: Binding<Bool>) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(MapDragSpace.name))
            .onChanged { value in
                isDragging.wrappedValue = true
                if let coord = proxy.convert(value.location, from: .named(MapDragSpace.name)) {
                    onMove(GeoPoint(latitude: coord.latitude, longitude: coord.longitude))
                }
            }
            .onEnded { _ in isDragging.wrappedValue = false }
    }

    /// Line-anchored pill spot; nil when either endpoint is off-screen so the
    /// caller can fall back to a leading-edge anchor instead of hiding the pill.
    private func lineSpot(proxy: MapProxy, from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
                          t: CGFloat, in size: CGSize) -> CGPoint? {
        guard let pa = proxy.convert(a, to: .local),
              let pb = proxy.convert(b, to: .local)
        else { return nil }
        return leftOfLine(from: pa, to: pb, t: t, distance: 150, in: size)
    }

    /// Leading-edge anchor used when map conversion fails (e.g. endpoint
    /// off-screen): keeps both pills visible like the reference layout.
    private func fallbackSpot(fraction: CGFloat, in size: CGSize) -> CGPoint {
        guard size.width > 80, size.height > 80 else {
            return CGPoint(x: 112, y: 300)
        }
        let y = min(max(size.height * fraction, 150), max(150, size.height - 230))
        return CGPoint(x: min(112, max(112, size.width - 112)), y: y)
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
            x: min(max(chosen.x, 112), max(112, size.width - 112)),
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

/// Teardrop tee marker with golfer glyph, matching the reference art.
struct TeePinView: View {
    var body: some View {
        ZStack {
            TeePinShape()
                .fill(.white)
                .frame(width: 14, height: 19)
            Image(systemName: "figure.golf")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.black)
                .offset(y: -2)
        }
    }
}

/// Teardrop map pin for the tee marker, matching the reference art.
struct TeePinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true)
        p.move(to: CGPoint(x: rect.midX - r * 0.55, y: r * 1.3))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX + r * 0.55, y: r * 1.3))
        p.closeSubpath()
        return p
    }
}
