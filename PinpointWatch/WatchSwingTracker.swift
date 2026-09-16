import CoreLocation
import CoreMotion
import HealthKit
import Observation

@MainActor @Observable
final class WatchSwingTracker: NSObject, @preconcurrency CLLocationManagerDelegate, HKWorkoutSessionDelegate {
    var currentLocation: CLLocation?
    private var manuallyStoppedRound: UUID?
    private var lifecycle = UUID()
    var running = false
    var starting = false
    var message = "Track swings during your golf session"
    var count = 0
    var latestCandidate: SwingCandidate?
    private let motion = CMMotionManager()
    private let gps = CLLocationManager()
    private let health = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var gate = SwingDetectionGate()
    private var anchor: CLLocation?
    private var fix: CLLocation?
    private var stationarySince: Date?
    private var roundID: UUID?
    private var hole = 1
    var onCandidate: ((SwingCandidate) -> Void)?

    override init() { super.init(); gps.delegate = self; gps.desiredAccuracy = kCLLocationAccuracyBest; gps.distanceFilter = 3 }
    func select(round: UUID, hole: Int) {
        if let roundID, roundID != round { stop(); count = 0 }
        if self.roundID != round || self.hole != hole { latestCandidate = nil }
        self.roundID = round; self.hole = hole
    }
    func startForRound() async {
        guard manuallyStoppedRound != roundID else { return }
        await start()
    }
    func stopByUser() { manuallyStoppedRound = roundID; stop() }
    func start() async {
        guard !running, !starting, roundID != nil else { return }
        guard motion.isDeviceMotionAvailable else { message = "Motion sensors unavailable on this device"; return }
        let run = lifecycle
        starting = true; defer { starting = false }
        do {
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            guard run == lifecycle, !Task.isCancelled else { return }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .golf; configuration.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: health, configuration: configuration)
            session.delegate = self; workout = session
            session.startActivity(with: Date())
            gate = SwingDetectionGate(); anchor = nil; fix = nil; stationarySince = nil
            gps.requestWhenInUseAuthorization(); gps.startUpdatingLocation()
            running = true; message = "Tracking · waiting for a settled swing"
            motion.deviceMotionUpdateInterval = 1.0 / 50
            motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, error in
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    if let error { self.message = error.localizedDescription; self.stop(); return }
                    guard let sample else { return }
                    let a = sample.userAcceleration
                    let r = sample.rotationRate
                    self.consume(acceleration: sqrt(a.x*a.x + a.y*a.y + a.z*a.z), rotation: sqrt(r.x*r.x + r.y*r.y + r.z*r.z))
                }
            }
        } catch { message = "Could not start tracking: \(error.localizedDescription)"; stop() }
    }
    func stop() {
        lifecycle = UUID()
        running = false; currentLocation = nil; motion.stopDeviceMotionUpdates(); gps.stopUpdatingLocation()
        workout?.end(); workout = nil
    }
    private func consume(acceleration: Double, rotation: Double) {
        guard let roundID else { return }
        let now = Date()
        let fresh = fix.flatMap { now.timeIntervalSince($0.timestamp) < 15 ? $0 : nil }
        let dwell = stationarySince.map { now.timeIntervalSince($0) } ?? 0
        // Without GPS, the motion rest gate still allows a candidate; phone resolves position.
        let settled = fresh == nil || (dwell >= 8 && (fresh!.speed < 0 || fresh!.speed <= 1.5))
        guard gate.sample(time: now.timeIntervalSince1970, acceleration: acceleration, rotation: rotation, stationary: settled) else { return }
        let candidate = SwingCandidate(roundID: roundID, hole: hole, timestamp: now,
            latitude: fresh?.coordinate.latitude, longitude: fresh?.coordinate.longitude,
            accuracy: fresh?.horizontalAccuracy, locationSource: fresh == nil ? "estimated" : "watch",
            peakG: acceleration, rotation: rotation, dwellSeconds: fresh == nil ? 0 : dwell)
        latestCandidate = candidate
        onCandidate?(candidate); count += 1
        message = "\(count) possible swings · review on iPhone"
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let next = locations.last, next.horizontalAccuracy >= 0, next.horizontalAccuracy <= 20,
              abs(next.timestamp.timeIntervalSinceNow) < 15 else { return }
        fix = next
        currentLocation = next
        if anchor == nil || anchor!.distance(from: next) > 12 || next.speed > 1.5 {
            anchor = next; stationarySince = next.timestamp
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fix = nil; message = "Tracking motion · phone or estimated locations"
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended { Task { @MainActor in if self.workout === workoutSession { self.stop() } } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.message = error.localizedDescription; self.stop() }
    }
}
