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
    var measurementOrigin: GeoPoint
    var recordedHole: HoleScore
    var shots: [TrackedShot]
    var target: GeoPoint
    var showsUserLocation: Bool
    var bag: ClubBag = .standard
    var windMph: Double = 0
    var windHelping: Double = 0
    var windFromDegrees: Double? = nil
    var onHeadingChange: (Double) -> Void = { _ in }
    var onMoveTarget: (GeoPoint) -> Void
    var onMoveTee: (GeoPoint) -> Void
    var onSelectShot: ((TrackedShot) -> Void)?
    var onMoveShot: (TrackedShot, GeoPoint) -> Void = { _, _ in }
    var onOpenBag: () -> Void = {}
    var candidates: [SwingCandidate] = []
    var onSelectCandidate: (SwingCandidate) -> Void = { _ in }

    @State private var selectedShotID: UUID?
    @State private var mapSize: CGSize = .zero
    @State private var cameraTick = 0
    @State private var trailCache = GolfLocationTrailCache()
    @State private var draggingMarker = false
    @State private var directToFlag = false
    @GestureState private var shotGestureActive = false
    @State private var draggedShotID: UUID?
    @State private var shotDragOrigin: CGPoint?
    @State private var shotPreview: GeoPoint?
    private var displayedHole: HoleScore {
        guard let id = draggedShotID, let point = shotPreview,
              let index = recordedHole.shots.firstIndex(where: { $0.id == id }) else { return recordedHole }
        var hole = recordedHole
        hole.shots[index].start = point
        return hole
    }
    private var effectiveTarget: GeoPoint { directToFlag ? pin : target }
    private var planningLegs: [RangefinderLeg] {
        RangefinderSnap.legs(origin: measurementOrigin, target: target, pin: pin, direct: directToFlag)
    }
    private var planningLine: [CLLocationCoordinate2D] {
        [measurementOrigin.coordinate] + planningLegs.map { $0.end.coordinate }
    }
    private func refreshSnap() {
        directToFlag = RangefinderSnap.isDirect(origin: measurementOrigin, target: target, pin: pin, wasDirect: directToFlag)
    }
    private func moveTarget(_ point: GeoPoint) {
        directToFlag = RangefinderSnap.isDirect(origin: measurementOrigin, target: point, pin: pin, wasDirect: directToFlag)
        onMoveTarget(directToFlag ? pin : point)
    }

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position, interactionModes: draggingMarker ? [] : [.pan, .zoom], selection: $selectedShotID) {
                    MapPolyline(coordinates: planningLine)
                        .stroke(.white.opacity(0.96), lineWidth: 1.5)

                    ForEach(displayedHole.recordedShotLegs(tee: tee, pin: pin)) { leg in
                        MapPolyline(coordinates: [leg.start.coordinate, leg.end.coordinate])
                            .stroke(.white.opacity(0.9), lineWidth: 2)
                    }

                    GolfTrailMapContent(history: trailCache.resolve(samples: recordedHole.locationSamples ?? [], swings: candidates))
                    // Green: translucent halo + solid white dot.
                    MapCircle(center: pin.coordinate, radius: 7)
                        .foregroundStyle(.white.opacity(0.28))
                    MapCircle(center: pin.coordinate, radius: 2.0)
                        .foregroundStyle(.white)
                        .stroke(.white, lineWidth: 1)

                    // Tee marker is projected as an overlay (TeePinView) below.

                    ForEach(candidates) { event in
                        if let lat = event.latitude, let lon = event.longitude {
                            Marker(event.locationSource == "estimated" ? "Estimated swing · Review" : "Detected swing · Review", systemImage: "questionmark", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                .tint(.orange).tag(event.id)
                        }
                    }
                    if showsUserLocation {
                        UserAnnotation()
                    }
                }
                .mapStyle(.imagery(elevation: .flat))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mapControls {
                    MapCompass()
                        .mapControlVisibility(.hidden)
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    onHeadingChange(context.camera.heading)
                    // Camera motion only refreshes overlay projections here.
                    // The target moves solely by dragging its marker, so the
                    // map can pan and zoom freely underneath a fixed target.
                    cameraTick &+= 1
                }
                .onChange(of: selectedShotID) { _, id in
                    if let id, let shot = shots.first(where: { $0.id == id }) {
                        onSelectShot?(shot)
                    } else if let id, let event = candidates.first(where: { $0.id == id }) { onSelectCandidate(event) }
                    selectedShotID = nil
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
            .onAppear(perform: refreshSnap)
            .onChange(of: target) { _, _ in refreshSnap() }
            .onChange(of: measurementOrigin) { _, _ in refreshSnap() }
            .onChange(of: pin) { _, _ in refreshSnap() }
            .onChange(of: shotGestureActive) { _, active in
                if !active {
                    draggedShotID = nil; shotDragOrigin = nil; shotPreview = nil; draggingMarker = false
                }
            }
        }
    }

    @ViewBuilder
    private func overlayPills(proxy: MapProxy, size: CGSize) -> some View {
        // Draggable target crosshair, geo-anchored instead of fixed at the
        // screen center. Dragging moves only the target — the camera is
        // untouched, so the map stays where it is.
        let targetSpot = markerSpot(for: effectiveTarget.coordinate, yOffset: 0, proxy: proxy, size: size)
        ZStack {
            if directToFlag {
                Image(uiImage: GolfFlagDrawing.image(color: .white)).offset(x: 10, y: -20)
            } else { CenterCrosshair() }
        }
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
            .position(targetSpot.point)
            .opacity(targetSpot.visible ? 1 : 0)
            .allowsHitTesting(targetSpot.visible)
            .highPriorityGesture(markerDrag(proxy: proxy, onMove: moveTarget, isDragging: $draggingMarker))
            .accessibilityLabel(Text(directToFlag ? "Target snapped to flag. Drag away to plan a layup." : "Target"))

        // Draggable tee marker with the same direct-drag interaction.
        let teeSpot = markerSpot(for: tee.coordinate, yOffset: -9.5, proxy: proxy, size: size)
        ZStack { TeePinView() }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .position(teeSpot.point)
            .opacity(teeSpot.visible && !shotOverlapsTee ? 1 : 0)
            .allowsHitTesting(teeSpot.visible && !shotOverlapsTee)
            .highPriorityGesture(markerDrag(proxy: proxy, onMove: onMoveTee, isDragging: $draggingMarker))
            .accessibilityLabel(Text("Tee"))

        // Explicit overlays cannot be culled by MapKit's marker collision rules.
        ForEach(placedShots) { item in
            let spot = markerSpot(for: item.point.coordinate, yOffset: -22, proxy: proxy, size: size)
            Button {
                if let shot = shots.first(where: { $0.id == item.id }) { onSelectShot?(shot) }
            } label: {
                VStack(spacing: 2) {
                    Text(item.monogram).font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(PinpointTheme.primaryText)
                        .frame(width: 36, height: 36)
                        .background(item.isPutt ? Color.green : PinpointTheme.accent, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                    Text(item.markerTitle).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(3).background(.black.opacity(0.85), in: Capsule())
                }
            }.buttonStyle(.plain)
                .frame(minWidth: 52, minHeight: 60)
                .contentShape(Rectangle())
                .highPriorityGesture(shotDrag(id: item.id, origin: item.point, proxy: proxy))
                .position(spot.point).opacity(spot.visible ? 1 : 0)
                .allowsHitTesting(spot.visible)
                .accessibilityLabel(item.markerTitle)
                .accessibilityIdentifier("tracked-shot-\(item.number)")
        }

        // Lines and labels share one collection. Changing to the distinct flag
        // identity removes both layup labels instead of reusing the second one.
        ForEach(planningLegs) { leg in
            if leg.id == .flag || leg.yards > 8 {
                let info = playsLike(for: leg.yards, bearing: leg.start.bearing(to: leg.end))
                let spot = lineSpot(proxy: proxy, from: leg.start.coordinate, to: leg.end.coordinate,
                                    t: 0.5, in: size) ?? fallbackSpot(fraction: leg.id == .second ? 0.35 : 0.63, in: size)
                PlaysLikeLinePill(yards: info.raw, playsLike: info.like, club: info.club, action: onOpenBag)
                    .position(spot)
                    .accessibilityIdentifier(leg.id == .flag ? "distance-to-flag" : (leg.id == .first ? "first-shot-distance" : "second-shot-distance"))
            }
        }
    }

    private func playsLike(for yards: Double, bearing: Double) -> (raw: Int, like: Int, club: String?) {
        let helping = windFromDegrees.map { -cos((bearing - $0) * .pi / 180) } ?? windHelping
        let like = CaddieEngine.playsLike(yards: yards, windMph: windMph, windHelping: helping)
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

    private func shotDrag(id: UUID, origin: GeoPoint, proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(MapDragSpace.name))
            .updating($shotGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                if draggedShotID == nil {
                    draggedShotID = id
                    shotDragOrigin = proxy.convert(origin.coordinate, to: .named(MapDragSpace.name))
                }
                guard let anchor = shotDragOrigin else { return }
                draggingMarker = true
                let pixel = CGPoint(x: anchor.x + value.translation.width, y: anchor.y + value.translation.height - 56)
                guard let coordinate = proxy.convert(pixel, from: .named(MapDragSpace.name)) else { return }
                var point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let history = trailCache.resolve(samples: recordedHole.locationSamples ?? [], swings: candidates)
                if let stop = history.nearest(to: point),
                   let spot = proxy.convert(stop.point.coordinate, to: .named(MapDragSpace.name)),
                   hypot(spot.x - pixel.x, spot.y - pixel.y) <= 28 { point = stop.point }
                shotPreview = point
            }
            .onEnded { _ in
                if let point = shotPreview, let shot = shots.first(where: { $0.id == id }) { onMoveShot(shot, point) }
                draggedShotID = nil; shotDragOrigin = nil; shotPreview = nil; draggingMarker = false
            }
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

    private var shotOverlapsTee: Bool {
        placedShots.contains { $0.point.yards(to: tee) < 8 }
    }

    private var placedShots: [PlacedShot] {
        shots.enumerated().compactMap { index, shot in
            guard let origin = displayedHole.shotOrigin(at: index, tee: tee) else { return nil }
            return PlacedShot(id: shot.id, number: shot.number, point: origin,
                              isPutt: shot.isPutt, caption: shot.club?.shortName)
        }
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

struct GolfTrailMapContent: MapContent {
    var history: GolfLocationTrail
    var body: some MapContent {
        ForEach(Array(history.movementPaths.indices), id: \.self) { index in
            MapPolyline(coordinates: history.movementPaths[index].map(\.coordinate))
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 11]))
        }
        ForEach(Array(history.breadcrumbs.indices), id: \.self) { index in
            MapKit.Annotation("Movement", coordinate: history.breadcrumbs[index].coordinate) {
                Circle().fill(Color.white.opacity(0.45)).frame(width: 6, height: 6).allowsHitTesting(false)
            }.annotationTitles(.hidden)
        }
        ForEach(history.stops) { stop in
            MapKit.Annotation("Stopped here", coordinate: stop.point.coordinate) {
                Image(uiImage: stop.watchConfirmed ? GolfStopAppearance.watchImage : GolfStopAppearance.image)
                    .frame(width: 38, height: 38).allowsHitTesting(false)
            }.annotationTitles(.hidden)
        }
    }
}
