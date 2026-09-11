import MapKit
import SwiftUI

/// Full-bleed satellite hole map: tee → green corridor, shot trail, front/mid/back
/// distances, and a drag-to-measure target like a GPS rangefinder.
struct HoleMapView: View {
    @Binding var position: MapCameraPosition
    var layout: HoleLayout
    var pin: GeoPoint
    var ball: GeoPoint
    var shots: [TrackedShot]
    /// Locked drop from a tap.
    var measurePoint: GeoPoint?
    /// Live camera-center target while dragging the map.
    var hoverPoint: GeoPoint?
    var showsUserLocation: Bool
    var showsGreenDistances: Bool
    var putts: Int = 0
    var firstPuttFeet: Double? = nil
    var onTapCoordinate: ((GeoPoint) -> Void)?
    var onHoverCoordinate: ((GeoPoint) -> Void)?
    var onSelectShot: ((TrackedShot) -> Void)?

    @State private var selectedShotID: UUID?

    private var lineTarget: GeoPoint? { measurePoint ?? hoverPoint }
    private var liveTarget: GeoPoint { lineTarget ?? ball }
    private var liveYardsToPin: Int { Int(liveTarget.yards(to: pin).rounded()) }

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position, selection: $selectedShotID) {
                    if !layout.greenOutline.isEmpty {
                        MapPolygon(coordinates: layout.greenOutline.map(\.coordinate))
                            .foregroundStyle(Color.green.opacity(0.28))
                            .stroke(.white.opacity(0.45), lineWidth: 1)
                    }

                    MapPolyline(coordinates: layout.playPath.map(\.coordinate))
                        .stroke(.white.opacity(0.38), lineWidth: 3)

                    if let lineTarget {
                        MapPolyline(coordinates: [ball.coordinate, lineTarget.coordinate, pin.coordinate])
                            .stroke(.white.opacity(0.96), lineWidth: 4)
                    }

                    Marker("Tee", monogram: Text("T"), coordinate: layout.tee.coordinate)
                        .tint(.white)
                    Marker(pinMarkerTitle, systemImage: "flag.fill", coordinate: pin.coordinate)
                        .tint(.yellow)

                    ForEach(placedShots) { item in
                        Marker(item.markerTitle, monogram: Text(item.monogram), coordinate: item.point.coordinate)
                            .tint(item.isPutt ? Color(red: 0.18, green: 0.72, blue: 0.38) : Color(red: 0.13, green: 0.45, blue: 0.98))
                            .tag(item.id)
                    }

                    if let measurePoint {
                        Marker("Target", systemImage: "plus.circle.fill", coordinate: measurePoint.coordinate)
                            .tint(.red)
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
                .onMapCameraChange(frequency: .continuous) { context in
                    let c = context.camera.centerCoordinate
                    onHoverCoordinate?(GeoPoint(latitude: c.latitude, longitude: c.longitude))
                }
                .gesture(
                    SpatialTapGesture().onEnded { event in
                        if let coord = proxy.convert(event.location, from: .local) {
                            onTapCoordinate?(GeoPoint(latitude: coord.latitude, longitude: coord.longitude))
                        }
                    }
                )
                .onChange(of: selectedShotID) { _, id in
                    if let id, let shot = shots.first(where: { $0.id == id }) {
                        onSelectShot?(shot)
                    }
                }

                distanceOverlays(proxy: proxy)
                centerCrosshair
            }
        }
    }

    private var centerCrosshair: some View {
        ZStack {
            Text("\(liveYardsToPin) Yds")
                .font(.system(size: 32, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.8), in: Capsule())
                .offset(y: -56)

            Circle()
                .stroke(.white.opacity(0.95), lineWidth: 2.5)
                .frame(width: 34, height: 34)
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
            Path { p in
                p.move(to: CGPoint(x: -22, y: 0)); p.addLine(to: CGPoint(x: -10, y: 0))
                p.move(to: CGPoint(x: 10, y: 0)); p.addLine(to: CGPoint(x: 22, y: 0))
                p.move(to: CGPoint(x: 0, y: -22)); p.addLine(to: CGPoint(x: 0, y: -10))
                p.move(to: CGPoint(x: 0, y: 10)); p.addLine(to: CGPoint(x: 0, y: 22))
            }
            .stroke(.white.opacity(0.95), lineWidth: 2.5)
            .frame(width: 52, height: 52)
        }
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func distanceOverlays(proxy: MapProxy) -> some View {
        ForEach(distanceLabels) { label in
            if let screen = proxy.convert(label.point.coordinate, to: .local) {
                Text(label.text)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
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
        var cursor = layout.tee
        var remaining = layout.tee.yards(to: pin)
        for shot in shots {
            if let end = shot.end {
                cursor = end
            } else {
                let carry = shot.carryYards ?? shot.club?.stockYards ?? 120
                remaining = max(0, remaining - carry)
                cursor = layout.point(afterTravelling: layout.tee.yards(to: pin) - remaining, toward: pin)
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
                                        text: "F  \(Int(front.rounded()))"))
            labels.append(DistanceLabel(id: "mid", point: layout.greenCenter,
                                        text: "\(Int(mid.rounded())) Yds"))
            if abs(back - mid) > 6 {
                labels.append(DistanceLabel(id: "back", point: layout.greenBack,
                                            text: "B  \(Int(back.rounded()))"))
            }
        }

        if let lineTarget {
            let toPin = lineTarget.yards(to: pin)
            let fromBall = ball.yards(to: lineTarget)
            labels.append(DistanceLabel(id: "measure-pin",
                                        point: lineTarget.midpoint(to: pin),
                                        text: "\(Int(toPin.rounded())) Yds"))
            if fromBall > 8 {
                labels.append(DistanceLabel(id: "measure-carry",
                                            point: ball.midpoint(to: lineTarget),
                                            text: "\(Int(fromBall.rounded())) Yds"))
            }
            return labels
        }

        var prev = layout.tee
        var remaining = layout.tee.yards(to: pin)
        for (idx, shot) in shots.enumerated() where !shot.isPutt {
            let next: GeoPoint
            if let end = shot.end {
                next = end
            } else {
                let carry = shot.carryYards ?? shot.club?.stockYards ?? 120
                remaining = max(0, remaining - carry)
                next = layout.point(afterTravelling: layout.tee.yards(to: pin) - remaining, toward: pin)
            }
            let yards = shot.carryYards ?? prev.yards(to: next)
            if yards > 8 {
                labels.append(DistanceLabel(id: "leg-\(idx)",
                                            point: prev.midpoint(to: next),
                                            text: "\(Int(yards.rounded())) Yds"))
            }
            prev = next
        }
        let leftover = prev.yards(to: pin)
        if leftover > 12, !shots.isEmpty {
            labels.append(DistanceLabel(id: "remain",
                                        point: prev.midpoint(to: pin),
                                        text: "\(Int(leftover.rounded())) Yds"))
        }
        return labels
    }
}
