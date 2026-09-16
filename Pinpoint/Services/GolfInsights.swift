import Foundation

struct PracticeFocus: Identifiable {
    var id: String
    var title: String
    var icon: String
    var evidence: String
    var opportunity: Double
    var drill: String
    var target: String
}

/// Computed facts are shared by the dashboard, coach and practice plan.
/// Unknown putting/fairway data never counts as a miss or a zero.
struct GolfEvidence {
    var rounds: [GolfRound]
    var completed: [(round: GolfRound, hole: HoleScore, par: Int)] {
        rounds.flatMap { round in
            round.playedHoleScores.compactMap { hole in
                guard hole.isComplete, hole.hasScore, let definition = round.hole(hole.holeNumber) else { return nil }
                return (round, hole, definition.par)
            }
        }
    }
    var putting: [HoleScore] { completed.map(\.hole).filter { $0.recordedPutts != nil || $0.shots.contains(where: \.isPutt) } }
    var threePutts: Int { putting.filter { $0.putts >= 3 }.count }
    var penalties: Int { completed.reduce(0) { $0 + $1.hole.penaltyStrokes } }
    var averageToPar: Double? { completed.isEmpty ? nil : Double(completed.reduce(0) { $0 + $1.hole.grossScore - $1.par }) / Double(completed.count) }
    var fairways: [Bool] { completed.compactMap { $0.round.fairwayHit(for: $0.hole.holeNumber) } }
    var greens: [Bool] { completed.compactMap { $0.hole.greenInRegulation(par: $0.par) } }
    var measuredShots: [TrackedShot] { completed.flatMap { $0.hole.shots }.filter { $0.includeInTrueDistance && !$0.isPutt && ($0.carryYards ?? 0) > 0 } }
    var focus: [PracticeFocus] {
        var items: [PracticeFocus] = []
        if threePutts > 0 {
            items.append(PracticeFocus(id: "putting", title: "Control your first putt", icon: "flag.fill",
                evidence: "\(threePutts) three-putt holes in \(putting.count) holes with putting recorded.", opportunity: Double(threePutts) / Double(max(putting.count, 1)),
                drill: "Roll 5 balls each from 20, 30 and 40 feet. Finish every ball inside a 3-foot circle, then hole out. Log how many of 15 finish inside the circle.", target: "Goal: 12 of 15 inside 3 feet"))
        }
        if penalties > 0 {
            items.append(PracticeFocus(id: "control", title: "Keep the next ball in play", icon: "scope",
                evidence: "\(penalties) penalty strokes across \(completed.count) completed holes.", opportunity: Double(penalties) / Double(max(completed.count, 1)),
                drill: "Pick a fairway-width corridor at the range. Hit 10 tee shots with your driver, then 10 with a shorter club. Record playable shots for each. Use the more reliable club when trouble narrows the landing area.", target: "Goal: 8 of 10 playable shots"))
        }
        let misses = greens.filter { !$0 }.count
        if misses > 0 {
            items.append(PracticeFocus(id: "approach", title: "Build a reliable approach", icon: "figure.golf",
                evidence: "\(misses) missed greens in \(greens.count) holes with GIR evidence. GIR is inferred from scoring or shot records.", opportunity: Double(misses) / Double(greens.count) * 0.4,
                drill: "Choose three approach distances from your bag. Hit 5 balls to each target, aiming at the center. Record which finish within 15 yards and whether misses are short, long, left or right.", target: "Goal: 10 of 15 within 15 yards"))
        }
        let fairwayMisses = fairways.filter { !$0 }.count
        if fairwayMisses > 0 {
            items.append(PracticeFocus(id: "tee", title: "Tighten your tee-shot pattern", icon: "arrow.up.forward",
                evidence: "\(fairwayMisses) missed fairways in \(fairways.count) recorded par-4 and par-5 holes.", opportunity: Double(fairwayMisses) / Double(fairways.count) * 0.3,
                drill: "Set a start-line target and hit 10 balls with the same tee club. Record each start direction and finish. Choose a target that gives your common miss more room on the course.", target: "Goal: 7 of 10 in your corridor"))
        }
        return items.sorted { $0.opportunity > $1.opportunity }
    }
    static func percentage(_ values: [Bool]) -> String {
        values.isEmpty ? "—" : "\(Int((Double(values.filter { $0 }.count) / Double(values.count) * 100).rounded()))%"
    }
    var scoringBreakdown: String {
        (3...5).map { par in
            let holes = completed.filter { $0.par == par }
            guard !holes.isEmpty else { return "Par \(par): no scored holes." }
            let average = Double(holes.reduce(0) { $0 + $1.hole.grossScore }) / Double(holes.count)
            return "Par \(par): \(String(format: "%.2f", average)) average score, \(holes.count) holes."
        }.joined(separator: "\n")
    }
    var clubBreakdown: String {
        let grouped = Dictionary(grouping: measuredShots.filter { $0.club != nil }, by: { $0.club! })
        return grouped.sorted { $0.key.stockYards > $1.key.stockYards }.map { club, shots in
            let carries = shots.compactMap(\.carryYards).sorted()
            let mean = carries.reduce(0, +) / Double(carries.count)
            return "\(club.displayName): mean \(Int(mean.rounded())) yd, recorded range \(Int(carries.first!))–\(Int(carries.last!)) yd, n=\(carries.count)."
        }.joined(separator: "\n")
    }
    var patternBreakdown: String {
        let shots = completed.flatMap { $0.hole.shots }.filter { !$0.isPutt }
        let shapes = Dictionary(grouping: shots.compactMap(\.shape), by: { $0 })
        let contacts = Dictionary(grouping: shots.compactMap(\.contact), by: { $0 })
        let shapeText = shapes.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.label): \($0.value.count)" }.joined(separator: ", ")
        let contactText = contacts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.label): \($0.value.count)" }.joined(separator: ", ")
        return "Recorded shapes: \(shapeText.isEmpty ? "none" : shapeText). Recorded contacts: \(contactText.isEmpty ? "none" : contactText)."
    }

    var observationBreakdown: String {
        let shots = completed.flatMap { $0.hole.shots }
        let groups = Dictionary(grouping: shots, by: { $0.club?.displayName ?? "Unknown club" })
        return groups.keys.sorted().map { club in
            let rows = groups[club]!
            func counts(_ values: [String]) -> String {
                Dictionary(grouping: values, by: { $0 }).sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value.count)" }.joined(separator: ", ")
            }
            return "\(club) explicitly recorded: contacts [\(counts(rows.compactMap { $0.contact?.rawValue }))]; shapes [\(counts(rows.compactMap { $0.shape?.rawValue }))]; finishes [\(counts(rows.compactMap { $0.observations?.finish?.rawValue }))]; lateral misses [\(counts(rows.compactMap { $0.observations?.lateralMiss?.rawValue }))]; depth misses [\(counts(rows.compactMap { $0.observations?.depthMiss?.rawValue }))]; putt breaks [\(counts(rows.compactMap { $0.observations?.puttBreak?.rawValue }))]; putt miss sides [\(counts(rows.compactMap { $0.observations?.puttMissSide?.rawValue }))]. Missing observations excluded."
        }.joined(separator: "\n")
    }

    var summary: String {
        """
        Scope: \(rounds.count) rounds, \(completed.count) completed scored holes.
        Average score relative to par per hole: \(averageToPar.map { String(format: "%+.2f", $0) } ?? "unknown").
        Fairways: \(Self.percentage(fairways)) from \(fairways.count) known outcomes.
        GIR (inferred): \(Self.percentage(greens)) from \(greens.count) known outcomes.
        Three-putts: \(threePutts) of \(putting.count) holes with known putts. Penalty strokes: \(penalties).
        \(scoringBreakdown)
        \(clubBreakdown)
        \(patternBreakdown)
        \(observationBreakdown)
        \(focus.map { "Priority: \($0.title). Evidence: \($0.evidence) Drill: \($0.drill) \($0.target)" }.joined(separator: "\n"))
        """
    }
    var detail: String {
        let rows = completed.prefix(90).map { item in
            let hole = item.hole
            let shots = hole.shots.map { shot in
                "\(shot.club?.displayName ?? "unknown club") carry=\(shot.carryYards.map { String(format: "%.0f", $0) } ?? "unknown") contact=\(shot.contact?.rawValue ?? "unknown") shape=\(shot.shape?.rawValue ?? "unknown") \(shot.observations?.evidence ?? "additional observations unknown") mappedDistanceYards=\(shot.mappedDistanceYards.map { String($0) } ?? "unknown") clubSuggested=\(shot.clubWasSuggested == true) traveledYards=\(shot.traveledYards.map { String($0) } ?? "unknown") remainingFeet=\(shot.remainingFeet.map { String($0) } ?? "unknown") note=\(String(shot.note.prefix(120)))"
            }.joined(separator: "; ")
            return "\(item.round.startedAt.formatted(date: .abbreviated, time: .omitted)) \(item.round.courseName) hole \(hole.holeNumber): par \(item.par), score \(hole.grossScore), putts \(putting.contains(where: { $0.id == hole.id }) ? String(hole.putts) : "unknown"), penalties \(hole.penaltyStrokes), penaltiesByShot \(hole.penaltiesByShot?.description ?? "unassigned"). Shots: \(shots). Notes: \(String((hole.analysisNote ?? "").prefix(200))). Original recap: \(String(hole.dictateTranscript.prefix(300)))"
        }
        return rows.joined(separator: "\n")
    }
}

