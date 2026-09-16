import AVFoundation
import Combine
import CoreMotion
import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// A detected swing candidate from motion + sound coincidence.
struct WatchShotEvent: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var timestamp: Date
    /// Peak acceleration in g at impact.
    var peakAccelerationG: Double
    /// Audio level jump in dB around impact.
    var audioJumpDb: Double
    var confidence: Double // 0...1
    var source: String // "watch", "iphone", "simulated"
    var claimed: Bool

    init(peakAccelerationG: Double, audioJumpDb: Double,
         source: String = "iphone", timestamp: Date = Date()) {
        id = UUID()
        self.timestamp = timestamp
        self.peakAccelerationG = peakAccelerationG
        self.audioJumpDb = audioJumpDb
        self.source = source
        claimed = false
        // Confidence: strong motion spike + sharp sound transient = likely a strike.
        let motion = min(1.0, max(0, (peakAccelerationG - 1.6) / 2.4))
        let audio = min(1.0, max(0, (audioJumpDb - 6) / 18))
        confidence = 0.35 * motion + 0.65 * audio
    }

    var isLikelyStrike: Bool { confidence >= 0.55 }
}

/// iPhone-side shot detection fusing wrist-like motion (CoreMotion) with the
/// impact transient (microphone level). A real watchOS companion sends the
/// same payload over WatchConnectivity; this service merges both streams
/// into one pending inbox the golfer confirms hole-by-hole.
///
/// Design notes:
/// - Detection NEVER auto-adds shots: events wait in `pendingEvents` until
///   the golfer assigns a club + lie (or dismisses). False positives from
///   practice swings stay harmless.
/// - Thresholds are conservative; a "simulated" event generator lets the
///   golfer demo the flow without swinging (and powers SwiftUI previews).
@Observable
final class WatchShotDetector: NSObject {
    var isListening = false
    var pendingEvents: [WatchShotEvent] = []
    var lastError: String?
    var watchReachable = false

    /// Most recent motion peak, exposed for the live "swing meter" UI.
    var liveAccelerationG: Double = 0

    private let motion = CMMotionManager()
    private var audioRecorder: AVAudioRecorder?
    private var pollTimer: Timer?
    private var lastPeakG: Double = 0
    private var lastDb: Double = -80
    private var cooldownUntil = Date.distantPast
    private var motionBaseline: Double = 1.0

    private let impactThresholdG = 2.6
    private let audioJumpThresholdDb = 10.0

    override init() {
        super.init()
    }

    // MARK: - Listening (iPhone mic + motion fusion)

    func startListening() {
        guard !isListening else { return }
        lastError = nil
        startMotion()
        startAudioMetering()
        isListening = true
    }

    func stopListening() {
        isListening = false
        pollTimer?.invalidate()
        pollTimer = nil
        motion.stopAccelerometerUpdates()
        audioRecorder?.stop()
        audioRecorder = nil
    }

    private func startMotion() {
        guard motion.isAccelerometerAvailable else {
            lastError = "Motion sensing isn't available on this device."
            return
        }
        motion.accelerometerUpdateInterval = 1.0 / 60
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let g = sqrt(data.acceleration.x * data.acceleration.x
                + data.acceleration.y * data.acceleration.y
                + data.acceleration.z * data.acceleration.z)
            liveAccelerationG = g
            // Slow-adapting baseline so walking doesn't desensitize full swings.
            motionBaseline = 0.98 * motionBaseline + 0.02 * g
            if g > lastPeakG { lastPeakG = g }
        }
    }

    private func startAudioMetering() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            lastError = "Couldn't start the microphone for impact sound."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pinpoint-impact-meter.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleIMA4,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
        } catch {
            lastError = "Couldn't start impact metering."
            return
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard isListening else { return }
        audioRecorder?.updateMeters()
        let db = Double(audioRecorder?.averagePower(forChannel: 0) ?? -80)
        let jump = db - lastDb
        lastDb = 0.9 * lastDb + 0.1 * db
        let peak = lastPeakG
        lastPeakG = 0

        guard Date() > cooldownUntil else { return }
        guard peak >= impactThresholdG, jump >= audioJumpThresholdDb else { return }
        cooldownUntil = Date().addingTimeInterval(4) // one strike per swing, not per rattle
        let event = WatchShotEvent(peakAccelerationG: peak, audioJumpDb: jump, source: "iphone")
        Task { @MainActor in
            pendingEvents.insert(event, at: 0)
        }
    }

    // MARK: - Inbox management

    func claim(_ event: WatchShotEvent) {
        if let idx = pendingEvents.firstIndex(where: { $0.id == event.id }) {
            pendingEvents[idx].claimed = true
        }
    }

    func remove(_ event: WatchShotEvent) {
        pendingEvents.removeAll { $0.id == event.id }
    }

    func clearClaimed() {
        pendingEvents.removeAll { $0.claimed }
    }

    /// Demo / preview helper: injects a realistic strike event.
    func simulateShot(peakG: Double = 3.4, jumpDb: Double = 22) {
        let event = WatchShotEvent(peakAccelerationG: peakG, audioJumpDb: jumpDb, source: "simulated")
        pendingEvents.insert(event, at: 0)
    }

    /// Payload a watchOS companion app should send via WatchConnectivity
    /// `sendMessage(["type": "shot", ...])`. Kept as the contract for the
    /// future watch target — the iPhone merges it like its own detections.
    func ingestWatchMessage(_ message: [String: Any]) {
        guard message["type"] as? String == "shot" else { return }
        let peak = message["peakG"] as? Double ?? 3.0
        let jump = message["audioJumpDb"] as? Double ?? 18
        let event = WatchShotEvent(peakAccelerationG: peak, audioJumpDb: jump, source: "watch")
        Task { @MainActor in
            pendingEvents.insert(event, at: 0)
        }
    }

    var unclaimedCount: Int { pendingEvents.filter { !$0.claimed }.count }
}
