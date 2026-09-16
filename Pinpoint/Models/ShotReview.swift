import Foundation

extension RoundStore {
    /// Suggested origins remain drafts until the golfer confirms the shot review.
    func suggestedMappedShots(_ number: Int, retaining previous: [TrackedShot] = []) -> [TrackedShot] {
        guard let round = activeRound, let hole = round.score(for: number),
              let expected = hole.suggestedShotCount,
              let layout = round.playLayout(for: number), let pin = round.pinCoordinate(for: number) else { return [] }
        let logged = hole.shots.filter { !$0.isPutt }
        guard expected > 0 else { return [] }
        var used = logged.compactMap(\.start)
        let history = locationTrail(number)
        return (1...expected).filter { slot in !logged.contains { $0.number == slot } }.map { slot in
            if let old = previous.first(where: { $0.number == slot }) {
                if let start = old.start { used.append(start) }
                return old
            }
            let origin = slot == 1 ? layout.tee : layout.point(afterTravelling: Double(slot - 1) / Double(expected) * layout.project(pin).length, toward: pin)
            let candidate = history.preferred(excluding: used, near: origin)
            // A late GPS fix in the fairway cannot relocate the tee shot.
            let stop = slot == 1 ? candidate.flatMap { $0.point.yards(to: layout.tee) <= 30 ? $0 : nil } : candidate
            let start = stop?.point ?? origin
            used.append(start)
            var shot = TrackedShot(number: slot, lie: slot == 1 ? .tee : .fairway, start: start, includeInTrueDistance: false,
                note: stop == nil ? "Estimated position — review before saving" : "Stopped location — review before saving")
            shot.lieWasInferred = true
            return shot
        }
    }
}
