import Foundation

// MARK: - Strokes gained vs. a skill benchmark
//
// Implements the golf-stats-tracking-plan strategy: every shot is valued as
//
//     SG = expected(start) - expected(finish) - strokes taken
//
// against a versioned baseline table indexed by distance, lie and benchmark
// skill level. Scratch is the primary comparison; peer-handicap levels give
// context for where the golfer is right now. Benchmark figures are
// directional product defaults (see ReferenceBenchmarks), not licensed truth.

// MARK: - Benchmark level

/// Skill baseline that strokes-gained and peer comparisons are measured
/// against. Defaults to scratch; callers may pass the golfer's current
/// level for context.
enum BenchmarkLevel: String, CaseIterable, Identifiable, Codable {
    case scratch
    case hcp5
    case hcp10
    case hcp15
    case hcp20

    var id: String { rawValue }

    /// Handicap the level represents. Scratch plays to 0.
    var handicap: Double {
        switch self {
        case .scratch: return 0
        case .hcp5: return 5
        case .hcp10: return 10
        case .hcp15: return 15
        case .hcp20: return 20
        }
    }

    var label: String {
        switch self {
        case .scratch: return "Scratch"
        case .hcp5: return "5 handicap"
        case .hcp10: return "10 handicap"
        case .hcp15: return "15 handicap"
        case .hcp20: return "20 handicap"
        }
    }

    var shortLabel: String {
        switch self {
        case .scratch: return "Scr"
        case .hcp5: return "5"
        case .hcp10: return "10"
        case .hcp15: return "15"
        case .hcp20: return "20"
        }
    }

    static var `default`: BenchmarkLevel { .scratch }

    /// Nearest peer level for a golfer's estimated handicap. Nil (unknown
    /// handicap) falls back to scratch.
    static func suggested(forHandicap handicap: Double?) -> BenchmarkLevel {
        guard let handicap, handicap.isFinite else { return .default }
        if handicap < 2.5 { return .scratch }
        if handicap < 7.5 { return .hcp5 }
        if handicap < 12.5 { return .hcp10 }
        if handicap < 17.5 { return .hcp15 }
        return .hcp20
    }

    /// Extra expected strokes a peer at this level needs over scratch.
    /// Grows with distance; putting (onGreen) gets a flatter allowance.
    /// Directional defaults, kept deliberately small and documented.
    func strokeOffset(atDistanceYards distance: Double, onGreen: Bool) -> Double {
        let d = max(0, distance)
        switch self {
        case .scratch: return 0
        case .hcp5: return onGreen ? 0.06 : 0.12 + d * 0.0004
        case .hcp10: return onGreen ? 0.12 : 0.25 + d * 0.0008
        case .hcp15: return onGreen ? 0.18 : 0.38 + d * 0.0012
        case .hcp20: return onGreen ? 0.24 : 0.50 + d * 0.0016
        }
    }
}

// MARK: - Expected strokes

/// Versioned scratch baseline plus peer offsets. Version the model so shipped
/// numbers stay comparable when the table is recalibrated; never hard-code
/// these figures as universal truth in marketing.
enum ExpectedStrokes {
    static let modelVersion = "2026.09-sg-v1"

    /// Scratch expected strokes from `distance` yards in `lie`.
    /// Putting uses a distance-based curve; otherwise a fairway anchor table
    /// with lie adjustments, interpolated linearly between anchors.
    static func scratchBaseline(distanceYards: Double, lie: Lie) -> Double {
        let d = max(0, distanceYards)
        if lie == .green { return puttingBaseline(feet: d * 3) }
        let fairway = interpolate(d, anchors: fairwayAnchors)
        switch lie {
        case .green: return puttingBaseline(feet: d * 3) // unreachable; kept for exhaustiveness
        case .tee: return max(1, fairway - 0.05)
        case .fairway: return fairway
        case .fringe: return fairway + 0.05
        case .rough: return fairway + (d < 50 ? 0.25 : 0.40)
        case .sand: return fairway + (d < 50 ? 0.55 : 0.40)
        case .recovery: return fairway + 1.0
        }
    }

    static func value(distanceYards: Double, lie: Lie, level: BenchmarkLevel) -> Double {
        scratchBaseline(distanceYards: distanceYards, lie: lie)
            + level.strokeOffset(atDistanceYards: distanceYards, onGreen: lie == .green)
    }

    // MARK: Private tables

    /// Fairway expected strokes by starting distance (yards). Directional
    /// scratch defaults in the spirit of Broadie's tables: roughly 3.0 from
    /// 100 yd, 3.2 from 150 yd, 3.5 from 200 yd, approaching 4.0 off a
    /// 300-yd tee ball.
    private static let fairwayAnchors: [(distance: Double, strokes: Double)] = [
        (0, 1.00), (5, 2.05), (10, 2.20), (20, 2.45), (30, 2.60),
        (40, 2.70), (50, 2.78), (75, 2.90), (100, 3.00), (125, 3.10),
        (150, 3.22), (175, 3.34), (200, 3.46), (225, 3.58), (250, 3.70),
        (275, 3.82), (300, 3.94), (350, 4.15), (400, 4.35), (500, 4.75),
        (600, 5.10),
    ]

    /// Scratch expected putts by first-putt distance (feet).
    private static let puttingAnchors: [(feet: Double, strokes: Double)] = [
        (0, 1.00), (2, 1.02), (3, 1.05), (5, 1.20), (6, 1.30),
        (9, 1.50), (10, 1.60), (15, 1.78), (20, 1.90), (25, 2.00),
        (30, 2.08), (40, 2.18), (50, 2.28), (60, 2.38), (100, 2.60),
    ]

    private static func puttingBaseline(feet: Double) -> Double {
        interpolate(max(0, feet), anchors: puttingAnchors.map { ($0.feet, $0.strokes) })
    }

    private static func interpolate(_ x: Double, anchors: [(distance: Double, strokes: Double)]) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if x <= first.distance { return first.strokes }
        if x >= last.distance { return last.strokes }
        for i in 1..<anchors.count where x <= anchors[i].distance {
            let lo = anchors[i - 1], hi = anchors[i]
            let t = (x - lo.distance) / max(1e-9, hi.distance - lo.distance)
            return lo.strokes + t * (hi.strokes - lo.strokes)
        }
        return last.strokes
    }
}

// MARK: - Shot category

