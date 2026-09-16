#if PINPOINT_CARPLAY
import CarPlay
import UIKit

final class CarPlayAppDelegate: PhoneAppDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: connectingSceneSession.role == .carTemplateApplication ? "Pinpoint Cart" : nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .carTemplateApplication {
            config.sceneClass = CPTemplateApplicationScene.self
            config.delegateClass = CartSceneDelegate.self
        }
        return config
    }
}

/// Golf-cart companion, using two-level CarPlay lists. Requires Apple's entitlement approval.
@MainActor
final class CartSceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interface: CPInterfaceController?
    private var root: CPListTemplate?
    private let rounds = PinpointRuntime.shared.rounds
    private let location = PlayerLocation()
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        location.start()
        showRound()
        observer = NotificationCenter.default.addObserver(forName: .pinpointRoundChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibleRound() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibleRound() }
        }
    }
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        timer?.invalidate(); timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; location.stop(); interface = nil; root = nil
    }
    private func item(_ title: String, _ detail: String, symbol: String, action: (() -> Void)? = nil) -> CPListItem {
        let row = CPListItem(text: title, detailText: detail, image: UIImage(systemName: symbol))
        if let action { row.handler = { _, completion in action(); completion() } }
        else { row.isEnabled = false }
        return row
    }
    private func refreshVisibleRound() {
        guard interface?.topTemplate === root else { return }
        showRound()
    }
    private func showRound() {
        guard let interface else { return }
        let rows: [CPListItem]
        let title: String
        if let round = rounds.activeRound, let hole = round.score(for: round.currentHoleNumber), let definition = round.hole(hole.holeNumber) {
            title = "Hole \(hole.holeNumber) · Par \(definition.par)"
            var distance = "\(definition.yardage) yd · tee yardage"
            if let pin = round.pinCoordinate(for: hole.holeNumber) {
                if let fix = location.freshCoordinate, GeorgetownGPS.isStanding(on: hole.holeNumber, at: fix) {
                    distance = "\(Int(fix.yards(to: pin).rounded())) yd · live GPS to pin"
                } else if let ball = round.ballCoordinate(for: hole.holeNumber) {
                    distance = "\(Int(ball.yards(to: pin).rounded())) yd · tee / last mapped shot"
                }
            }
            rows = [
                item(distance, round.courseName, symbol: "flag.fill"),
                item(hole.hasScore ? "Score \(hole.grossScore) · Edit" : "Enter score", "Large score choices", symbol: "pencil") { [weak self] in self?.edit(hole, round: round, putts: false) },
                item(hole.hasKnownPutts ? "Putts \(hole.putts) · Edit" : "Add putts (optional)", "Score the hole first", symbol: "circle") { [weak self] in self?.edit(hole, round: round, putts: true) },
                item(round.nextHole(after: hole.holeNumber) == nil ? "Round scorecard" : (hole.hasScore ? "Next hole" : "Skip hole · score later"), hole.hasScore ? "Score saved" : "Leave this hole unscored", symbol: "chevron.right") { [weak self] in
                    guard self?.rounds.activeRound?.id == round.id, self?.rounds.activeRound?.currentHoleNumber == hole.holeNumber else { self?.showRound(); return }
                    if let next = round.nextHole(after: hole.holeNumber) { self?.rounds.setCurrentHole(next); self?.showRound() }
                    else { self?.showHoles(round) }
                },
                item("Holes & scorecard", "\(round.totalGross) strokes · \(round.completedHoles.count) finished", symbol: "list.number") { [weak self] in self?.showHoles(round) },
                item("Practice focus", "A quick reminder for your round", symbol: "target") { [weak self] in self?.showFocus(round) }
            ]
        } else {
            title = "Pinpoint Cart"
            rows = [item("Start a round on iPhone", "Your course and scorecard will appear here.", symbol: "iphone")]
        }
        if let root, root.title == title { root.updateSections([CPListSection(items: rows)]) }
        else {
            let template = CPListTemplate(title: title, sections: [CPListSection(items: rows)])
            root = template
            interface.setRootTemplate(template, animated: false, completion: nil)
        }
    }
    private func showHoles(_ round: GolfRound) {
        let rows = round.holeScores.map { hole in
            item("Hole \(hole.holeNumber) · \(hole.hasScore ? "Score \(hole.grossScore)" : "—")", "Par \(round.hole(hole.holeNumber)?.par ?? 4)", symbol: "flag") { [weak self] in
                guard self?.rounds.activeRound?.id == round.id else { self?.failure("Round changed. Return to the main screen."); return }
                self?.rounds.setCurrentHole(hole.holeNumber)
                self?.interface?.popToRootTemplate(animated: true) { _, _ in self?.showRound() }
            }
        }
        interface?.pushTemplate(CPListTemplate(title: "Choose hole", sections: [CPListSection(items: rows)]), animated: true, completion: nil)
    }
    private func edit(_ hole: HoleScore, round: GolfRound, putts: Bool) {
        guard !putts || hole.hasScore else { failure("Enter the hole score before adding putts."); return }
        var values = putts ? Array(0...min(hole.grossScore, 12)) : Array(1...20)
        let existing = putts ? hole.putts : hole.grossScore
        if existing > 0 && !values.contains(existing) { values.append(existing) }
        let revision = CompanionRevision.of(hole)
        let rows = values.map { value in
            item("\(value) \(putts ? "putts" : "strokes")", (putts ? hole.recordedPutts : hole.recordedScore) == value ? "Saved selection" : "Tap to save", symbol: "checkmark.circle") { [weak self] in
                guard let self, let current = self.rounds.activeRound, current.id == round.id,
                      let actual = current.score(for: hole.holeNumber), CompanionRevision.of(actual) == revision else {
                    self?.failure("This hole changed. Go back and reopen the editor."); return
                }
                let score = putts ? hole.grossScore : value
                let count = putts ? value : (hole.hasKnownPutts ? hole.putts : nil)
                guard self.rounds.saveScoreEntry(hole.holeNumber, score: score, putts: count) else {
                    self.failure(self.rounds.lastError ?? "Couldn't save. Try again."); return
                }
                self.interface?.popToRootTemplate(animated: true) { _, _ in self.showRound() }
            }
        }
        interface?.pushTemplate(CPListTemplate(title: "Hole \(hole.holeNumber) · \(putts ? "Putts" : "Score")", sections: [CPListSection(items: rows)]), animated: true, completion: nil)
    }
    private func showFocus(_ round: GolfRound) {
        let focus = GolfEvidence(rounds: [round]).focus.first
        let row = item(focus?.title ?? "Build your round data", focus?.target ?? "Score holes to unlock personal practice priorities.", symbol: "target")
        interface?.pushTemplate(CPListTemplate(title: "Practice focus", sections: [CPListSection(items: [row])]), animated: true, completion: nil)
    }
    private func failure(_ text: String) {
        let alert = CPAlertTemplate(titleVariants: [text], actions: [CPAlertAction(title: "OK", style: .default) { [weak self] _ in self?.interface?.dismissTemplate(animated: true, completion: nil) }])
        interface?.presentTemplate(alert, animated: true, completion: nil)
    }
}
#endif
