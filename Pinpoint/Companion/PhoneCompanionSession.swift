import Foundation
import WatchConnectivity
import UIKit

extension Notification.Name { static let pinpointRoundChanged = Notification.Name("pinpointRoundChanged") }

@MainActor
final class PhoneCompanionSession: NSObject, WCSessionDelegate {
    static let shared = PhoneCompanionSession()
    private weak var rounds: RoundStore?
    private var observer: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var cachedRound: GolfRound?
    private var cachedRoundContext: [String: Any] = [:]
    private var lastLocationPublish = Date.distantPast
    private var lastContext: [String: Any]?
    private let backupLocation = PlayerLocation(background: true)

    func start(rounds: RoundStore) {
        guard self.rounds == nil else { return }
        self.rounds = rounds
        backupLocation.onFix = { [weak self, weak rounds] sample in
            guard let rounds else { return }
            rounds.recordLocation(sample)
            RoundLiveActivity.shared.refresh(rounds: rounds, location: sample)
            if let self, sample.timestamp.timeIntervalSince(self.lastLocationPublish) >= 10 {
                self.lastLocationPublish = sample.timestamp
                self.publish(refreshActivity: false)
            }
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        observer = NotificationCenter.default.addObserver(forName: .pinpointRoundChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
        publish()
    }
    func context() -> [String: Any] {
        var result = roundContext()
        if let round = rounds?.activeRound,
           var snapshot = CompanionWire.decode(CompanionRound.self, result[CompanionWire.snapshot]) {
            let current = backupLocation.freshCoordinate
            for index in snapshot.holes.indices {
                snapshot.holes[index].lastShotAnchor = round.lastShotAnchor(for: snapshot.holes[index].id, current: snapshot.holes[index].id == round.currentHoleNumber ? current : nil)
            }
            snapshot.phoneLocation = current.map {
                CompanionShotAnchor(latitude: $0.latitude, longitude: $0.longitude,
                    timestamp: lastLocationPublish, estimated: false)
            }
            result[CompanionWire.snapshot] = CompanionWire.encode(snapshot)
        }
        result["swingReceipts"] = ((rounds?.activeRound?.swingCandidates ?? []) + (rounds?.pastRounds.flatMap { $0.swingCandidates ?? [] } ?? [])).suffix(1000).map { $0.id.uuidString }
        result["voiceReceipts"] = UserDefaults.standard.stringArray(forKey: "pinpoint.watch.voiceReceipts") ?? []
        return result
    }
    private func roundContext() -> [String: Any] {
        guard let round = rounds?.activeRound else { return [CompanionWire.noRound: true] }
        var scoreSnapshot = round
        for index in scoreSnapshot.holeScores.indices { scoreSnapshot.holeScores[index].locationSamples = nil }
        if cachedRound == scoreSnapshot { return cachedRoundContext }
        let holes = round.holeScores.compactMap { score -> CompanionHole? in
            guard let definition = round.hole(score.holeNumber) else { return nil }
            let pin = round.pinCoordinate(for: score.holeNumber)
            return CompanionHole(id: score.holeNumber, par: definition.par, yardage: definition.yardage,
                score: score.recordedScore ?? (score.isComplete && score.hasScore ? score.grossScore : nil), putts: score.hasKnownPutts ? score.putts : nil,
                revision: CompanionRevision.of(score), pinLatitude: pin?.latitude, pinLongitude: pin?.longitude,
                penalties: score.penaltyStrokes, handicap: definition.handicap,
                shots: score.shots.map { shot in
                    CompanionShot(id: shot.id, number: shot.number, club: shot.club?.displayName ?? "Shot",
                        isPutt: shot.isPutt, carryYards: shot.carryYards, remainingFeet: shot.remainingFeet,
                        detail: [shot.contact?.label, shot.shape?.label, shot.observations?.finish?.rawValue].compactMap { $0 }.joined(separator: " · "))
                })
        }
        let focus = "Review your round insights and practice plan in Me on your iPhone."
        let snapshot = CompanionRound(id: round.id, course: round.courseName, currentHole: round.currentHoleNumber,
            holes: holes, focus: focus, updatedAt: Date())
        cachedRound = scoreSnapshot
        cachedRoundContext = [CompanionWire.snapshot: CompanionWire.encode(snapshot) ?? Data()]
        return cachedRoundContext
    }
    func publish(refreshActivity: Bool = true) {
        if refreshActivity, let rounds { RoundLiveActivity.shared.refresh(rounds: rounds) }
        if rounds?.activeRound != nil { backupLocation.start() } else { backupLocation.stop() }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        let next = context()
        // Ignore timestamp-only refreshes (including cloud checkpoint updates).
        var comparable = next
        if var snapshot = CompanionWire.decode(CompanionRound.self, next[CompanionWire.snapshot]) {
            snapshot.updatedAt = .distantPast
            comparable[CompanionWire.snapshot] = CompanionWire.encode(snapshot)
        }
        if let lastContext, NSDictionary(dictionary: lastContext).isEqual(to: comparable) { return }
        do { try session.updateApplicationContext(next); lastContext = comparable } catch { }
        rounds?.watchDetector.watchReachable = session.isReachable
    }
    private func receive(_ message: [String: Any]) -> [String: Any] {
        if message[CompanionWire.refresh] != nil { return context() }
        guard let edit = CompanionWire.decode(CompanionScoreEdit.self, message[CompanionWire.edit]), let rounds else {
            return ["error": "Invalid score request. Refresh from iPhone."]
        }
        if let error = rounds.applyCompanionEdit(edit) {
            return context().merging(["error": error]) { _, new in new }
        }
        publish()
        return context().merging(["saved": true]) { _, new in new }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.receive(message)) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.rounds?.watchDetector.ingestWatchMessage(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let event = CompanionWire.decode(SwingCandidate.self, userInfo["swing"]) else { return }
        Task { @MainActor in
            if self.rounds?.receiveSwing(event, phonePoint: PlayerLocation.point(near: event.timestamp)) == true { self.publish() }
        }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WCSession removes the temporary URL after this callback returns.
        guard let roundText = file.metadata?["roundID"] as? String, UUID(uuidString: roundText) != nil,
              let hole = file.metadata?["hole"] as? Int, (1...18).contains(hole),
              let data = try? Data(contentsOf: file.fileURL), !data.isEmpty, data.count <= 8_000_000 else { return }
        let folder = WatchVoiceInbox.directory
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let id = file.metadata?["recordingID"] as? String ?? UUID().uuidString
            guard UUID(uuidString: id) != nil else { return }
            let destination = folder.appendingPathComponent("\(roundText)_\(hole)_\(id).m4a")
            try data.write(to: destination, options: .atomic)
            Task { @MainActor in
                var receipts = UserDefaults.standard.stringArray(forKey: "pinpoint.watch.voiceReceipts") ?? []
                if !receipts.contains(id) { receipts.append(id) }
                UserDefaults.standard.set(Array(receipts.suffix(200)), forKey: "pinpoint.watch.voiceReceipts")
                WatchVoiceInbox.shared.reload()
                self.publish()
            }
        } catch { /* Source remains on Watch if the transfer itself fails. */ }
    }
}

@MainActor
class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Activate even for a background WatchConnectivity launch with no visible SwiftUI window.
        PhoneCompanionSession.shared.start(rounds: PinpointRuntime.shared.rounds)
        return true
    }
}
