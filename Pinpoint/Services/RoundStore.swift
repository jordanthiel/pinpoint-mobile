import Foundation

/// Local-first store for on-course rounds. Persists to Application Support
/// as JSON; Supabase sync for rounds ships with the migration in
/// `supabase/migrations/*_rounds.sql` and reuses the app's auth session.
@Observable
final class RoundStore {
    var activeRound: GolfRound?
    var pastRounds: [GolfRound] = []
    var clubBag: ClubBag = .standard
    var lastError: String?

    let watchDetector = WatchShotDetector()

    private let fileManager = FileManager.default

    private var rootURL: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinpoint", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var roundsURL: URL { rootURL.appendingPathComponent("rounds.json") }
    private var activeURL: URL { rootURL.appendingPathComponent("active-round.json") }
    private var bagURL: URL { rootURL.appendingPathComponent("club-bag.json") }

    init() {
        load()
    }

    // MARK: - Persistence

    func load() {
        if let data = try? Data(contentsOf: roundsURL),
           let decoded = try? JSONDecoder().decode([GolfRound].self, from: data) {
            pastRounds = decoded.sorted { $0.startedAt > $1.startedAt }
        }
        if let data = try? Data(contentsOf: activeURL),
           let decoded = try? JSONDecoder().decode(GolfRound.self, from: data),
           decoded.status == .active {
            activeRound = decoded
        }
        if let data = try? Data(contentsOf: bagURL),
           let decoded = try? JSONDecoder().decode(ClubBag.self, from: data),
           !decoded.clubs.isEmpty {
            clubBag = decoded
        } else {
            clubBag = .standard
            saveBag()
        }
    }

    private func saveBag() {
        do {
            try JSONEncoder().encode(clubBag).write(to: bagURL, options: [.atomic])
        } catch {
            lastError = "Couldn't save your bag."
        }
    }

    func setBagCarry(_ club: GolfClub, yards: Double) {
        var bag = clubBag
        bag.upsert(club, carryYards: yards)
        clubBag = bag
        saveBag()
    }

    func updateBagEntry(_ entry: ClubBagEntry) {
        var bag = clubBag
        bag.update(entry)
        clubBag = bag
        saveBag()
    }

    func addClubToBag(_ club: GolfClub, nickname: String? = nil, yards: Double? = nil) {
        var bag = clubBag
        bag.add(club, nickname: nickname, carryYards: yards)
        clubBag = bag
        saveBag()
    }

    func removeClubFromBag(_ club: GolfClub) {
        var bag = clubBag
        bag.remove(club)
        clubBag = bag
        saveBag()
    }

    func removeBagEntry(id: UUID) {
        var bag = clubBag
        bag.remove(id: id)
        clubBag = bag
        saveBag()
    }

    func resetClubBag() {
        clubBag = .standard
        saveBag()
    }

    func bagCarry(for club: GolfClub) -> Double {
        clubBag.carry(for: club) ?? club.stockYards
    }

    private func save() {
        do {
            try JSONEncoder().encode(pastRounds).write(to: roundsURL, options: [.atomic])
            if let activeRound {
                try JSONEncoder().encode(activeRound).write(to: activeURL, options: [.atomic])
            } else {
                try? fileManager.removeItem(at: activeURL)
            }
        } catch {
            lastError = "Couldn't save your rounds."
        }
    }

    // MARK: - Round lifecycle

    func startRound(course: GolfCourse, teeName: String, roundType: RoundType,
                   scoringMode: ScoringMode, startHole: Int = 1) {
        let round = GolfRound(course: course, teeName: teeName, roundType: roundType,
                              scoringMode: scoringMode, startHole: startHole)
        // Holes start empty; the GPS view seeds distance-to-pin from each
        // hole's yardage until the golfer adds, claims, or dictates shots.
        activeRound = round
        save()
    }

    func finishRound() {
        guard var round = activeRound else { return }
        round.status = .finished
        round.finishedAt = Date()
        pastRounds.insert(round, at: 0)
        activeRound = nil
        save()
    }

    func discardActiveRound() {
        activeRound = nil
        save()
    }

    func setCurrentHole(_ number: Int) {
        activeRound?.currentHoleNumber = number
        save()
    }

    func setRecap(_ text: String) {
        activeRound?.recap = text
        save()
    }

    // MARK: - Hole editing

    func updateHole(_ holeNumber: Int, mutate: (inout HoleScore) -> Void) {
        guard var round = activeRound,
              let idx = round.holeScores.firstIndex(where: { $0.holeNumber == holeNumber })
        else { return }
        mutate(&round.holeScores[idx])
        activeRound = round
        save()
    }