/// The four strokes-gained buckets. Category totals sum to SG: Total.
enum ShotCategory: String, CaseIterable, Identifiable, Codable {
    case offTee
    case approach
    case aroundGreen
    case putting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .offTee: return "Off the tee"
        case .approach: return "Approach"
        case .aroundGreen: return "Around the green"
        case .putting: return "Putting"
        }
    }

    var shortLabel: String {
        switch self {
        case .offTee: return "OTT"
        case .approach: return "APP"
        case .aroundGreen: return "ARG"
        case .putting: return "PUTT"
        }
    }

    var icon: String {
        switch self {
        case .offTee: return "arrow.up.forward"
        case .approach: return "flag"
        case .aroundGreen: return "circle.dashed"
        case .putting: return "circle.fill"
        }
    }

    /// Practice controllability weight for the priority score: ball-striking
    /// categories outrank putting, which is noisier week to week.
    var controllability: Double {
        switch self {
        case .approach: return 1.0
        case .offTee: return 0.9
        case .aroundGreen: return 0.9
        case .putting: return 0.7
        }
    }

    /// Plan boundary: non-putts inside 50 yards are short game.
    static let shortGameYards = 50.0

    static func classify(shotNumber: Int, par: Int, startLie: Lie,
                         startDistanceYards: Double?, isPutt: Bool) -> ShotCategory {
        if isPutt || startLie == .green { return .putting }
        if shotNumber == 1 && par >= 4 && startLie == .tee { return .offTee }
        if let d = startDistanceYards, d <= shortGameYards { return .aroundGreen }
        return .approach
    }
}

// MARK: - Shot valuation

/// One shot with its strokes-gained value resolved.
struct ValuedShot: Identifiable {
    var id: UUID
    var shotNumber: Int
    var category: ShotCategory
    var sg: Double
    var startExpected: Double
    var endExpected: Double
    var strokesTaken: Double
    var startDistanceYards: Double
    var startLie: Lie
}

enum StrokesGained {
    /// SG = expected(start) - expected(finish) - strokes taken.
    /// A holed shot finishes at 0 expected strokes.
    static func value(startYards: Double, startLie: Lie,
                      endYards: Double, endLie: Lie,
                      penaltyStrokes: Int, holed: Bool,
                      level: BenchmarkLevel) -> Double {
        let start = ExpectedStrokes.value(distanceYards: startYards, lie: startLie, level: level)
        let end = holed ? 0 : ExpectedStrokes.value(distanceYards: endYards, lie: endLie, level: level)
        return start - end - Double(1 + max(0, penaltyStrokes))
    }
}

// MARK: - Resolving recorded holes into valued shots

/// Derives per-shot SG from the round's recorded evidence. Shots without a
/// known start distance are skipped (never invented); the final putt of a
/// completed hole is treated as holed. Holes with no usable distances still
/// contribute to the non-SG Core 11 metrics (GIR, three-putts, doubles).
enum ShotValuation {
    struct HoleValuation {
        var shots: [ValuedShot]
        /// Penalty strokes on the hole not assigned to any shot. They count
        /// against SG: Total without inventing a category attribution.
        var unassignedPenalties: Int
        var totalSG: Double { shots.reduce(0) { $0 + $1.sg } - Double(unassignedPenalties) }
    }

    /// Explicit distances win; otherwise derive start distance from the shot's
    /// GPS origin to the pin — the same math the shot-map save uses — so
    /// GPS-tracked shots (e.g. Watch swings) still value. Nil only when there
    /// is genuinely no position evidence.
    static func startDistance(of shot: TrackedShot, pin: GeoPoint?) -> Double? {
        if let d = shot.distanceToPinBeforeYards, d.isFinite, d >= 0 { return d }
        if let start = shot.start, let pin { return start.yards(to: pin) }
        return nil
    }

    static func value(hole: HoleScore, par: Int, level: BenchmarkLevel, pin: GeoPoint? = nil) -> HoleValuation {
        let resolvedPin = pin ?? hole.pinPosition.coordinate
        let ordered = hole.shots.sorted { $0.number < $1.number }
        var valued: [ValuedShot] = []
        var assignedPenalties = 0
        for (index, shot) in ordered.enumerated() {
            guard let startDist = startDistance(of: shot, pin: resolvedPin) else { continue }
            let next = index + 1 < ordered.count ? ordered[index + 1] : nil
            let endResolution = endState(after: shot, next: next, hole: hole, pin: resolvedPin, isLastRecorded: next == nil)
            guard let end = endResolution else { continue }
            let penalties = hole.penaltiesByShot?[shot.number] ?? 0
            assignedPenalties += penalties
            let category = ShotCategory.classify(shotNumber: shot.number, par: par,
                                                 startLie: shot.lie, startDistanceYards: startDist,
                                                 isPutt: shot.isPutt)
            let sg = StrokesGained.value(startYards: startDist, startLie: shot.lie,
                                         endYards: end.distanceYards, endLie: end.lie,
                                         penaltyStrokes: penalties, holed: end.holed, level: level)
            valued.append(ValuedShot(id: shot.id, shotNumber: shot.number, category: category, sg: sg,
                                     startExpected: ExpectedStrokes.value(distanceYards: startDist, lie: shot.lie, level: level),
                                     endExpected: end.holed ? 0 : ExpectedStrokes.value(distanceYards: end.distanceYards, lie: end.lie, level: level),
                                     strokesTaken: Double(1 + max(0, penalties)),
                                     startDistanceYards: startDist, startLie: shot.lie))
        }
        let unassigned = hole.penaltyStrokes > 0 && hole.penaltiesByShot == nil
            ? hole.penaltyStrokes
            : max(0, hole.penaltyStrokes - assignedPenalties)
        return HoleValuation(shots: valued, unassignedPenalties: unassigned)
    }

    private struct EndState {
        var distanceYards: Double
        var lie: Lie
        var holed: Bool
    }

