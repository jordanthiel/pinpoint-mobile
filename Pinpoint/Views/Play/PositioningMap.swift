import MapKit
import SwiftUI

/// The camera is initialized once. Panning updates the draft coordinate without
/// feeding it back into the camera, avoiding jumps and gesture feedback loops.
struct PositioningMap: UIViewRepresentable {
    var initialPoint: GeoPoint
    var distance: Double = 120
    var heading: Double = 0
    var referencePin: GeoPoint?
    var locationTrail = GolfLocationTrail()
    var onMove: (GeoPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = PlacementMapView()
        // A flat, explicitly bounded camera uses the same zoom limits for
        // programmatic placement and subsequent native pan/pinch gestures.
        map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 20, maxCenterCoordinateDistance: 20_000)
        map.isScrollEnabled = true
        map.insetsLayoutMarginsFromSafeArea = false
        map.layoutMargins = .zero
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.initialCamera = MKMapCamera(lookingAtCenter: initialPoint.coordinate, fromDistance: distance, pitch: 0, heading: heading)
        map.delegate = context.coordinator
        map.showsUserLocation = !locationTrail.stops.isEmpty || !locationTrail.breadcrumbs.isEmpty
        map.addAnnotations(GolfTrailAnnotation.make(locationTrail))
        map.addOverlays(GolfMovementLine.make(locationTrail), level: .aboveRoads)
        if let referencePin {
            let flag = MKPointAnnotation()
            flag.coordinate = referencePin.coordinate
            flag.title = "Pin"
            map.addAnnotation(flag)
        }
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
    }
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PositioningMap
        init(_ parent: PositioningMap) { self.parent = parent }
        private var userIsMoving = false
        private func hasActiveGesture(_ view: UIView) -> Bool {
            (view.gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
                || view.subviews.contains { hasActiveGesture($0) }
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if hasActiveGesture(mapView) { userIsMoving = true }
            traceCamera("will", mapView)
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            traceCamera("did", mapView)
            let shouldSnap = userIsMoving
            if userIsMoving { publishCenter(mapView) }
            userIsMoving = false
            if shouldSnap {
                let center = GeoPoint(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)
                if let stop = parent.locationTrail.nearest(to: center) {
                    let pixel = mapView.convert(stop.point.coordinate, toPointTo: mapView)
                    if hypot(pixel.x - mapView.bounds.midX, pixel.y - mapView.bounds.midY) <= 28 {
                        parent.onMove(stop.point)
                        mapView.setCenter(stop.point.coordinate, animated: false)
                    }
                }
            }
        }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            if hasActiveGesture(mapView) { userIsMoving = true }
            guard userIsMoving else { return }
            publishCenter(mapView)
        }
        private func traceCamera(_ event: String, _ map: MKMapView) {
            #if DEBUG
            if CommandLine.arguments.contains("--trace-placement") {
                print("PLACEMENT \(event) distance=\(map.camera.centerCoordinateDistance) heading=\(map.camera.heading) gesture=\(userIsMoving)")
            }
            #endif
        }
        private func publishCenter(_ mapView: MKMapView) {
            guard (mapView as? PlacementMapView)?.cameraReady == true else { return }
            let center = mapView.centerCoordinate
            guard CLLocationCoordinate2DIsValid(center) else { return }
            parent.onMove(GeoPoint(latitude: center.latitude, longitude: center.longitude))
            if let pin = parent.referencePin {
                mapView.removeOverlays(mapView.overlays)
                mapView.addOverlay(MKPolyline(coordinates: [center, pin.coordinate], count: 2))
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let point = annotation as? GolfTrailAnnotation { return point.view() }
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.image = GolfFlagDrawing.image(color: .systemYellow)
            view.centerOffset = CGPoint(x: 10, y: -20)
            view.isEnabled = false
            return view
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is GolfMovementLine { return GolfMovementLine.renderer(overlay) }
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .white
            renderer.lineWidth = 1.5
            return renderer
        }
    }
}

