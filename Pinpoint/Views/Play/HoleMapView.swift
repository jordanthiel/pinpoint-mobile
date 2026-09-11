import MapKit
import SwiftUI

/// Full-bleed satellite hole map with a draggable target and tee.
struct HoleMapView: View {
    @Binding var position: MapCameraPosition
    var layout: HoleLayout
    var pin: GeoPoint
    var tee: GeoPoint
    var ball: GeoPoint
    var shots: [TrackedShot]
    var target: GeoPoint
    var showsUserLocation: Bool
    var showsGreenDistances: Bool
    var putts: Int = 0
    var firstPuttFeet: Double? = nil
    var bag: ClubBag = .standard
    var onDragTarget: (GeoPoint) -> Void
    var onDragTee: (GeoPoint) -> Void
    var onSelectShot: ((TrackedShot) -> Void)?

    @State private var selectedShotID: UUID?
    @State private var isDragging = false

    private var liveYards: Int { Int(ball.yards(to: target).rounded()) }
    private var liveEntry: ClubBagEntry? {
        CaddieEngine.recommendEntry(for: Double(liveYards), bag: bag)?.entry
    }

    private var mapModes: MapInteractionModes { isDragging ? [] : [.pan, .zoom] }

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position, interactionModes: mapModes, selection: $selectedShotID) {
                    if !layout.greenOutline.isEmpty {
                        MapPolygon(coordinates: layout.smoothedGreenOutline.map(\.coordinate))
                            .foregroundStyle(Color.green.opacity(0.24))
                            .stroke(Color.white.opacity(0.62), lineWidth: 2)
                    }

                    MapPolyline(coordinates: layout.playPath.map(\.coordinate))
                        .stroke(.white.opacity(0.38), lineWidth: 3)

                    MapPolyline(coordinates: [ball.coordinate, target.coordinate, pin.coordinate])
                        .stroke(.white.opacity(0.96), lineWidth: 4)

                    Marker(pinMarkerTitle, systemImage: "flag.fill", coordinate: pin.coordinate)
                        .tint(.yellow)

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
                .mapControls {
                    MapCompass()
                        .mapControlVisibility(.hidden)
                }
                .onChange(of: selectedShotID) { _, id in
                    if let id, let shot = shots.first(where: { $0.id == id }) {
                        onSelectShot?(shot)
                    }
                }

                distanceOverlays(proxy: proxy)

                MapDragHandle(proxy: proxy, point: tee, isDragging: $isDragging, onMove: onDragTee) {
                    handleBadge(title: "TEE", color: .white, textColor: .black)
                }

                MapDragHandle(proxy: proxy, point: target, isDragging: $isDragging, onMove: onDragTarget) {
                    VStack(spacing: 6) {
                        VStack(spacing: 2) {
                            Text("\(liveYards) Yds")
                                .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                            if let liveEntry {
                                Text(liveEntry.fullLabel)
                                    .font(.headline.weight(.bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.8), in: Capsule())

                        ZStack {
                            Circle()
                                .fill(.red)
                                .frame(width: 34, height: 34)
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 34, height: 34)
                            Image(systemName: "plus")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                    }
                    .offset(y: -28)
                }
            }
            .coordinateSpace(name: MapDragSpace.name)
        }
    }

    private func handleBadge(title: String, color: Color, textColor: Color) -> some View {
        Text(title)
            .font(.caption.weight(.heavy))
            .foregroundStyle(textColor)
            .frame(width: 44, height: 44)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
    }

    @ViewBuilder
    private func distanceOverlays(proxy: MapProxy) -> some View {
        ForEach(distanceLabels) { label in
            if let screen = proxy.convert(label.point.coordinate, to: .local) {
                Text(label.text)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.78), in: Capsule())
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                    .position(screen)
                    .allowsHitTesting(false)
            }
        }
    }

    private var pinMarkerTitle: String {
        var parts = ["Pin"]
        if putts > 0 { parts.append("Putts \(putts)") }
        if let firstPuttFeet { parts.append("1st \(Int(firstPuttFeet.rounded())) ft") }
        return parts.joined(separator: " · ")
    }

    private func labeledYards(_ yards: Double, prefix: String = "") -> String {
        CaddieEngine.yardsClubLabel(yards: yards, bag: bag, prefix: prefix)
    }

    // MARK: - Geometry

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
                if let lieCode = Optional(shot.lie.code) {
                    if let carry = shot.carryYards {
                        caption = "\(lieCode) · \(Int(carry))"
                    } else {
                        caption = lieCode
                    }
                }
                items.append(PlacedShot(id: shot.id, number: shot.number, point: cursor,
                                        isPutt: shot.isPutt, caption: caption))
            }
        }
        return items
    }

    private struct DistanceLabel: Identifiable {
        var id: String
        var point: GeoPoint
        var text: String
    }

    private var distanceLabels: [DistanceLabel] {
        var labels: [DistanceLabel] = []

        if showsGreenDistances {
            let front = ball.yards(to: layout.greenFront)
            let mid = ball.yards(to: layout.greenCenter)
            let back = ball.yards(to: layout.greenBack)
            labels.append(DistanceLabel(id: "front", point: layout.greenFront,
                                        text: labeledYards(front, prefix: "F ")))
            labels.append(DistanceLabel(id: "mid", point: layout.greenCenter,
                                        text: labeledYards(mid)))
            if abs(back - mid) > 6 {
                labels.append(DistanceLabel(id: "back", point: layout.greenBack,
                                            text: labeledYards(back, prefix: "B ")))
            }
        }

        let toPin = target.yards(to: pin)
        let fromBall = ball.yards(to: target)
        labels.append(DistanceLabel(id: "measure-pin",
                                    point: target.midpoint(to: pin),
                                    text: labeledYards(toPin)))
        if fromBall > 8 {
            labels.append(DistanceLabel(id: "measure-carry",
                                        point: ball.midpoint(to: target),
                                        text: labeledYards(fromBall)))
        }
        return labels
    }
}
