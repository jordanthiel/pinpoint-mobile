import Foundation
import WatchConnectivity
import Observation

@MainActor @Observable
final class WatchSession: NSObject, WCSessionDelegate {
    var round: CompanionRound?
    var reachable = false
    var error: String?
    var saving = false
    var pendingRecordings = 0
    let tracker = WatchSwingTracker()
    private var swings: [SwingCandidate] = []
    private let cacheKey = "pinpoint.watch.round"
    static var voiceDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Voice", isDirectory: true)
    }
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey) { round = CompanionWire.decode(CompanionRound.self, data) }
        #if DEBUG
        if CommandLine.arguments.contains("--demo-round") {
            round = CompanionRound(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, course: "Simulator Preview", currentHole: 1,
                holes: [CompanionHole(id: 1, par: 4, yardage: 344, score: 5, putts: 2, revision: "preview", pinLatitude: nil, pinLongitude: nil), CompanionHole(id: 2, par: 3, yardage: 121, score: nil, putts: nil, revision: "preview", pinLatitude: nil, pinLongitude: nil)], focus: "Lag putting: roll ten putts into a three-foot circle.", updatedAt: Date())
            return
        }
        #endif
        swings = (try? JSONDecoder().decode([SwingCandidate].self, from: Data(contentsOf: Self.swingURL))) ?? []
        tracker.onCandidate = { [weak self] event in self?.queueSwing(event) }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    private func apply(_ context: [String: Any]) {
        if let snapshot = CompanionWire.decode(CompanionRound.self, context[CompanionWire.snapshot]) {
            round = snapshot
            UserDefaults.standard.set(CompanionWire.encode(snapshot), forKey: cacheKey)
        } else if context[CompanionWire.noRound] as? Bool == true {
            round = nil; UserDefaults.standard.removeObject(forKey: cacheKey)
        }
        if let round { tracker.select(round: round.id, hole: round.currentHole) }
        else { tracker.stop() }
        let swingReceipts = context["swingReceipts"] as? [String] ?? []
        if let candidate = tracker.latestCandidate, swingReceipts.contains(candidate.id.uuidString) {
            // The phone now owns its review state (including deletion/dismissal).
            tracker.latestCandidate = nil
        }
        swings.removeAll { swingReceipts.contains($0.id.uuidString) }
        persistSwings()
        let receipts = context["voiceReceipts"] as? [String] ?? []
        for file in voiceFiles() where receipts.contains(file.deletingPathExtension().lastPathComponent.split(separator: "_").last.map(String.init) ?? "") {
            try? FileManager.default.removeItem(at: file)
        }
        pendingRecordings = voiceFiles().count
    }
    func refresh() {
        reachable = WCSession.default.isReachable
        guard reachable else { error = "Open Pinpoint on your paired iPhone to sync."; return }
        WCSession.default.sendMessage([CompanionWire.refresh: true], replyHandler: { response in
            Task { @MainActor in self.apply(response); self.error = nil }
        }, errorHandler: { error in Task { @MainActor in self.error = error.localizedDescription } })
        retryVoiceTransfers()
        retrySwingTransfers()
    }
    func save(_ edit: CompanionScoreEdit) async -> Bool {
        guard WCSession.default.isReachable else { error = "Keep your iPhone nearby and open Pinpoint to save. Your draft stays here."; return false }
        saving = true; error = nil
        defer { saving = false }
        return await withCheckedContinuation { continuation in
            WCSession.default.sendMessage([CompanionWire.edit: CompanionWire.encode(edit) ?? Data()], replyHandler: { response in
                Task { @MainActor in
                    self.apply(response)
                    self.error = response["error"] as? String
                    continuation.resume(returning: response["saved"] as? Bool == true)
                }
            }, errorHandler: { error in
                Task { @MainActor in self.error = error.localizedDescription; continuation.resume(returning: false) }
            })
        }
    }
    private static var swingURL: URL { voiceDirectory.deletingLastPathComponent().appendingPathComponent("swings.json") }
    private func persistSwings() {
        do { try JSONEncoder().encode(swings).write(to: Self.swingURL, options: .atomic) }
        catch { self.error = "Could not save swing queue: \(error.localizedDescription)" }
    }
    private func queueSwing(_ event: SwingCandidate) {
        swings.append(event); persistSwings(); retrySwingTransfers()
    }
    func retrySwingTransfers() {
        guard WCSession.default.activationState == .activated else { return }
        for event in swings {
            guard !WCSession.default.outstandingUserInfoTransfers.contains(where: { $0.userInfo["swingID"] as? String == event.id.uuidString }) else { continue }
            WCSession.default.transferUserInfo(["swing": CompanionWire.encode(event) ?? Data(), "swingID": event.id.uuidString])
        }
    }
    private func voiceFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: Self.voiceDirectory, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "m4a" }
    }
    func retryVoiceTransfers() {
        pendingRecordings = voiceFiles().count
        guard WCSession.default.activationState == .activated else { return }
        for file in voiceFiles() {
            guard !WCSession.default.outstandingFileTransfers.contains(where: { $0.file.fileURL.lastPathComponent == file.lastPathComponent }) else { continue }
            let parts = file.deletingPathExtension().lastPathComponent.split(separator: "_").map(String.init)
            guard parts.count == 3, let hole = Int(parts[1]) else { continue }
            WCSession.default.transferFile(file, metadata: ["roundID": parts[0], "hole": hole, "recordingID": parts[2]])
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.apply(session.receivedApplicationContext); self.reachable = session.isReachable; self.retryVoiceTransfers(); self.retrySwingTransfers(); if self.reachable { self.refresh() } }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = session.isReachable; if self.reachable { self.refresh() } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            if let error { self.error = "Voice note kept on Watch: \(error.localizedDescription)" }
            // Keep source until the phone sends an explicit durable-storage receipt.
            if session.isReachable { self.refresh() }
        }
    }
}
