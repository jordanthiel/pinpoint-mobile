import CoreLocation
import Foundation
import UIKit

/// Lightweight view subscription. Every screen and the round share one GPS receiver.
@Observable
final class PlayerLocation: NSObject {
    @ObservationIgnored var onFix: ((GolfLocationSample) -> Void)?
    var coordinate: GeoPoint?
    var heading: Double?
    var authorizationDenied = false
    private var lastFixAt: Date?
    @ObservationIgnored fileprivate let background: Bool
    @ObservationIgnored private var started = false
    var freshCoordinate: GeoPoint? {
        guard let lastFixAt, abs(lastFixAt.timeIntervalSinceNow) < 30 else { return nil }
        return coordinate
    }
    static func point(near time: Date) -> GeoPoint? { PhoneGPS.shared.point(near: time) }
    init(background: Bool = false) { self.background = background; super.init() }
    func start() { started = true; PhoneGPS.shared.subscribe(self) }
    func stop() { guard started else { return }; started = false; PhoneGPS.shared.unsubscribe(self) }
    fileprivate func receive(_ fix: CLLocation) {
        lastFixAt = fix.timestamp
        let point = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        if coordinate != point { coordinate = point }
        onFix?(GolfLocationSample(point: point, timestamp: fix.timestamp, accuracy: fix.horizontalAccuracy, speed: fix.speed))
    }
}

private final class PhoneGPS: NSObject, CLLocationManagerDelegate {
    static let shared = PhoneGPS()
    private let clients = NSHashTable<PlayerLocation>.weakObjects()
    private var fixes: [CLLocation] = []
    private var running = false
    private lazy var manager: CLLocationManager = {
        let value = CLLocationManager()
        value.delegate = self
        // Meter-level golf accuracy without navigation's continuous extra sensor work.
        value.desiredAccuracy = kCLLocationAccuracyBest
        value.distanceFilter = kCLDistanceFilterNone // Stationary fixes are required for dwell detection.
        value.activityType = .fitness
        value.pausesLocationUpdatesAutomatically = false
        return value
    }()
    func point(near time: Date) -> GeoPoint? {
        guard let fix = fixes.min(by: { abs($0.timestamp.timeIntervalSince(time)) < abs($1.timestamp.timeIntervalSince(time)) }),
              abs(fix.timestamp.timeIntervalSince(time)) <= 20 else { return nil }
        return GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    }
    func subscribe(_ client: PlayerLocation) {
        let new = !clients.contains(client)
        clients.add(client)
        configure()
        if new, let fix = fixes.last, abs(fix.timestamp.timeIntervalSinceNow) < 30 { client.receive(fix) }
    }
    func unsubscribe(_ client: PlayerLocation) { clients.remove(client); configure() }
    private func configure() {
        let subscribers = clients.allObjects
        guard !subscribers.isEmpty else { manager.stopUpdatingLocation(); running = false; return }
        let background = subscribers.contains { $0.background }
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = background
        let denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        for client in subscribers where client.authorizationDenied != denied { client.authorizationDenied = denied }
        switch manager.authorizationStatus {
        case .notDetermined:
            if UIApplication.shared.applicationState == .active { manager.requestWhenInUseAuthorization() }
        case .authorizedAlways, .authorizedWhenInUse:
            if !running { running = true; manager.startUpdatingLocation() }
            if background, UIApplication.shared.applicationState == .active,
               manager.authorizationStatus == .authorizedWhenInUse,
               !UserDefaults.standard.bool(forKey: "pinpoint.location.alwaysRequested") {
                UserDefaults.standard.set(true, forKey: "pinpoint.location.alwaysRequested")
                manager.requestAlwaysAuthorization()
            }
        default: manager.stopUpdatingLocation(); running = false
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { configure() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 40,
              abs(fix.timestamp.timeIntervalSinceNow) < 30,
              fixes.last.map({ fix.timestamp.timeIntervalSince($0.timestamp) >= 1 }) ?? true else { return }
        // Only the last minute is needed to locate a Watch swing. Don't retain thousands of duplicate fixes.
        fixes.removeAll { fix.timestamp.timeIntervalSince($0.timestamp) > 60 }
        fixes.append(fix)
        for client in clients.allObjects { client.receive(fix) }
    }
}
