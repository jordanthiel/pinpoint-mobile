import MapKit
import SwiftUI

/// Full-bleed satellite hole map: tee → green corridor, shot trail, front/mid/back
/// distances, and a tap-to-measure target like a GPS rangefinder.
struct HoleMapView: View {
    @Binding var position: MapCameraPosition
    var layout: HoleLayout
    var pin: GeoPoint
    var ball: GeoPoint
    var shots: [TrackedShot]
    var measurePoint: GeoPoint?
    var showsUserLocation: Bool
    var showsGreenDistances: Bool
    var putts: Int = 0
    var firstPuttFeet: Double? = nil
    var onTapCoordinate: ((GeoPoint) -> Void)?
    var onSelectShot: ((TrackedShot) -> Void)?

    @State private var selectedShotID: UUID?

    var body: some View {
        MapReader { proxy in
            Map(position: $position, selection: $selectedShotID) {
                if !layout.greenOutline.isEmpty {
                    MapPolygon(coordinates: layout.greenOutline.map(\.coordinate))
                        .foregroundStyle(Color.green.opacity(0.28))
                        .stroke(.white.opacity(0.45), lineWidth: 1)
                }

                MapPolyline(coordinates: corridorCoordinates)
                    .stroke(.white.opacity(0.88), lineWidth: 2.2)

                if let measurePoint {
                    MapPolyline(coordinates: [measurePoint.coordinate, pin.coordinate])
                        .stroke(.white, lineWidth: 2)
                    if ball.yards(to: measurePoint) > 4 {
                        MapPolyline(coordinates: [ball.coordinate, measurePoint.coordinate])
                            .stroke(PinpointTheme.accent.opacity(0.9), lineWidth: 2)
                    }
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

                ForEach(distanceLabels) { label in
                    Marker(label.text, coordinate: label.point.coordinate)
                        .tint(.black)
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
        }
    }

    private var pinMarkerTitle: String {
        var parts = ["Pin"]
        if putts > 0 { parts.append("Putts \(putts)") }
        if let firstPuttFeet { parts.append("1st \(Int(firstPuttFeet.rounded())) ft") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Geometry

    private var corridorCoordinates: [CLLocationCoordinate2D] {
        var pts = layout.path
        if pts.isEmpty { pts = [layout.tee, pin] }
        if let measurePoint {
            return [ball.coordinate, measurePoint.coordinate, pin.coordinate]
        }
        if ball.yards(to: layout.tee) > 8 {
            return [ball.coordinate, pin.coordinate]
        }
        return pts.map(\.coordinate)
    }

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
        if let measurePoint {
            let toPin = measurePoint.yards(to: pin)
            let fromBall = ball.yards(to: measurePoint)
            var labels = [
                DistanceLabel(id: "measure-pin",
                              point: measurePoint.midpoint(to: pin),
                              text: "\(Int(toPin.rounded())) Yds")
            ]
            if fromBall > 8 {
                labels.append(DistanceLabel(id: "measure-carry",
                                            point: ball.midpoint(to: measurePoint),
                                            text: "\(Int(fromBall.rounded())) Yds"))
            }
            return labels
        }

        var labels: [DistanceLabel] = []
        if showsGreenDistances {
            let front = ball.yards(to: layout.greenFront)
            let mid = ball.yards(to: layout.greenCenter)
            let back = ball.yards(to: layout.greenBack)
            labels.append(DistanceLabel(id: "front", point: layout.greenFront.offset(eastYards: -14, northYards: 8),
                                        text: "\(Int(front.rounded())) Yds"))
            labels.append(DistanceLabel(id: "mid", point: layout.greenCenter.offset(eastYards: 16, northYards: 0),
                                        text: "\(Int(mid.rounded())) Yds"))
            if abs(back - mid) > 6 {
                labels.append(DistanceLabel(id: "back", point: layout.greenBack.offset(eastYards: -10, northYards: -8),
                                            text: "\(Int(back.rounded())) Yds"))
            }
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
                                            point: prev.midpoint(to: next).offset(eastYards: 12, northYards: 0),
                                            text: "\(Int(yards.rounded())) Yds"))
            }
            prev = next
        }
        let leftover = prev.yards(to: pin)
        if leftover > 12, !shots.isEmpty {
            labels.append(DistanceLabel(id: "remain",
                                        point: prev.midpoint(to: pin).offset(eastYards: -12, northYards: 0),
                                        text: "\(Int(leftover.rounded())) Yds"))
        }
        return labels
    }
}

extension HoleLayout {
    func cameraPosition(pin: GeoPoint? = nil) -> MapCameraPosition {
        let target = pin ?? self.pin
        return .camera(
            MapCamera(
                centerCoordinate: cameraCenter.coordinate,
                distance: cameraDistance(),
                heading: tee.bearing(to: target),
                pitch: 0
            )
        )
    }

    func greenCameraPosition(pin: GeoPoint? = nil) -> MapCameraPosition {
        let target = pin ?? greenCenter
        return .camera(
            MapCamera(
                centerCoordinate: target.coordinate,
                distance: 92,
                heading: headingDegrees,
                pitch: 0
            )
        )
    }

    func contains(_ point: GeoPoint, slackYards: Double = 140) -> Bool {
        if point.yards(to: pin) < slackYards { return true }
        if point.yards(to: tee) < slackYards { return true }
        return path.contains { point.yards(to: $0) < slackYards }
    }
}