    private static func endState(after shot: TrackedShot, next: TrackedShot?,
                                 hole: HoleScore, pin: GeoPoint?, isLastRecorded: Bool) -> EndState? {
        if shot.observations?.holed == true || shot.observations?.finish == .holed {
            return EndState(distanceYards: 0, lie: .green, holed: true)
        }
        if let next {
            if let d = startDistance(of: next, pin: pin) {
                return EndState(distanceYards: d, lie: next.lie, holed: false)
            }
            return nil
        }
        // Last recorded shot: a putt on a completed hole finished the job;
        // a non-putt landing at the first-putt marker ended there.
        if shot.isPutt {
            guard hole.isComplete, hole.hasScore else { return nil }
            return EndState(distanceYards: 0, lie: .green, holed: true)
        }
        if let feet = hole.firstPuttFeet, feet.isFinite, feet >= 0 {
            return EndState(distanceYards: feet / 3, lie: .green, holed: false)
        }
        if let firstPutt = hole.firstPuttPosition, let pin {
            return EndState(distanceYards: firstPutt.yards(to: pin), lie: .green, holed: false)
        }
        if let end = shot.end, let pin {
            return EndState(distanceYards: end.yards(to: pin), lie: .green, holed: false)
        }
        return nil
    }
}

// MARK: - Approach distance bands

/// GIR-by-band buckets from the plan.
enum ApproachBand: String, CaseIterable, Identifiable {
    case under100
    case band100to124
    case band125to149
    case band150to174
    case band175to199
    case over200

    var id: String { rawValue }

    var label: String {
        switch self {
        case .under100: return "<100"
        case .band100to124: return "100–124"
        case .band125to149: return "125–149"
        case .band150to174: return "150–174"
        case .band175to199: return "175–199"
        case .over200: return "200+"
        }
    }

    static func of(_ yards: Double) -> ApproachBand {
        switch yards {
        case ..<100: return .under100
        case ..<125: return .band100to124
        case ..<150: return .band125to149
        case ..<175: return .band150to174
        case ..<200: return .band175to199
        default: return .over200
        }
    }
}

// MARK: - Core 11

/// The home-screen metrics from the plan. SG figures are per round over the
/// rounds that contain valued shots; rates carry their denominators so the UI
/// can show opportunity counts and low-sample warnings.
struct Core11 {
    struct CategorySG {
        var total: Double
        var shots: Int
        var rounds: Int
        /// Per-round average over rounds containing this category. Nil when
        /// the sample is too small to trust.
        var perRound: Double? { rounds >= 1 && shots >= Core11.minSGShots ? total / Double(rounds) : nil }
    }

    struct Rate {
        var made: Int
        var opportunities: Int
        var value: Double? { opportunities >= Core11.minRateOpportunities ? Double(made) / Double(opportunities) : nil }
        /// Raw fraction regardless of sample size (for internal ranking).
        var rawValue: Double? { opportunities > 0 ? Double(made) / Double(opportunities) : nil }
    }

    var level: BenchmarkLevel
    var rounds: Int
    var holes: Int
    var sgTotal: CategorySG
    var sgByCategory: [ShotCategory: CategorySG]
    var effectiveDrivingDistance: Double?
    var drivingDistanceShots: Int
    var damaging: Rate
    var damagingPenalties: Int
    var damagingRecoveries: Int
    var girOverall: Rate
    var girByBand: [ApproachBand: Rate]
    var upAndDown: Rate
    var threePutt: Rate
    var doublePlus: Rate

    static let minSGShots = 5
    static let minRateOpportunities = 5
    static let shortGameYards = 50.0

    var hasSG: Bool { sgTotal.shots >= Self.minSGShots }

    func sg(_ category: ShotCategory) -> CategorySG {
        sgByCategory[category] ?? CategorySG(total: 0, shots: 0, rounds: 0)
    }

    /// Strokes lost per round in a category (positive means losing shots).
    func strokesLostPerRound(_ category: ShotCategory) -> Double {
        -(sg(category).perRound ?? 0)
    }

    static func compute(rounds: [GolfRound], level: BenchmarkLevel) -> Core11 {
        var totals: [ShotCategory: (sg: Double, shots: Int, roundIDs: Set<UUID>)] = [:]
        var sgRoundIDs = Set<UUID>()
        var driveDistances: [Double] = []
        var damagingMade = 0, damagingOpps = 0, damagingPen = 0, damagingRec = 0
        var girMade = 0, girOpps = 0
        var girBandMade: [ApproachBand: Int] = [:]
        var girBandOpps: [ApproachBand: Int] = [:]
        var udMade = 0, udOpps = 0
        var tpMade = 0, tpOpps = 0
        var dblMade = 0, dblOpps = 0
        var holes = 0

        for round in rounds {
            for hole in round.playedHoleScores {
                guard hole.isComplete, hole.hasScore,
                      let def = round.hole(hole.holeNumber) else { continue }
                let par = def.par
                holes += 1
                let pin = round.pinCoordinate(for: hole.holeNumber)
                let valuation = ShotValuation.value(hole: hole, par: par, level: level, pin: pin)
                if !valuation.shots.isEmpty { sgRoundIDs.insert(round.id) }
                for shot in valuation.shots {
                    var entry = totals[shot.category] ?? (0, 0, [])
                    entry.sg += shot.sg
                    entry.shots += 1
                    entry.roundIDs.insert(round.id)
                    totals[shot.category] = entry
                }

                // Driving: par-4/5 tee shots with a known outcome.
                if par >= 4 { accumulateDriving(hole: hole, distances: &driveDistances,
                                               made: &damagingMade, opps: &damagingOpps,
                                               penalties: &damagingPen, recoveries: &damagingRec) }

                // GIR overall and by band of the first approach start distance.
                if let gir = hole.greenInRegulation(par: par) {
                    girOpps += 1
                    if gir { girMade += 1 }
                    if let approachDist = firstApproachDistance(hole: hole, par: par, pin: pin) {
                        let band = ApproachBand.of(approachDist)
                        girBandOpps[band, default: 0] += 1
                        if gir { girBandMade[band, default: 0] += 1 }
                    }
                }

                // Up-and-down: missed green with a short-game shot inside 50 y.
                if let ud = upAndDownResult(hole: hole, par: par, pin: pin) {
                    udOpps += 1
                    if ud { udMade += 1 }
                }

                // Three-putts need known putts; doubles need a score.
                if hole.hasKnownPutts {
                    tpOpps += 1
                    if hole.putts >= 3 { tpMade += 1 }
                }
                dblOpps += 1
                if hole.grossScore - par >= 2 { dblMade += 1 }
            }
        }

        // Unassigned hole penalties already reduce SG: Total shot by shot via
        // HoleValuation.totalSG, but Core11 aggregates raw shot SG; fold the
        // penalty remainder into the total bucket here.
        var totalSG = totals.values.reduce(0) { $0 + $1.sg }
        let totalShots = totals.values.reduce(0) { $0 + $1.shots }
        var penaltyRemainder = 0.0
        for round in rounds {
            for hole in round.playedHoleScores {
                guard hole.isComplete, hole.hasScore,
                      let def = round.hole(hole.holeNumber) else { continue }
                penaltyRemainder += Double(ShotValuation.value(hole: hole, par: def.par, level: level, pin: round.pinCoordinate(for: hole.holeNumber)).unassignedPenalties)
            }
        }
        totalSG -= penaltyRemainder

        var byCategory: [ShotCategory: CategorySG] = [:]
        for category in ShotCategory.allCases {
            let e = totals[category] ?? (0, 0, [])
            byCategory[category] = CategorySG(total: e.sg, shots: e.shots, rounds: e.roundIDs.count)
        }
        var bands: [ApproachBand: Rate] = [:]
        for band in ApproachBand.allCases {
            bands[band] = Rate(made: girBandMade[band] ?? 0, opportunities: girBandOpps[band] ?? 0)
        }
        return Core11(
            level: level,
            rounds: rounds.count,
            holes: holes,
            sgTotal: CategorySG(total: totalSG, shots: totalShots, rounds: sgRoundIDs.count),
            sgByCategory: byCategory,
            effectiveDrivingDistance: driveDistances.isEmpty ? nil : driveDistances.reduce(0, +) / Double(driveDistances.count),
            drivingDistanceShots: driveDistances.count,
            damaging: Rate(made: damagingMade, opportunities: damagingOpps),
            damagingPenalties: damagingPen,
            damagingRecoveries: damagingRec,
            girOverall: Rate(made: girMade, opportunities: girOpps),
            girByBand: bands,
            upAndDown: Rate(made: udMade, opportunities: udOpps),
            threePutt: Rate(made: tpMade, opportunities: tpOpps),
            doublePlus: Rate(made: dblMade, opportunities: dblOpps)
        )
    }