    /// Writes the hole sheet (score / putts / penalties / fairway) without requiring shots.
    /// Later shot mapping does not overwrite `recordedScore` / `recordedPutts`.
    func recordHoleScore(_ holeNumber: Int, score: Int, putts: Int, penalties: Int, fairwayHit: Bool?) {
        updateHole(holeNumber) { hole in
            hole.applyRecordedScore(score: score, putts: putts, penalties: penalties, fairwayHit: fairwayHit)
        }
    }

    func addShot(_ holeNumber: Int, _ shot: TrackedShot) {
        updateHole(holeNumber) { hole in
            var s = shot
            s.number = (hole.shots.map(\.number).max() ?? 0) + 1
            hole.shots.append(s)
            hole.shots.sort { $0.number < $1.number }
        }
    }

    func updateShot(_ holeNumber: Int, _ shot: TrackedShot) {
        updateHole(holeNumber) { hole in
            if let idx = hole.shots.firstIndex(where: { $0.id == shot.id }) {
                hole.shots[idx] = shot
            }
        }
    }

    func deleteShot(_ holeNumber: Int, id: UUID) {
        updateHole(holeNumber) { hole in
            hole.shots.removeAll { $0.id == id }
            for i in hole.shots.indices { hole.shots[i].number = i + 1 }
        }
    }

    func nextShotNumber(_ holeNumber: Int) -> Int {
        guard let round = activeRound,
              let hole = round.score(for: holeNumber)
        else { return 1 }
        return (hole.shots.map(\.number).max() ?? 0) + 1
    }

    /// Current ball state for the GPS view: distance left + suggested lie.
    func ballState(_ holeNumber: Int) -> (distanceYards: Double, lie: Lie) {
        guard let round = activeRound,
              let holeDef = round.hole(holeNumber),
              let hole = round.score(for: holeNumber)
        else { return (150, .tee) }
        if hole.shots.isEmpty {
            if let ball = round.ballCoordinate(for: holeNumber),
               let pin = round.pinCoordinate(for: holeNumber) {
                return (ball.yards(to: pin), .tee)
            }
            return (Double(holeDef.yardage), .tee)
        }
        // Prefer live GPS remaining when the last shot has an end point.
        if let ball = round.ballCoordinate(for: holeNumber),
           let pin = round.pinCoordinate(for: holeNumber) {
            let remaining = ball.yards(to: pin)
            return (remaining, nextLie(after: hole.shots[hole.shots.count - 1], remaining: remaining))
        }
        var remaining = Double(holeDef.yardage)
        var lie: Lie = .tee
        for shot in hole.shots {
            if let carry = shot.carryYards {
                remaining = max(0, remaining - carry)
            } else if let d = shot.distanceToPinBeforeYards {
                remaining = max(0, d - (shot.club?.stockYards ?? 150))
            } else {
                remaining = max(0, remaining - (shot.club?.stockYards ?? 150))
            }
            lie = nextLie(after: shot, remaining: remaining)
        }
        return (remaining, lie)
    }

    private func nextLie(after shot: TrackedShot, remaining: Double) -> Lie {
        if shot.club?.isPutter == true { return .green }
        if remaining <= 25 { return .green }
        if remaining <= 45 { return .fringe }
        // Misses scatter: poor quality or lateral shapes find the rough.
        // Deterministic on purpose — the suggestion must not flip between recomputes.
        if shot.quality == .poor || shot.shape == .slice || shot.shape == .hook {
            return .rough
        }
        if shot.lie == .sand { return .fairway }
        return .fairway
    }

    // MARK: - Dictation

