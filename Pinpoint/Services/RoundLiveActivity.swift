import ActivityKit
import UIKit
import OSLog

/// Owns one activity per active round. GPS updates are coalesced to five seconds;
/// score/hole changes bypass that throttle, without touching cloud sync or disk.
@MainActor
final class RoundLiveActivity {
    static let shared = RoundLiveActivity()
    private weak var rounds: RoundStore?
    private var fix: GolfLocationSample?
    private var activity: Activity<GolfActivityAttributes>?
    private var worker: Task<Void, Never>?
    private var delayedRefresh: Task<Void, Never>?
    private var pending = false
    private var lastSent = Date.distantPast
    private var lastAttempt = Date.distantPast
    private var observedRound: UUID?
    private var dismissedRound: UUID?
    private let log = Logger(subsystem: "com.pinpointreplay.mobile", category: "LiveActivity")

    func refresh(rounds: RoundStore, location: GolfLocationSample? = nil) {
        self.rounds = rounds
        if let location { fix = location }
        // No work queue, serialization, or view invalidation for each GPS fix.
        if location != nil, Date().timeIntervalSince(lastSent) < 5 {
            if delayedRefresh == nil {
                let delay = max(0, 5 - Date().timeIntervalSince(lastSent))
                delayedRefresh = Task { [weak self, weak rounds] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard let self, let rounds else { return }
                    self.delayedRefresh = nil
                    self.refresh(rounds: rounds)
                }
            }
            return
        }
        delayedRefresh?.cancel(); delayedRefresh = nil
        pending = true
        guard worker == nil else { return }
        worker = Task {
            while pending {
                pending = false
                await reconcile()
            }
            worker = nil
        }
    }

    private func reconcile() async {
        guard let rounds else { return }
        let round = rounds.activeRound
        let roundID = round?.id
        if observedRound != roundID {
            observedRound = roundID
            dismissedRound = nil
            lastAttempt = .distantPast
            if let round, fix?.timestamp ?? .distantPast < round.startedAt { fix = nil }
        }
        // Restore our activity after a process restart and remove old/account-switched rounds.
        for existing in Activity<GolfActivityAttributes>.activities where existing.attributes.roundID != roundID {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        guard rounds.activeRound?.id == roundID else { pending = true; return }
        if activity?.attributes.roundID != roundID { activity = nil }
        guard let round, round.hole(round.currentHoleNumber) != nil else { return }
        if activity == nil {
            activity = Activity<GolfActivityAttributes>.activities.first { $0.attributes.roundID == round.id }
        }
        if let activity, activity.activityState == .dismissed || activity.activityState == .ended {
            dismissedRound = round.id
            self.activity = nil
        }
        guard dismissedRound != round.id else { return }
        let state = GolfActivityState.snapshot(round: round, fix: fix)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
        if let activity {
            guard activity.content.state != state || Date().timeIntervalSince(lastSent) >= 30 else { return }
            await activity.update(content)
            lastSent = Date()
        } else if UIApplication.shared.applicationState == .active,
                  ActivityAuthorizationInfo().areActivitiesEnabled,
                  Date().timeIntervalSince(lastAttempt) >= 30 {
            lastAttempt = Date()
            do {
                activity = try Activity.request(attributes: GolfActivityAttributes(roundID: round.id, course: round.courseName), content: content, pushType: nil)
                lastSent = Date()
            } catch {
                log.error("Unable to start round activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