    // MARK: Helpers

    private static let driverClubs: Set<GolfClub> = [.driver, .wood3, .wood5]

    private static func accumulateDriving(hole: HoleScore, distances: inout [Double],
                                          made: inout Int, opps: inout Int,
                                          penalties: inout Int, recoveries: inout Int) {
        let ordered = hole.shots.sorted { $0.number < $1.number }
        guard let tee = ordered.first, tee.number == 1, tee.lie == .tee else {
            // Score-only holes: penalties still signal damage when assigned.
            if hole.penaltyStrokes > 0, hole.shots.isEmpty {
                opps += 1
                made += 1
                penalties += hole.penaltyStrokes
            }
            return
        }
        opps += 1
        let teePenalties = hole.penaltiesByShot?[1] ?? 0
        let finish = tee.observations?.finish
        let penalized = teePenalties > 0 || finish == .water || finish == .outOfBounds
        let second = ordered.dropFirst().first
        let recovered = second?.lie == .recovery
        if penalized { penalties += 1 }
        if recovered { recoveries += 1 }
        if penalized || recovered { made += 1; return }
        // Clean drives with a measured, trustworthy distance count.
        if let club = tee.club, driverClubs.contains(club), tee.includeInTrueDistance {
            if let carry = tee.carryYards, carry > 0 { distances.append(carry) }
            else if let traveled = tee.traveledYards, traveled > 0 { distances.append(traveled) }
        }
    }

    /// Start distance of the first approach-category shot, for banding GIR.
    static func firstApproachDistance(hole: HoleScore, par: Int, pin: GeoPoint? = nil) -> Double? {
        let resolvedPin = pin ?? hole.pinPosition.coordinate
        for shot in hole.shots.sorted(by: { $0.number < $1.number }) {
            guard let d = ShotValuation.startDistance(of: shot, pin: resolvedPin) else { continue }
            let category = ShotCategory.classify(shotNumber: shot.number, par: par,
                                                 startLie: shot.lie, startDistanceYards: d,
                                                 isPutt: shot.isPutt)
            if category == .approach { return d }
        }
        return nil
    }

    /// Nil when the hole cannot be judged (no short-game evidence, GIR made,
    /// or ambiguous unassigned penalties).
    static func upAndDownResult(hole: HoleScore, par: Int, pin: GeoPoint? = nil) -> Bool? {
        guard hole.greenInRegulation(par: par) == false else { return nil }
        let resolvedPin = pin ?? hole.pinPosition.coordinate
        let ordered = hole.shots.sorted { $0.number < $1.number }
        guard let firstShort = ordered.first(where: { shot in
            guard !shot.isPutt, let d = ShotValuation.startDistance(of: shot, pin: resolvedPin) else { return false }
            return d <= shortGameYards
        }) else { return nil }
        let penaltiesAfter: Int?
        if let assignments = hole.penaltiesByShot {
            penaltiesAfter = assignments.filter { $0.key >= firstShort.number }.values.reduce(0, +)
        } else if hole.penaltyStrokes == 0 {
            penaltiesAfter = 0
        } else {
            return nil // cannot tell where the penalties happened
        }
        let strokesAfter = hole.grossScore - firstShort.number + 1 - (penaltiesAfter ?? 0)
        return strokesAfter <= 2
    }
}

// MARK: - Tier 2 diagnostics

/// One tap below the home dashboard: explains *why* a Core 11 metric moved.
/// Every figure carries its sample size; small samples surface as low-sample
/// notes in the UI rather than confident claims.
struct Tier2Diagnostics {
    struct Driving {
        var playable: Core11.Rate
        var penalty: Core11.Rate
        var recovery: Core11.Rate
        var missDirection: [ShotShape: Int]
        var strikeDistribution: [Contact: Int]
        var drivesMeasured: Int
    }
    struct Approach {
        /// Median finish proximity (yards) by band, using every approach with
        /// a known finish — not GIR approaches only.
        var medianLeaveByBand: [ApproachBand: Double]
        var approachCountByBand: [ApproachBand: Int]
        var shortMisses: Int
        var longMisses: Int
        var leftMisses: Int
        var rightMisses: Int
        var sgFromFairway: Double?
        var sgFromRough: Double?
        var fairwayApproaches: Int
        var roughApproaches: Int
        /// Farthest band with at least half the greens hit.
        var fiftyPercentGIRBand: ApproachBand?
    }
    struct ShortGame {
        var proximityUnder10: [Double]
        var proximity10to19: [Double]
        var proximity20to50: [Double]
        var twoChipRate: Core11.Rate
        var poorStrikeRate: Core11.Rate
        var sandSave: Core11.Rate
    }
    struct Putting {
        /// Make counts by first-putt band (feet). Only holes with a known
        /// first-putt distance contribute.
        var makesByBand: [String: (made: Int, attempts: Int)]
        var lagSuccess: Core11.Rate
        var averageSecondPuttFeet: Double?
        var threePuttOriginsFeet: [Double]
        var puttsPerGIR: Double?
    }

