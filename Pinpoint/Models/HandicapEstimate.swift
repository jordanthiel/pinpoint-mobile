import Foundation

/// Personal estimate, not an official Handicap Index. Gross scores and the
/// published fewer-than-20 selection rule; no PCC, caps or exceptional reductions.
struct HandicapEstimate {
    struct Entry: Identifiable {
        var id: UUID { round.id }
        var round: GolfRound
        var differential: Double
    }
    var entries: [Entry]
    var excludedCount: Int
    var value: Double? { Self.calculate(entries.map(\.differential)) }
    var countingIDs: Set<UUID> {
        guard let rule = Self.selection(entries.count) else { return [] }
        return Set(entries.sorted { $0.differential < $1.differential }.prefix(rule.count).map(\.id))
    }
    var displayValue: String {
        guard let value else { return "—" }
        return value < 0 ? String(format: "+%.1f", abs(value)) : String(format: "%.1f", value)
    }
    init(rounds: [GolfRound]) {
        var seen = Set<UUID>()
        let saved = rounds.filter { $0.status != .active && seen.insert($0.id).inserted }
        let eligible = saved.sorted { $0.startedAt > $1.startedAt }.compactMap { round -> Entry? in
            guard round.status == .finished,
                  round.playedHoleScores.count == 18,
                  Set(round.playedHoleScores.map(\.holeNumber)) == Set(1...18),
                  round.playedHoleScores.allSatisfy({ $0.isComplete && $0.hasScore && $0.grossScore > 0 }) else { return nil }
            // Old Georgetown rounds predate the rating snapshot. Never substitute
            // this course's rating for an unknown course or an unknown tee.
            let tee = round.handicapTee ?? (round.courseID == SampleCourses.georgetown.id ? SampleCourses.georgetown.tee(named: round.teeName) : nil)
            guard let tee, tee.rating.isFinite, tee.rating > 0, (55...155).contains(tee.slope) else { return nil }
            let differential = (113 / Double(tee.slope)) * (Double(round.totalGross) - tee.rating)
            return Entry(round: round, differential: (differential * 10).rounded() / 10)
        }
        entries = Array(eligible.prefix(20))
        excludedCount = saved.count - eligible.count
    }
    static func selection(_ count: Int) -> (count: Int, adjustment: Double)? {
        switch count {
        case 3: return (1, -2)
        case 4: return (1, -1)
        case 5: return (1, 0)
        case 6: return (2, -1)
        case 7...8: return (2, 0)
        case 9...11: return (3, 0)
        case 12...14: return (4, 0)
        case 15...16: return (5, 0)
        case 17...18: return (6, 0)
        case 19: return (7, 0)
        case 20...: return (8, 0)
        default: return nil
        }
    }
    /// Inputs must be newest first, so old low scores fall out of the window.
    static func calculate(_ newestFirst: [Double]) -> Double? {
        let recent = Array(newestFirst.filter(\.isFinite).prefix(20))
        guard let rule = selection(recent.count) else { return nil }
        let best = recent.sorted().prefix(rule.count)
        let result = best.reduce(0, +) / Double(rule.count) + rule.adjustment
        return min(54, (result * 10).rounded() / 10)
    }
}
