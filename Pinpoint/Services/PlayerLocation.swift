import CoreLocation
import Foundation

/// Live GPS for the on-course rangefinder. Distances prefer this point
/// when the golfer is actually standing on the hole.
@Observable
final class PlayerLocation: NSObject, CLLocationManagerDelegate {
    var coordinate: GeoPoint?
    var heading: Double?
    var authorizationDenied = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var started = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 2
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        started = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationDenied = false
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        default:
            authorizationDenied = true
        }
    }

    func stop() {
        started = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard started else { return }
        start()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // A 100m+ fix looks like the next hole. Ignore it.
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 40 else { return }
        coordinate = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        heading = value
    }
}