    var driving: Driving
    var approach: Approach
    var shortGame: ShortGame
    var putting: Putting

    static let puttBands: [(label: String, range: ClosedRange<Double>)] = [
        ("0–2 ft", 0...2), ("3–5 ft", 3...5), ("6–9 ft", 6...9),
        ("10–15 ft", 10...15), ("16–25 ft", 16...25), ("25+ ft", 25...10_000),
    ]

    static func compute(rounds: [GolfRound], level: BenchmarkLevel) -> Tier2Diagnostics {
        var playableMade = 0, playableOpps = 0
        var penMade = 0, penOpps = 0
        var recMade = 0, recOpps = 0
        var shapes: [ShotShape: Int] = [:]
        var contacts: [Contact: Int] = [:]
        var drivesMeasured = 0
        var leaveByBand: [ApproachBand: [Double]] = [:]
        var shortMiss = 0, longMiss = 0, leftMiss = 0, rightMiss = 0
        var sgFairway = 0.0, nFairway = 0, sgRough = 0.0, nRough = 0
        var girBandMade: [ApproachBand: Int] = [:]
        var girBandOpps: [ApproachBand: Int] = [:]
        var proxShort: [Double] = [], proxMid: [Double] = [], proxLong: [Double] = []
        var twoChipMade = 0, twoChipOpps = 0
        var poorMade = 0, poorOpps = 0
        var sandMade = 0, sandOpps = 0
        var makesByBand: [String: (made: Int, attempts: Int)] = [:]
        var lagMade = 0, lagOpps = 0
        var secondPutts: [Double] = []
        var threePuttOrigins: [Double] = []
        var puttsOnGIR = 0, girHolesWithPutts = 0

        for round in rounds {
            for hole in round.playedHoleScores {
                guard hole.isComplete, hole.hasScore,
                      let def = round.hole(hole.holeNumber) else { continue }
                let par = def.par
                let pin = round.pinCoordinate(for: hole.holeNumber)
                let ordered = hole.shots.sorted { $0.number < $1.number }
                let valuation = ShotValuation.value(hole: hole, par: par, level: level, pin: pin)
                let valuedByID = Dictionary(uniqueKeysWithValues: valuation.shots.map { ($0.id, $0) })

                // Driving diagnostics from par-4/5 tee shots.
                if par >= 4, let tee = ordered.first, tee.number == 1, tee.lie == .tee {
                    let teePen = hole.penaltiesByShot?[1] ?? 0
                    let finish = tee.observations?.finish
                    let penalized = teePen > 0 || finish == .water || finish == .outOfBounds
                    let recovered = ordered.dropFirst().first?.lie == .recovery
                    penOpps += 1; recOpps += 1; playableOpps += 1
                    if penalized { penMade += 1 }
                    if recovered { recMade += 1 }
                    if !penalized, !recovered { playableMade += 1 }
                    if let shape = tee.shape { shapes[shape, default: 0] += 1 }
                    if let contact = tee.contact { contacts[contact, default: 0] += 1 }
                    if let carry = tee.carryYards, carry > 0, tee.includeInTrueDistance { drivesMeasured += 1 }
                }

                // Approach + short-game diagnostics from valued shots.
                var argShotsBeforeGreen = 0
                var sawGreensideBunker = false
                for shot in ordered {
                    guard let valued = valuedByID[shot.id] else { continue }
                    switch valued.category {
                    case .approach:
                        if let finishDist = finishDistance(of: shot, in: ordered, hole: hole, pin: pin) {
                            leaveByBand[ApproachBand.of(valued.startDistanceYards), default: []].append(finishDist)
                        }
                        if shot.lie == .fairway || shot.lie == .tee { sgFairway += valued.sg; nFairway += 1 }
                        if shot.lie == .rough { sgRough += valued.sg; nRough += 1 }
                        if let gir = hole.greenInRegulation(par: par) {
                            let band = ApproachBand.of(valued.startDistanceYards)
                            // Attribute the hole outcome to its first approach only.
                            if Core11.firstApproachDistance(hole: hole, par: par, pin: pin) == valued.startDistanceYards {
                                girBandOpps[band, default: 0] += 1
                                if gir { girBandMade[band, default: 0] += 1 }
                            }
                        }
                        if shot.observations?.depthMiss == .short { shortMiss += 1 }
                        if shot.observations?.depthMiss == .long { longMiss += 1 }
                        if shot.observations?.lateralMiss == .left { leftMiss += 1 }
                        if shot.observations?.lateralMiss == .right { rightMiss += 1 }
                    case .aroundGreen:
                        argShotsBeforeGreen += 1
                        if let finishDist = finishDistance(of: shot, in: ordered, hole: hole, pin: pin) {
                            let feet = finishDist * 3
                            if valued.startDistanceYards * 3 < 30 { proxShort.append(feet) }
                            else if valued.startDistanceYards * 3 < 60 { proxMid.append(feet) }
                            else { proxLong.append(feet) }
                        }
                        if shot.lie == .sand { sawGreensideBunker = true }
                        if let contact = shot.contact {
                            poorOpps += 1
                            if contact == .fat || contact == .thin || contact == .top || contact == .shank { poorMade += 1 }
                        }
                    case .putting, .offTee:
                        break
                    }
                }
                if hole.greenInRegulation(par: par) == false, argShotsBeforeGreen > 0 {
                    twoChipOpps += 1
                    if argShotsBeforeGreen >= 2 { twoChipMade += 1 }
                }
                if sawGreensideBunker, hole.greenInRegulation(par: par) == false {
                    let ud = Core11.upAndDownResult(hole: hole, par: par, pin: pin)
                    if ud != nil {
                        sandOpps += 1
                        if ud == true { sandMade += 1 }
                    }
                }

                // Putting diagnostics.
                if hole.hasKnownPutts {
                    if let first = hole.firstPuttFeet, first.isFinite, first >= 0 {
                        let band = puttBands.first { $0.range.contains(first) }?.label ?? "25+ ft"
                        var entry = makesByBand[band] ?? (0, 0)
                        entry.attempts += 1
                        if hole.putts == 1 { entry.made += 1 }
                        makesByBand[band] = entry
                        if first >= 25 {
                            lagOpps += 1
                            // Lag success: second putt inside 3 ft ~= at most 2 putts total
                            // with no three-putt. Conservative: holed in ≤ 2.
                            if hole.putts <= 2 { lagMade += 1 }
                            if hole.putts >= 3 { threePuttOrigins.append(first) }
                        } else if hole.putts >= 3 {
                            threePuttOrigins.append(first)
                        }
                    }
                    if hole.putts == 2, let first = hole.firstPuttFeet, first >= 25 {
                        // Long first putt holed in two implies a short second.
                        secondPutts.append(min(first / 4, 6))
                    }
                    if hole.greenInRegulation(par: par) == true {
                        puttsOnGIR += hole.putts
                        girHolesWithPutts += 1
                    }
                }
            }
        }

        var medianLeave: [ApproachBand: Double] = [:]
        var counts: [ApproachBand: Int] = [:]
        for (band, leaves) in leaveByBand {
            counts[band] = leaves.count
            medianLeave[band] = leaves.sorted()[leaves.count / 2]
        }
        var fifty: ApproachBand?
        for band in ApproachBand.allCases {
            let opps = girBandOpps[band] ?? 0
            if opps >= 3, Double(girBandMade[band] ?? 0) / Double(opps) >= 0.5 {
                fifty = band
            }
        }
        return Tier2Diagnostics(
            driving: Driving(
                playable: Core11.Rate(made: playableMade, opportunities: playableOpps),
                penalty: Core11.Rate(made: penMade, opportunities: penOpps),
                recovery: Core11.Rate(made: recMade, opportunities: recOpps),
                missDirection: shapes, strikeDistribution: contacts, drivesMeasured: drivesMeasured),
            approach: Approach(
                medianLeaveByBand: medianLeave, approachCountByBand: counts,
                shortMisses: shortMiss, longMisses: longMiss, leftMisses: leftMiss, rightMisses: rightMiss,
                sgFromFairway: nFairway >= Core11.minSGShots ? sgFairway / Double(max(1, nFairway)) : nil,
                sgFromRough: nRough >= Core11.minSGShots ? sgRough / Double(max(1, nRough)) : nil,
                fairwayApproaches: nFairway, roughApproaches: nRough,
                fiftyPercentGIRBand: fifty),
            shortGame: ShortGame(
                proximityUnder10: proxShort, proximity10to19: proxMid, proximity20to50: proxLong,
                twoChipRate: Core11.Rate(made: twoChipMade, opportunities: twoChipOpps),
                poorStrikeRate: Core11.Rate(made: poorMade, opportunities: poorOpps),
                sandSave: Core11.Rate(made: sandMade, opportunities: sandOpps)),
            putting: Putting(
                makesByBand: makesByBand,
                lagSuccess: Core11.Rate(made: lagMade, opportunities: lagOpps),
                averageSecondPuttFeet: secondPutts.isEmpty ? nil : secondPutts.reduce(0, +) / Double(secondPutts.count),
                threePuttOriginsFeet: threePuttOrigins,
                puttsPerGIR: girHolesWithPutts > 0 ? Double(puttsOnGIR) / Double(girHolesWithPutts) : nil)
        )
    }