struct PlacementMarker: View {
    var symbol: String
    var color: Color
    var body: some View {
        Group {
            if symbol == "flag.fill" {
                Image(uiImage: GolfFlagDrawing.image(color: UIColor(color)))
                    .frame(width: 24, height: 40).offset(x: 10, y: -20)
            } else {
                Image(systemName: symbol).font(.system(size: 32, weight: .light))
                    .foregroundStyle(color).offset(y: -16)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// MapKit needs its final viewport size before applying a close-range camera.
final class PlacementMapView: MKMapView {
    var initialCamera: MKMapCamera?
    private(set) var cameraReady = false
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !cameraReady, window != nil, bounds.width > 0, bounds.height > 0, let initialCamera else { return }
        // Use a supported region scale rather than an over-zoomed camera that
        // MapKit clamps as soon as the first native gesture begins.
        let span = max(60, initialCamera.centerCoordinateDistance)
        cameraReady = true
        setRegion(MKCoordinateRegion(center: initialCamera.centerCoordinate,
                                    latitudinalMeters: span, longitudinalMeters: span), animated: false)
        // setRegion establishes a supported zoom but resets the bearing. Keep its
        // resolved distance, then restore the approach orientation exactly once.
        let oriented = camera.copy() as! MKMapCamera
        oriented.heading = initialCamera.heading
        oriented.pitch = 0
        setCamera(oriented, animated: false)
    }
}


enum GolfFlagDrawing {
    static func image(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 40)).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(color.cgColor); cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: 2, y: 40)); cg.addLine(to: CGPoint(x: 2, y: 1)); cg.strokePath()
            cg.setFillColor(color.cgColor)
            cg.move(to: CGPoint(x: 2, y: 1)); cg.addLine(to: CGPoint(x: 23, y: 8))
            cg.addLine(to: CGPoint(x: 2, y: 16)); cg.closePath(); cg.fillPath()
        }
    }
}

/// Shared breadcrumbs and consolidated stops for shot maps.
final class GolfTrailAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let isStop: Bool
    let watch: Bool
    init(point: GeoPoint, isStop: Bool, watch: Bool = false) {
        coordinate = point.coordinate; self.isStop = isStop; self.watch = watch
    }
    static func make(_ trail: GolfLocationTrail) -> [GolfTrailAnnotation] {
        trail.breadcrumbs.map { GolfTrailAnnotation(point: $0, isStop: false) }
        + trail.stops.map { GolfTrailAnnotation(point: $0.point, isStop: true, watch: $0.watchConfirmed) }
    }
    func view() -> MKAnnotationView {
        let view = MKAnnotationView(annotation: self, reuseIdentifier: nil)
        view.image = isStop ? (watch ? GolfStopAppearance.watchImage : GolfStopAppearance.image) : GolfStopAppearance.breadcrumb
        view.isEnabled = false
        view.displayPriority = isStop ? .required : .defaultLow
        view.zPriority = .min
        view.selectedZPriority = .min
        view.accessibilityLabel = isStop ? (watch ? "Watch swing location" : "Stopped here") : "Movement"
        return view
    }
}

/// Fixed screen-size symbols stay legible at every map zoom. Cache raster images
/// instead of redrawing every breadcrumb as GPS observations arrive.
enum GolfStopAppearance {
    static let image = drawStop(watch: false)
    static let watchImage = drawStop(watch: true)
    static let breadcrumb = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6)).image { _ in
        UIColor.white.withAlphaComponent(0.45).setFill()
        UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 6, height: 6)).fill()
    }
    private static func drawStop(watch: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 38, height: 38)).image { _ in
            UIColor(white: 0.18, alpha: 0.7).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 38, height: 38)).fill()
            UIColor.white.withAlphaComponent(0.4).setStroke()
            let rim = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 36, height: 36))
            rim.lineWidth = 1; rim.stroke()
            UIColor(red: 1, green: 0.79, blue: 0.12, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 9, y: 9, width: 20, height: 20)).fill()
            if watch {
                UIColor.white.setStroke()
                let ring = UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 26, height: 26))
                ring.lineWidth = 1.5; ring.stroke()
            }
        }
    }
}

/// A few overlays per hole replace hundreds of potentially culled movement annotations.
final class GolfMovementLine: MKPolyline {
    static func make(_ trail: GolfLocationTrail) -> [GolfMovementLine] {
        trail.movementPaths.map { GolfMovementLine(coordinates: $0.map(\.coordinate), count: $0.count) }
    }
    static func renderer(_ overlay: MKOverlay) -> MKPolylineRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = UIColor.white.withAlphaComponent(0.55)
        renderer.lineWidth = 3
        renderer.lineCap = .round
        renderer.lineDashPattern = [1, 11]
        return renderer
    }
}