struct CoachReply {
    var text: String
    var engine: String
}

enum GolfCoach {
    static func answer(_ question: String, evidence: GolfEvidence, history: String) async -> CoachReply {
        guard !evidence.completed.isEmpty else {
            return CoachReply(text: "Complete and score a hole to start building your golf profile. Add putts, fairways and shot details for more specific answers. I don't have recorded results to analyze yet.", engine: "Data check")
        }
        var unavailableReason = ""
        do {
            let text = try await OpenAIGolfService.coach(question: question,
                evidence: evidence.summary + "\nHOLE EVIDENCE (bounded excerpt)\n" + String(evidence.detail.prefix(12000)), history: history)
            return CoachReply(text: text, engine: "OpenAI · recorded golf data")
        } catch { unavailableReason = error.localizedDescription }
        let lower = question.lowercased()
        var text = evidence.summary
        if lower.contains("putt") {
            text = "You recorded \(evidence.threePutts) three-putt holes across \(evidence.putting.count) holes with putting data. " + (evidence.focus.first { $0.id == "putting" }?.drill ?? "Record first-putt distances and total putts to distinguish distance control from short-putt performance.")
        } else if lower.contains("club") || lower.contains("distance") {
            let grouped = Dictionary(grouping: evidence.measuredShots.filter { $0.club != nil }, by: { $0.club! })
            text = grouped.sorted { $0.key.stockYards > $1.key.stockYards }.map { club, shots in
                let carries = shots.compactMap(\.carryYards)
                return "\(club.displayName): \(Int((carries.reduce(0, +) / Double(carries.count)).rounded())) yd average from \(carries.count) recorded carries."
            }.joined(separator: "\n")
            if text.isEmpty { text = "No measured carries in this selection. Record shot distances to build club-specific evidence; stock bag distances aren't personal measurements." }
        } else if lower.contains("practice") || lower.contains("improve") {
            text = evidence.focus.first.map { "\($0.title)\n\($0.evidence)\n\n\($0.drill)\n\($0.target)" } ?? evidence.summary
        } else {
            text = "Here is the recorded summary for your selection:\n\n" + text
        }
        return CoachReply(text: unavailableReason + "\n\n" + text, engine: "Recorded-data summary · OpenAI unavailable")
    }
}