    /// Finish proximity of one valued shot in yards, via the next shot's
    /// start distance (explicit or GPS-derived) or the first-putt marker.
    private static func finishDistance(of shot: TrackedShot, in ordered: [TrackedShot], hole: HoleScore, pin: GeoPoint?) -> Double? {
        guard let index = ordered.firstIndex(where: { $0.id == shot.id }) else { return nil }
        if index + 1 < ordered.count {
            return ShotValuation.startDistance(of: ordered[index + 1], pin: pin ?? hole.pinPosition.coordinate)
        }
        if let feet = hole.firstPuttFeet { return feet / 3 }
        return nil
    }
}

// MARK: - Versioned reference benchmarks

/// Published-figure defaults used for peer context. Every value carries its
/// source so the UI can label figures as directional, and the plan's caveat
/// applies: verify against the original source before any marketing claim.
enum ReferenceBenchmarks {
    static let version = "2026.09-ref-v1"
    /// Arccos-derived average driver distance by handicap (yards).
    static let drivingDistance: [(range: String, yards: Double)] = [
        ("0–4.9", 244), ("5–9.9", 234), ("10–14.9", 223),
    ]
    static let longTermDrivingTarget = 240.0
    /// Penalty + recovery shares (Arccos via plan): ~7% penalties, ~16%
    /// recovery for 10–15 handicaps; combined target below 12%.
    static let damagingCombinedTarget = 0.12
    /// Shot Scope up-and-down inside 50 y: ~39% (10 hcp), ~54% (scratch).
    static let upAndDown: [(level: BenchmarkLevel, rate: Double)] = [
        (.scratch, 0.54), (.hcp10, 0.39),
    ]
    /// Shot Scope three-putt: ~7% (10 hcp); 4% directional scratch target.
    static let threePutt: [(level: BenchmarkLevel, rate: Double)] = [
        (.scratch, 0.04), (.hcp10, 0.07),
    ]
    /// Approach proximity (feet) by start distance: 10 hcp vs scratch.
    static let proximity: [(band: String, hcp10: Double, scratch: Double)] = [
        ("100–150 yd", 48, 31), ("150–200 yd", 70, 43), ("200+ yd", 92, 56),
    ]
    static let girDirectionalTarget = 0.50
}

// MARK: - Big-number autopsy

/// Primary cause of a double bogey or worse. The first meaningful error wins;
/// later errors are preserved as secondary causes.
enum DoubleCause: String, CaseIterable, Identifiable {
    case teePenalty
    case teeRecovery
    case approachPenalty
    case poorShortGameStrike
    case twoChip
    case threePutt
    case fourPutt
    case unassignedPenalty
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .teePenalty: return "Tee penalty"
        case .teeRecovery: return "Tee recovery"
        case .approachPenalty: return "Approach penalty"
        case .poorShortGameStrike: return "Poor short-game strike"
        case .twoChip: return "Two-chip"
        case .threePutt: return "Three-putt"
        case .fourPutt: return "Four-putt"
        case .unassignedPenalty: return "Penalty"
        case .other: return "Other"
        }
    }
}

struct DoubleAutopsy: Identifiable {
    var id: UUID
    var roundID: UUID
    var holeNumber: Int
    var par: Int
    var score: Int
    var primary: DoubleCause
    var secondary: [DoubleCause]

