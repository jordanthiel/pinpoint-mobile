import SwiftUI
import MapKit

struct ShotOverviewMarker: Equatable {
    var id: UUID
    var point: GeoPoint
    var number: String
    var title: String
    var color: UIColor
    var movable = false
}

struct ShotOverviewLeg: Equatable {
    var startID: UUID
    var endID: UUID?
    var start: GeoPoint
    var end: GeoPoint
    var estimated: Bool
    var isPutt = false
}

struct ShotOverviewMap: UIViewRepresentable {
    var layout: HoleLayout
    var markers: [ShotOverviewMarker]
    var legs: [ShotOverviewLeg]
    var pin: GeoPoint
    var locationTrail = GolfLocationTrail()
    var onDragDistance: (Double?) -> Void
    var onMove: (UUID, GeoPoint) -> Void
    var onSelect: (UUID) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        map.showsUserLocation = true
        map.delegate = context.coordinator
        context.coordinator.map = map
        context.coordinator.installGestures(on: map)
        map.setCamera(MKMapCamera(lookingAtCenter: layout.cameraCenter.coordinate, fromDistance: layout.cameraDistance(), pitch: 0, heading: layout.headingDegrees), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard coordinator.draggedID == nil else { return }
        let old = map.annotations.compactMap { $0 as? Mark }
        map.removeAnnotations(old.filter { mark in !markers.contains { $0.id == mark.value.id } })
        for marker in markers {
            if let mark = old.first(where: { $0.value.id == marker.id }) {
                if mark.value != marker {
                    mark.value = marker
                    (map.view(for: mark) as? ShotMarkerView)?.configure(marker)
                }
                if mark.coordinate.latitude != marker.point.latitude || mark.coordinate.longitude != marker.point.longitude {
                    mark.coordinate = marker.point.coordinate
                }
            } else { map.addAnnotation(Mark(marker)) }
        }
        coordinator.updateTrail()
        coordinator.drawLegs()
    }
    class Mark: NSObject, MKAnnotation {
        var value: ShotOverviewMarker
        @objc dynamic var coordinate: CLLocationCoordinate2D
        var title: String? { value.title }
        init(_ value: ShotOverviewMarker) { self.value = value; coordinate = value.point.coordinate }
    }
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private var renderedTrail: GolfLocationTrail?
        private var renderedLegs: [ShotOverviewLeg]?
        private var renderedDragID: UUID?
        private var renderedPreview: GeoPoint?
        private var trailOverlays: [MKOverlay] = []
        private var legOverlays: [MKOverlay] = []
        var parent: ShotOverviewMap
        weak var map: MKMapView?
        var draggedID: UUID?
        var dragOrigin: CGPoint = .zero
        var preview: GeoPoint?
        var panCandidate: UUID?
        var tapCandidate: UUID?
        weak var markerPan: UIPanGestureRecognizer?
        let floatingDistance = UILabel()
        init(_ parent: ShotOverviewMap) { self.parent = parent }

        func updateTrail() {
            guard let map, renderedTrail != parent.locationTrail else { return }
            renderedTrail = parent.locationTrail
            map.removeAnnotations(map.annotations.filter { $0 is GolfTrailAnnotation })
            map.addAnnotations(GolfTrailAnnotation.make(parent.locationTrail))
            map.removeOverlays(trailOverlays)
            trailOverlays = GolfMovementLine.make(parent.locationTrail)
            map.addOverlays(trailOverlays, level: .aboveRoads)
        }

