import Foundation

/// The model interprets narration. Code validates types, ranges and source quotes,
/// and maps returned fields directly into an editable review draft.
enum HoleRecapLLM {
    static func containsQuote(_ quote: String, in transcript: String) -> Bool {
        func normalize(_ value: String) -> String {
            value.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let quote = normalize(quote)
        return !quote.isEmpty && normalize(transcript).contains(quote)
    }
    static func bounded(_ value: Double?, _ maximum: Double) -> Bool {
        value.map { $0.isFinite && (0...maximum).contains($0) } ?? true
    }
    private static func field<T: RawRepresentable>(_ value: String?, as type: T.Type) throws -> T? where T.RawValue == String {
        guard let value else { return nil }
        guard let result = T(rawValue: value) else { throw GolfAIError.invalidResponse }
        return result
    }
    static func shot(_ shot: OpenAIShotFields, transcript: String) throws -> HoleDictationResult.ParsedShot {
        guard containsQuote(shot.evidence, in: transcript), bounded(shot.distanceYards, 500), bounded(shot.carryYards, 500),
              bounded(shot.leftFeet, 1500), bounded(shot.startingDistanceFeet, 3000) else { throw GolfAIError.invalidResponse }
        let club: GolfClub?
        if let name = shot.club {
            // Legacy single-hole responses used display names; v2 uses canonical IDs.
            club = GolfClub(rawValue: name) ?? GolfClub.allCases.first { $0.displayName.lowercased() == name.lowercased() }
            guard club != nil else { throw GolfAIError.invalidResponse }
        } else { club = nil }
        let observations = try ShotObservations(
            finish: field(shot.finish, as: ShotFinish.self), lateralMiss: field(shot.lateralMiss, as: LateralMiss.self),
            depthMiss: field(shot.depthMiss, as: DepthMiss.self), puttBreak: field(shot.breakDirection, as: PuttBreak.self),
            puttMissSide: field(shot.puttMissSide, as: PuttMissSide.self), holed: shot.holed,
            carryYards: shot.carryYards, startingDistanceFeet: shot.startingDistanceFeet)
        return try .init(club: club, lie: field(shot.lie, as: Lie.self), contact: field(shot.contact, as: Contact.self),
                         shape: field(shot.shape, as: ShotShape.self), quality: field(shot.quality, as: ShotQuality.self),
                         leftFeet: shot.leftFeet, putts: club == .putter ? 1 : nil, outcome: shot.outcome ?? "",
                         distanceYards: shot.distanceYards, breakDirection: shot.breakDirection ?? "", note: shot.note ?? "",
                         observations: observations, sourceQuote: shot.evidence)
    }
    static func grounded(_ response: OpenAIRecap, transcript: String) -> HoleDictationResult? {
        guard response.shots.count <= 50, response.puttsMentioned.map({ (0...15).contains($0) }) ?? true,
              response.scoreCall.map({ ["albatross", "eagle", "birdie", "par", "bogey", "double", "triple"].contains($0) }) ?? true,
              let shots = try? response.shots.map({ try shot($0, transcript: transcript) }) else { return nil }
        return .init(shots: shots, puttsMentioned: response.puttsMentioned, scoreCall: response.scoreCall,
                     leftoverNote: transcript, confidence: 0, warnings: [])
    }
    static func drafts(_ response: OpenAIRoundRecap, transcript: String, round: GolfRound) throws -> [RecapDraft] {
        guard response.holes.count <= 18, Set(response.holes.map(\.holeNumber)).count == response.holes.count else { throw GolfAIError.invalidResponse }
        return try response.holes.sorted { $0.holeNumber < $1.holeNumber }.map { hole in
            guard round.hole(hole.holeNumber) != nil, containsQuote(hole.evidence, in: transcript),
                  hole.score.map({ (1...30).contains($0) }) ?? true,
                  hole.putts.map({ (0...15).contains($0) }) ?? true,
                  hole.penalties.map({ (0...15).contains($0) }) ?? true,
                  var result = grounded(.init(shots: hole.shots, puttsMentioned: hole.putts, scoreCall: hole.scoreCall), transcript: transcript)
            else { throw GolfAIError.invalidResponse }
            result.leftoverNote = hole.notes
            result.warnings = response.warnings + hole.warnings
            if let score = hole.score, (hole.putts ?? 0) + (hole.penalties ?? 0) > score {
                result.warnings.append("Putts plus penalties exceed the score. Please correct the totals before saving.")
            }
            return RecapDraft(holeNumber: hole.holeNumber, transcript: hole.evidence, result: result,
                              score: hole.score, putts: hole.putts, penalties: hole.penalties,
                              fairway: hole.fairwayHit, selected: true)
        }
    }
}