    static func autopsy(rounds: [GolfRound]) -> [DoubleAutopsy] {
        var result: [DoubleAutopsy] = []
        for round in rounds {
            for hole in round.playedHoleScores {
                guard hole.isComplete, hole.hasScore,
                      let def = round.hole(hole.holeNumber),
                      hole.grossScore - def.par >= 2 else { continue }
                result.append(autopsy(hole: hole, par: def.par, roundID: round.id, pin: round.pinCoordinate(for: hole.holeNumber)))
            }
        }
        return result
    }

    static func autopsy(hole: HoleScore, par: Int, roundID: UUID, pin: GeoPoint? = nil) -> DoubleAutopsy {
        let resolvedPin = pin ?? hole.pinPosition.coordinate
        let ordered = hole.shots.sorted { $0.number < $1.number }
        var secondary: [DoubleCause] = []
        var primary: DoubleCause = .other

        func note(_ cause: DoubleCause) {
            if primary == .other { primary = cause } else if !secondary.contains(cause) { secondary.append(cause) }
        }

        let teePen = hole.penaltiesByShot?[1] ?? 0
        if teePen > 0 || ordered.first?.observations?.finish == .outOfBounds || ordered.first?.observations?.finish == .water {
            if ordered.first?.number == 1, par >= 4 { note(.teePenalty) }
        }
        if ordered.dropFirst().first?.lie == .recovery { note(.teeRecovery) }
        let approachPen = ordered.contains { shot in
            guard shot.number > 1, !shot.isPutt else { return false }
            return (hole.penaltiesByShot?[shot.number] ?? 0) > 0
        }
        if approachPen { note(.approachPenalty) }
        let argShots = ordered.filter { shot in
            guard !shot.isPutt, let d = ShotValuation.startDistance(of: shot, pin: resolvedPin) else { return false }
            return d <= Core11.shortGameYards
        }
        let poorStrike = argShots.contains { [.fat, .thin, .top, .shank].contains($0.contact) }
        if poorStrike { note(.poorShortGameStrike) }
        if argShots.count >= 2 { note(.twoChip) }
        if hole.hasKnownPutts {
            if hole.putts >= 4 { note(.fourPutt) }
            else if hole.putts >= 3 { note(.threePutt) }
        }
        if hole.penaltyStrokes > 0, primary == .other {
            note(hole.penaltiesByShot == nil ? .unassignedPenalty : .other)
        }
        return DoubleAutopsy(id: hole.id, roundID: roundID, holeNumber: hole.holeNumber,
                             par: par, score: hole.grossScore, primary: primary, secondary: secondary)
    }
}

// MARK: - Rolling windows

/// Last round / last 5 / last 10 / season slices over newest-first rounds.
enum RollingWindow: String, CaseIterable, Identifiable {
    case last
    case last5
    case last10
    case season
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last: return "Last round"
        case .last5: return "Rolling 5"
        case .last10: return "Rolling 10"
        case .season: return "Season"
        case .all: return "All rounds"
        }
    }

    func slice(_ newestFirst: [GolfRound]) -> [GolfRound] {
        switch self {
        case .last: return Array(newestFirst.prefix(1))
        case .last5: return Array(newestFirst.prefix(5))
        case .last10: return Array(newestFirst.prefix(10))
        case .season:
            guard let year = newestFirst.first?.startedAt else { return [] }
            let calendar = Calendar.current
            return newestFirst.filter { calendar.isDate($0.startedAt, equalTo: year, toGranularity: .year) }
        case .all: return newestFirst
        }
    }
}

// MARK: - Practice decision engine

/// One primary + one secondary focus, ranked by the plan's priority score:
///
///     priority = strokes lost × recurrence × controllability × confidence
///
/// with the repeated cause, a skill/strategy/data split, and a transfer
/// metric to re-measure over the next five and ten rounds.
struct PracticeRecommendation {
    enum IssueKind: String {
        case skill
        case strategy
        case data
    }
    struct Focus {
        var category: ShotCategory
        var title: String
        var cause: String
        var kind: IssueKind
        var drill: String
        var target: String
        var transferMetric: String
        var transferBaseline: String
        var priority: Double
    }
    var primary: Focus?
    var secondary: Focus?
    var takeaway: String
}

enum PracticePlan {
    static func recommend(core: Core11, diagnostics: Tier2Diagnostics,
                          autopsies: [DoubleAutopsy]) -> PracticeRecommendation {
        var focuses: [PracticeRecommendation.Focus] = []
        for category in ShotCategory.allCases {
            let lost = max(0, core.strokesLostPerRound(category))
            guard lost > 0.05, core.sg(category).shots >= Core11.minSGShots else { continue }
            let recurrence = recurrenceShare(for: category, in: autopsies, core: core)
            let confidence = min(1, Double(core.sg(category).shots) / 30)
            let priority = lost * recurrence * category.controllability * confidence
            focuses.append(focus(for: category, lost: lost, core: core,
                                 diagnostics: diagnostics, priority: priority))
        }
        let ranked = focuses.sorted { $0.priority > $1.priority }
        return PracticeRecommendation(
            primary: ranked.first,
            secondary: ranked.dropFirst().first,
            takeaway: takeaway(core: core)
        )
    }

    // MARK: Private

    private static func recurrenceShare(for category: ShotCategory, in autopsies: [DoubleAutopsy], core: Core11) -> Double {
        guard !autopsies.isEmpty else { return 0.6 }
        let matching: Int
        switch category {
        case .offTee: matching = autopsies.filter { [.teePenalty, .teeRecovery].contains($0.primary) }.count
        case .approach: matching = autopsies.filter { [.approachPenalty].contains($0.primary) }.count
        case .aroundGreen: matching = autopsies.filter { [.poorShortGameStrike, .twoChip].contains($0.primary) }.count
        case .putting: matching = autopsies.filter { [.threePutt, .fourPutt].contains($0.primary) }.count
        }
        return 0.3 + 0.7 * Double(matching) / Double(autopsies.count)
    }