        func drawLegs() {
            guard let map else { return }
            guard renderedLegs != parent.legs || renderedDragID != draggedID || renderedPreview != preview else { return }
            renderedLegs = parent.legs; renderedDragID = draggedID; renderedPreview = preview
            map.removeAnnotations(map.annotations.filter { $0 is MKPointAnnotation })
            map.removeOverlays(legOverlays)
            legOverlays = []
            for leg in parent.legs {
                let start = leg.startID == draggedID ? preview ?? leg.start : leg.start
                let end = leg.endID == draggedID ? preview ?? leg.end : leg.end
                let line = MKPolyline(coordinates: [start.coordinate, end.coordinate], count: 2)
                legOverlays.append(line)
                map.addOverlay(line)
                let yards = start.yards(to: end)
                let annotation = MKPointAnnotation()
                annotation.coordinate = start.midpoint(to: end).coordinate
                if let preview {
                    let finger = map.convert(preview.coordinate, toPointTo: map)
                    var labelPoint = map.convert(annotation.coordinate, toPointTo: map)
                    if hypot(labelPoint.x - finger.x, labelPoint.y - finger.y) < 115 {
                        labelPoint.x = max(55, finger.x - 115)
                        labelPoint.y = max(90, finger.y - 90)
                        annotation.coordinate = map.convert(labelPoint, toCoordinateFrom: map)
                    }
                }
                annotation.title = "\(leg.estimated ? "~" : "")\(Int((leg.isPutt ? yards * 3 : yards).rounded()))\n\(leg.isPutt ? "Ft" : "Yds")"
                map.addAnnotation(annotation)
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let point = annotation as? GolfTrailAnnotation { return point.view() }
            if let mark = annotation as? Mark {
                let view = ShotMarkerView(annotation: mark, reuseIdentifier: nil)
                view.configure(mark.value)
                return view
            }
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: nil)
            let label = UILabel(frame: CGRect(x: -60, y: -22, width: 65, height: 44))
            label.text = annotation.title ?? ""
            label.textColor = .white; label.numberOfLines = 2; label.textAlignment = .center
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOpacity = 1; label.layer.shadowRadius = 2
            view.addSubview(label); view.isEnabled = false; view.displayPriority = .required
            return view
        }
        func installGestures(on map: MKMapView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(dragMarker(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapMarker(_:)))
            tap.delegate = self
            tap.require(toFail: pan)
            // Give marker manipulation priority over MapKit's own pan and tap recognizers.
            func prioritize(in view: UIView) {
                for gesture in view.gestureRecognizers ?? [] {
                    if gesture is UIPanGestureRecognizer { gesture.require(toFail: pan) }
                    if gesture is UITapGestureRecognizer { gesture.require(toFail: tap) }
                }
                view.subviews.forEach { prioritize(in: $0) }
            }
            prioritize(in: map)
            map.addGestureRecognizer(pan)
            map.addGestureRecognizer(tap)
            markerPan = pan
            floatingDistance.backgroundColor = UIColor.black.withAlphaComponent(0.85)
            floatingDistance.textColor = .white
            floatingDistance.font = .systemFont(ofSize: 20, weight: .semibold)
            floatingDistance.textAlignment = .center
            floatingDistance.layer.cornerRadius = 12
            floatingDistance.clipsToBounds = true
            floatingDistance.isUserInteractionEnabled = false
            floatingDistance.isHidden = true
            map.addSubview(floatingDistance)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let map else { return false }
            let point = touch.location(in: map)
            // Prefer draggable shots when their touch area overlaps the flag/putt.
            let ordered = map.annotations.compactMap { $0 as? Mark }.sorted { $0.value.movable && !$1.value.movable }
            let hit = ordered.first { mark in
                guard let view = map.view(for: mark) else { return false }
                let hitBounds = view.bounds.insetBy(dx: -max(8, (60 - view.bounds.width) / 2),
                                                    dy: -max(8, (64 - view.bounds.height) / 2))
                return hitBounds.contains(view.convert(point, from: map))
            }
            if gestureRecognizer === markerPan {
                panCandidate = hit?.value.movable == true ? hit?.value.id : nil
                return panCandidate != nil
            }
            tapCandidate = hit?.value.id
            return tapCandidate != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // MapKit installs some recognizers after makeUIView; don't let those
            // prevent our shot pan. The map's scrolling is paused once it begins.
            gestureRecognizer === markerPan || other === markerPan
        }
        @objc func tapMarker(_ gesture: UITapGestureRecognizer) {
            guard draggedID == nil, let id = tapCandidate else { return }
            parent.onSelect(id)
        }
        @objc func dragMarker(_ gesture: UIPanGestureRecognizer) {
            guard let map, let id = draggedID ?? panCandidate,
                  let mark = map.annotations.compactMap({ $0 as? Mark }).first(where: { $0.value.id == id }) else { return }
            switch gesture.state {
            case .began:
                draggedID = mark.value.id
                dragOrigin = map.convert(mark.coordinate, toPointTo: map)
                map.isScrollEnabled = false
                fallthrough
            case .changed:
                let delta = gesture.translation(in: map)
                let raw = map.convert(CGPoint(x: dragOrigin.x + delta.x, y: dragOrigin.y + delta.y - 56), toCoordinateFrom: map)
                let rawPoint = GeoPoint(latitude: raw.latitude, longitude: raw.longitude)
                let stop = parent.locationTrail.nearest(to: rawPoint)
                let coordinate = stop.map { candidate in
                    let screen = map.convert(candidate.point.coordinate, toPointTo: map)
                    let finger = map.convert(raw, toPointTo: map)
                    return hypot(screen.x - finger.x, screen.y - finger.y) <= 28 ? candidate.point.coordinate : raw
                } ?? raw
                mark.coordinate = coordinate
                preview = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if let preview {
                    let yards = preview.yards(to: parent.pin)
                    floatingDistance.text = "\(Int(yards.rounded())) Yds"
                    let anchor = map.convert(coordinate, toPointTo: map)
                    floatingDistance.frame = CGRect(x: min(max(8, anchor.x - 60), map.bounds.width - 128),
                                                     y: max(90, anchor.y - 130), width: 120, height: 46)
                    floatingDistance.isHidden = false
                    map.bringSubviewToFront(floatingDistance)
                    parent.onDragDistance(yards)
                }
                drawLegs()
            case .ended:
                let point = preview ?? mark.value.point
                draggedID = nil; preview = nil; map.isScrollEnabled = true
                floatingDistance.isHidden = true
                parent.onDragDistance(nil)
                parent.onMove(mark.value.id, point)
            case .cancelled, .failed:
                floatingDistance.isHidden = true
                parent.onDragDistance(nil)
                mark.coordinate = mark.value.point.coordinate
                draggedID = nil; preview = nil; map.isScrollEnabled = true
                drawLegs()
            default: break
            }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is GolfMovementLine { return GolfMovementLine.renderer(overlay) }
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .white; renderer.lineWidth = 1.5
            return renderer
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation { mapView.deselectAnnotation(annotation, animated: false) }
        }
    }
}


