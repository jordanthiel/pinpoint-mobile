import Foundation

extension GolfActivityState {
    /// No location from another course, stale GPS, or draft par score is shown as live.
    static func snapshot(round: GolfRound, fix: GolfLocationSample?, now: Date = Date()) -> Self {
        let number = round.currentHoleNumber
        let validFix = fix.flatMap { sample -> GeoPoint? in
            guard sample.timestamp >= round.startedAt, abs(sample.timestamp.timeIntervalSince(now)) < 30,
                  sample.accuracy > 0, sample.accuracy <= 40,
                  let layout = round.playLayout(for: number), layout.isStandingOnHole(sample.point)
            else { return nil }
            return sample.point
        }
        let origin = validFix ?? round.ballCoordinate(for: number)
        let yards = origin.flatMap { point in round.pinCoordinate(for: number).map { max(0, Int(point.yards(to: $0).rounded())) } }
        let score = round.score(for: number)
        return GolfActivityState(hole: number, par: round.hole(number)?.par ?? 4, yards: yards,
            estimated: validFix == nil,
            score: score?.recordedScore ?? (score?.isComplete == true ? score?.grossScore : nil),
            toPar: round.completedToParLabel, holesCompleted: round.completedHoles.count)
    }
}