    /// Converts a parsed dictation into real shots appended to the hole.
    /// Returns the number of shots added.
    @discardableResult
    func applyDictation(_ result: HoleDictationResult, to holeNumber: Int) -> Int {
        guard let round = activeRound,
              let holeDef = round.hole(holeNumber),
              var hole = round.score(for: holeNumber)
        else { return 0 }
        var added = 0
        var nextNumber = (hole.shots.map(\.number).max() ?? 0) + 1
        var lie: Lie = hole.shots.isEmpty ? .tee : ballState(holeNumber).lie
        var remaining = hole.shots.isEmpty ? Double(holeDef.yardage) : ballState(holeNumber).distanceYards

        for parsed in result.shots {
            let isApproach = remaining < 220 && nextNumber > 1
            let club = parsed.club ?? (isApproach ? .sandWedge : .iron7)
            let shotLie: Lie = parsed.lie ?? (club.isPutter ? .green : lie)
            let stock = bagCarry(for: club)
            let shot = TrackedShot(
                number: nextNumber,
                club: club,
                lie: shotLie,
                distanceToPinBeforeYards: remaining,
                carryYards: club.isPutter ? nil : min(remaining, stock),
                contact: parsed.contact,
                shape: parsed.shape,
                quality: parsed.quality,
                source: .dictation,
                note: parsed.note
            )
            hole.shots.append(shot)
            nextNumber += 1
            added += 1
            if let leftFeet = parsed.leftFeet {
                remaining = leftFeet / 3.0
                lie = remaining <= 8 ? .green : .fringe
            } else {
                remaining = max(0, remaining - stock)
                lie = remaining <= 25 ? .green : .fairway
            }
        }
        let structuredPutts = result.shots.filter { $0.club?.isPutter == true }.count
        if let putts = result.puttsMentioned, putts > structuredPutts {
            for _ in 0..<(putts - structuredPutts) {
                hole.shots.append(TrackedShot(number: nextNumber, club: .putter,
                                              lie: .green, distanceToPinBeforeYards: remaining,
                                              source: .dictation))
                nextNumber += 1
                added += 1
            }
        }
        if hole.firstPuttFeet == nil, result.puttsMentioned != nil || structuredPutts > 0 {
            hole.firstPuttFeet = result.shots.compactMap(\.leftFeet).last ?? max(2, remaining * 3)
        }
        var analysis = result.leftoverNote
        if let call = result.scoreCall {
            let line = "Called \(call)"
            if analysis.isEmpty {
                analysis = line
            } else if !analysis.localizedCaseInsensitiveContains("called \(call)") {
                analysis += " · " + line
            }
        }
        updateHole(holeNumber) {
            $0.shots = hole.shots
            $0.firstPuttFeet = hole.firstPuttFeet
            // Fill recorded putts / score from the spoken recap only when the
            // golfer hasn't already locked them in on the score sheet.
            if $0.recordedPutts == nil, let mentioned = result.puttsMentioned {
                $0.recordedPutts = mentioned
            }
            if $0.recordedScore == nil,
               let call = result.scoreCall,
               let fromCall = HoleScore.score(fromCall: call, par: holeDef.par) {
                $0.recordedScore = fromCall
                $0.isComplete = true
            }
            if !analysis.isEmpty {
                if let existing = $0.analysisNote, !existing.isEmpty, existing != analysis {
                    $0.analysisNote = existing + " · " + analysis
                } else {
                    $0.analysisNote = analysis
                }
            }
        }
        return added
    }

    // MARK: - Stats (review later)

    /// Personal per-club average carry across all finished rounds + active round.
    func clubAverages() -> [GolfClub: Double] {
        var sums: [GolfClub: (total: Double, count: Int)] = [:]
        for round in (pastRounds + (activeRound.map { [$0] } ?? [])) {
            for hole in round.holeScores {
                for shot in hole.shots where shot.includeInTrueDistance {
                    guard let club = shot.club, !club.isPutter,
                          let carry = shot.carryYards, carry > 20, carry < 400
                    else { continue }
                    let cur = sums[club] ?? (0, 0)
                    sums[club] = (cur.total + carry, cur.count + 1)
                }
            }
        }
        return sums.compactMapValues { $0.count > 0 ? $0.total / Double($0.count) : nil }
    }

    struct RoundStats: Equatable {
        var holesPlayed: Int
        var fairwaysHit: Int
        var fairwaysTotal: Int
        var girHit: Int
        var girTotal: Int
        var totalPutts: Int
        var avgFirstPuttFt: Double?
        var averageScore: Double?

        var fairwayPct: Double? {
            guard fairwaysTotal > 0 else { return nil }
            return Double(fairwaysHit) / Double(fairwaysTotal) * 100
        }

        var girPct: Double? {
            guard girTotal > 0 else { return nil }
            return Double(girHit) / Double(girTotal) * 100
        }
    }

    func stats(for rounds: [GolfRound]) -> RoundStats {
        var fwHit = 0, fwTotal = 0, girHit = 0, girTotal = 0, putts = 0
        var firstPutts: [Double] = []
        var scores: [Int] = []
        for round in rounds {
            for hole in round.holeScores where hole.hasScore {
                guard let def = round.hole(hole.holeNumber) else { continue }
                if let fw = hole.fairwayHit(par: def.par) {
                    fwTotal += 1
                    if fw { fwHit += 1 }
                }
                if let gir = hole.greenInRegulation(par: def.par) {
                    girTotal += 1
                    if gir { girHit += 1 }
                }
                putts += hole.putts
                if let fp = hole.firstPuttFeet { firstPutts.append(fp) }
                scores.append(hole.grossScore)
            }
        }
        return RoundStats(
            holesPlayed: scores.count,
            fairwaysHit: fwHit, fairwaysTotal: fwTotal,
            girHit: girHit, girTotal: girTotal,
            totalPutts: putts,
            avgFirstPuttFt: firstPutts.isEmpty ? nil : firstPutts.reduce(0, +) / Double(firstPutts.count),
            averageScore: scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
        )
    }

    var allRoundsStats: RoundStats {
        stats(for: pastRounds + (activeRound.map { [$0] } ?? []))
    }
}