final class ShotMarkerView: MKAnnotationView {
    private let clubLabel = UILabel()
    func configure(_ marker: ShotOverviewMarker) {
        displayPriority = .required
        // GPS evidence stays behind playable markers, including when stops are refreshed.
        zPriority = .max
        selectedZPriority = .max
        if marker.movable {
            image = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 46.5)).image { context in
                context.cgContext.scaleBy(x: 0.75, y: 0.75)
                marker.color.setFill()
                let tail = UIBezierPath()
                tail.move(to: CGPoint(x: 12, y: 38)); tail.addLine(to: CGPoint(x: 24, y: 62))
                tail.addLine(to: CGPoint(x: 36, y: 38)); tail.close(); tail.fill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 48, height: 48)).fill()
                UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: 7, y: 7, width: 34, height: 34)).fill()
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 23, weight: .bold), .foregroundColor: marker.color]
                let text = marker.number as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: 24 - size.width / 2, y: 24 - size.height / 2), withAttributes: attributes)
            }
            centerOffset = CGPoint(x: 0, y: -23.25)
            if clubLabel.superview == nil { addSubview(clubLabel) }
            clubLabel.frame = CGRect(x: 32, y: 33, width: 82, height: 17)
            clubLabel.text = " " + marker.title + " "
            clubLabel.textColor = .white; clubLabel.backgroundColor = .black
            clubLabel.font = .systemFont(ofSize: 10, weight: .semibold)
            clubLabel.frame.size.width = min(100, clubLabel.intrinsicContentSize.width + 4)
            clubLabel.layer.cornerRadius = 3; clubLabel.clipsToBounds = true
            clubLabel.isHidden = false
        } else {
            clubLabel.isHidden = true
            image = marker.number == "⚑" ? GolfFlagDrawing.image(color: .systemYellow) :
                UIGraphicsImageRenderer(size: CGSize(width: 39, height: 45)).image { context in
                    context.cgContext.scaleBy(x: 0.75, y: 0.75)
                    marker.color.setFill()
                    UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 52, height: 50), cornerRadius: 10).fill()
                    let tail = UIBezierPath(); tail.move(to: CGPoint(x: 20, y: 48)); tail.addLine(to: CGPoint(x: 26, y: 60)); tail.addLine(to: CGPoint(x: 32, y: 48)); tail.close(); tail.fill()
                    ((marker.number == "?" ? "Swing" : "Putts") as NSString).draw(at: CGPoint(x: 12, y: 5), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.white])
                    (marker.number as NSString).draw(at: CGPoint(x: 17, y: 19), withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: UIColor.white])
                }
            centerOffset = CGPoint(x: marker.number == "⚑" ? 10 : 0, y: marker.number == "⚑" ? -20 : -22.5)
        }
        accessibilityLabel = marker.title + ", " + marker.number
    }
}