    private static func focus(for category: ShotCategory, lost: Double, core: Core11,
                              diagnostics: Tier2Diagnostics, priority: Double) -> PracticeRecommendation.Focus {
        let lostText = String(format: "%.1f", lost)
        switch category {
        case .approach:
            let weakBand = core.girByBand
                .filter { $0.value.opportunities >= 3 }
                .min { ($0.value.rawValue ?? 1) < ($1.value.rawValue ?? 1) }
            let shortMisses = diagnostics.approach.shortMisses
            let totalMiss = shortMisses + diagnostics.approach.longMisses
            let cause: String
            let kind: PracticeRecommendation.IssueKind
            if let weak = weakBand {
                cause = "GIR collapses in the \(weak.key.label)-yard band; \(lostText) shots lost per round here."
                kind = .skill
            } else if totalMiss > 0, Double(shortMisses) / Double(totalMiss) >= 0.5 {
                cause = "Misses are short too often — check carry numbers and club selection; \(lostText) shots lost per round."
                kind = .strategy
            } else if diagnostics.approach.roughApproaches >= 5,
                      (diagnostics.approach.sgFromRough ?? 0) < (diagnostics.approach.sgFromFairway ?? 0) - 0.3 {
                cause = "Approach play from rough lags the fairway by a clear margin."
                kind = .strategy
            } else {
                cause = "\(lostText) shots lost per round on approaches."
                kind = core.holes < 30 ? .data : .skill
            }
            return PracticeRecommendation.Focus(
                category: category, title: "Sharpen approach play",
                cause: cause, kind: kind,
                drill: "Take your weakest band to the range: 5 balls each at three approach distances, aiming at the center. Record finish side (short/long/left/right) and verify carry numbers.",
                target: "Goal: 10 of 15 within 15 yards, fewest misses short",
                transferMetric: "SG: Approach per round", transferBaseline: "\(lostText) lost", priority: priority)
        case .offTee:
            let rate = core.damaging.rawValue ?? 0
            let cause: String
            let kind: PracticeRecommendation.IssueKind
            if rate >= ReferenceBenchmarks.damagingCombinedTarget {
                cause = "Damaging drives (penalty or recovery) on \(Int((rate * 100).rounded()))% of par-4/5 tee shots; \(lostText) shots lost per round."
                kind = .strategy
            } else if let dist = core.effectiveDrivingDistance, dist < ReferenceBenchmarks.longTermDrivingTarget {
                cause = "Tee shots are playable but short (\(Int(dist.rounded())) yd effective); \(lostText) shots lost per round."
                kind = .skill
            } else {
                cause = "\(lostText) shots lost per round off the tee."
                kind = core.holes < 30 ? .data : .skill
            }
            return PracticeRecommendation.Focus(
                category: category, title: "Make the tee shot an advantage",
                cause: cause, kind: kind,
                drill: "Driver stays the default where your 80% dispersion fits the landing zone. Hit 10 balls at a fairway-width corridor; when trouble narrows it, rehearse the shorter-club target instead.",
                target: "Goal: damaging drives below 12%",
                transferMetric: "SG: Off the tee per round", transferBaseline: "\(lostText) lost", priority: priority)
        case .aroundGreen:
            let twoChip = diagnostics.shortGame.twoChipRate.rawValue ?? 0
            let poor = diagnostics.shortGame.poorStrikeRate.rawValue ?? 0
            let cause: String
            let kind: PracticeRecommendation.IssueKind
            if twoChip >= 0.15 {
                cause = "Two-chip rate \(Int((twoChip * 100).rounded()))% — the first chip leaves too much work."
                kind = .skill
            } else if poor >= 0.15 {
                cause = "Poor strike (heavy/thin/topped) on \(Int((poor * 100).rounded()))% of recorded short-game shots."
                kind = .skill
            } else {
                cause = "\(lostText) shots lost per round around the green."
                kind = core.holes < 30 ? .data : .skill
            }
            return PracticeRecommendation.Focus(
                category: category, title: "Convert more up-and-downs",
                cause: cause, kind: kind,
                drill: "From 10, 20 and 30 yards, hit 5 balls each to a 6-foot circle. Log proximity and strike; repeat the same setup to compare.",
                target: "Goal: 10 of 15 inside 6 feet",
                transferMetric: "SG: Around the green per round", transferBaseline: "\(lostText) lost", priority: priority)
        case .putting:
            let threePutt = core.threePutt.rawValue ?? 0
            let cause: String
            let kind: PracticeRecommendation.IssueKind
            if threePutt >= 0.05 {
                cause = "Three-putts on \(Int((threePutt * 100).rounded()))% of holes with known putts — usually lag speed, not short misses."
                kind = .skill
            } else {
                cause = "\(lostText) shots lost per round putting."
                kind = core.holes < 30 ? .data : .skill
            }
            return PracticeRecommendation.Focus(
                category: category, title: "Tighten lag speed",
                cause: cause, kind: kind,
                drill: "Roll 5 balls each from 20, 30 and 40 feet. Finish every ball inside a 3-foot circle, then hole out.",
                target: "Goal: 12 of 15 inside 3 feet",
                transferMetric: "SG: Putting per round", transferBaseline: "\(lostText) lost", priority: priority)
        }
    }

    private static func takeaway(core: Core11) -> String {
        let best = ShotCategory.allCases
            .compactMap { cat -> (ShotCategory, Double)? in
                guard let per = core.sg(cat).perRound else { return nil }
                return (cat, per)
            }
            .max { $0.1 < $1.1 }
        if let best, best.1 > 0.1 {
            return "Strength to keep: \(best.0.label) gains \(String(format: "%+.1f", best.1)) per round vs \(core.level.label)."
        }
        if core.hasSG { return "No category is gaining yet — the plan below targets the biggest leak first." }
        return "Record shot distances (start and finish) to unlock strokes-gained insights."
    }
}

// MARK: - GolfEvidence bridge

extension GolfEvidence {
    /// Core 11 vs the given benchmark (scratch by default).
    func core11(level: BenchmarkLevel = .default) -> Core11 {
        Core11.compute(rounds: rounds, level: level)
    }

    func diagnostics(level: BenchmarkLevel = .default) -> Tier2Diagnostics {
        Tier2Diagnostics.compute(rounds: rounds, level: level)
    }

    func autopsies() -> [DoubleAutopsy] {
        DoubleAutopsy.autopsy(rounds: rounds)
    }

    func practiceRecommendation(level: BenchmarkLevel = .default,
                                handicap: Double? = nil) -> PracticeRecommendation {
        let core = self.core11(level: level)
        _ = handicap // reserved: peer-level cause thresholds keyed off handicap
        return PracticePlan.recommend(core: core, diagnostics: diagnostics(level: level), autopsies: autopsies())
    }
}
