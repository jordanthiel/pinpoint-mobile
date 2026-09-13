import Foundation

/// Which engine produced a hole-recap structure.
enum HoleRecapEngine: String {
    case apple
    case rules
}

/// Dictation → structured hole data. Tries on-device Apple Intelligence
/// (Foundation Models, iOS 26+) first and falls back to the deterministic
/// rule parser when the model is unavailable or fails. Anything the engine
/// can't place in a field lands in `leftoverNote`, which the app saves as
/// the hole's analysis note.
enum HoleRecapLLM {
    static func structure(_ transcript: String) async -> (HoleDictationResult, HoleRecapEngine) {
        if let result = await appleStructure(transcript) {
            return (result, .apple)
        }
        return (HoleDictationParser.parse(transcript), .rules)
    }

    private static func appleStructure(_ transcript: String) async -> HoleDictationResult? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return await AppleRecap.parse(transcript)
        }
        #endif
        return nil
    }

    /// Map Apple-extracted strings onto the rule parser's enums so both
    /// engines produce the same shape. Unrecognized values fold into notes.
    static func mapShot(_ shot: AppleShotFields) -> HoleDictationResult.ParsedShot {
        let club = shot.club.flatMap { GolfClub.match(in: $0) }
        let contact = shot.contact.flatMap { HoleDictationParser.parseContact($0) }
        let shape = shot.shape.flatMap { HoleDictationParser.parseShape($0) }
        var noteBits: [String] = []
        if let s = shot.contact, contact == nil, !s.isEmpty { noteBits.append(s) }
        if let s = shot.shape, shape == nil, !s.isEmpty { noteBits.append(s) }
        let outcome = validatedOutcome(shot.outcome, noteBits: &noteBits)
        let breakDirection = validatedBreak(shot.breakDirection, noteBits: &noteBits)
        if let s = shot.puttMiss, !s.isEmpty { noteBits.append("putt missed \(s)") }
        if let s = shot.note, !s.isEmpty { noteBits.append(s) }
        let isPutter = club?.isPutter ?? false
        return HoleDictationResult.ParsedShot(
            club: club,
            lie: shot.lie.flatMap { HoleDictationParser.parseLie($0) } ?? (isPutter ? .green : nil),
            contact: contact,
            shape: shape,
            quality: shot.made == true ? .good : nil,
            leftFeet: shot.leftFeet,
            putts: isPutter ? 1 : nil,
            outcome: outcome,
            distanceYards: shot.distanceYards,
            breakDirection: breakDirection,
            note: HoleDictationParser.uniqueBits(noteBits)
        )
    }

    static func validatedOutcome(_ value: String?, noteBits: inout [String]) -> String {
        let known = ["missed left", "missed right", "short", "long", "fairway",
                     "green", "bunker", "water", "out of bounds", "holed"]
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !v.isEmpty else { return "" }
        if known.contains(v) { return v }
        noteBits.append(v)
        return ""
    }

    static func validatedBreak(_ value: String?, noteBits: inout [String]) -> String {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !v.isEmpty else { return "" }
        if v == "left to right" || v == "right to left" { return v }
        noteBits.append(v)
        return ""
    }
}

/// Plain-data view of one LLM-extracted shot. Kept free of Apple-only types
/// so the mapping above compiles on every deployment target.
struct AppleShotFields {
    var club: String?
    var distanceYards: Double?
    var leftFeet: Double?
    var contact: String?
    var shape: String?
    var outcome: String?
    var breakDirection: String?
    var puttMiss: String?
    var lie: String?
    var made: Bool?
    var note: String?
}

#if canImport(FoundationModels)
import FoundationModels

/// Apple Intelligence implementation. Gated to iOS 26+; everything else in
/// this file works back to the app's deployment target.
@available(iOS 26, *)
private enum AppleRecap {
    @Generable
    struct Recap {
        @Guide(description: "One entry per full swing or putt, in the order hit")
        var shots: [Shot]
        @Guide(description: "Total putts mentioned, if any")
        var puttsMentioned: Int?
        @Guide(description: "Hole score the golfer called: birdie, par, bogey, eagle, double")
        var scoreCall: String?
        @Guide(description: "Anything spoken that fits no field — feel, wind, misc color")
        var leftoverNote: String
    }

    @Generable
    struct Shot {
        @Guide(description: "Club: driver, 3 wood, hybrid, 7 iron, pitching wedge, sand wedge, putter, ...")
        var club: String?
        @Guide(description: "How far the shot travelled, in yards")
        var distanceYards: Double?
        @Guide(description: "Distance the ball finished from the pin, in feet")
        var leftFeet: Double?
        @Guide(description: "Contact: toe, heel, thin, fat, top, pure, shank")
        var contact: String?
        @Guide(description: "Shape: draw, fade, slice, hook, pull, push, straight")
        var shape: String?
        @Guide(description: "Outcome: missed left, missed right, short, long, fairway, green, bunker, water, out of bounds, holed")
        var outcome: String?
        @Guide(description: "Putt break: left to right or right to left")
        var breakDirection: String?
        @Guide(description: "Where a putt missed: left, right, short, long, high side, low side")
        var puttMiss: String?
        @Guide(description: "Lie: tee, fairway, rough, sand, green, fringe")
        var lie: String?
        @Guide(description: "True when the shot was holed or the putt was made")
        var made: Bool?
        @Guide(description: "Anything about this shot that fits no field")
        var note: String?
    }

    static func parse(_ transcript: String) async -> HoleDictationResult? {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              SystemLanguageModel.default.isAvailable
        else { return nil }
        let prompt = """
        Extract a golf hole recap into structured shots. One entry per full swing or putt, in order. \
        Use the exact vocabularies given for club, contact, shape, outcome, breakDirection and puttMiss; \
        leave a field out when it wasn't said. Put everything else in leftoverNote or per-shot note, never drop it.
        Recap: \(transcript)
        """
        do {
            let response = try await LanguageModelSession().respond(to: prompt, generating: Recap.self)
            return convert(response.content)
        } catch {
            return nil
        }
    }

    private static func convert(_ recap: Recap) -> HoleDictationResult {
        let shots = recap.shots.map { s in
            HoleRecapLLM.mapShot(AppleShotFields(
                club: s.club, distanceYards: s.distanceYards, leftFeet: s.leftFeet,
                contact: s.contact, shape: s.shape, outcome: s.outcome,
                breakDirection: s.breakDirection, puttMiss: s.puttMiss,
                lie: s.lie, made: s.made, note: s.note
            ))
        }
        let putterShots = shots.filter { $0.club?.isPutter == true }.count
        var putts = recap.puttsMentioned
        if putts == nil, putterShots > 0 { putts = putterShots }
        var noteBits: [String] = []
        for shot in shots where !shot.note.isEmpty { noteBits.append(shot.note) }
        if !recap.leftoverNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteBits.append(recap.leftoverNote)
        }
        var call = ""
        if let c = recap.scoreCall?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["birdie", "par", "bogey", "eagle", "double"].contains(c) {
            call = c
        } else if let c = recap.scoreCall, !c.isEmpty {
            noteBits.append(c)
        }
        let detailed = Double(shots.filter { $0.shape != nil || $0.contact != nil || !$0.note.isEmpty }.count)
        let confidence = min(0.9, 0.5 + 0.1 * Double(shots.count) + 0.05 * detailed)
        var warnings = [String]()
        if shots.isEmpty && putts == nil {
            warnings.append("The AI couldn't pick out clubs or putts — tap a shot to add it manually.")
        }
        if shots.contains(where: { $0.club == nil }) {
            warnings.append("One shot has no club — pick it before saving.")
        }
        return HoleDictationResult(
            shots: shots, puttsMentioned: putts,
            scoreCall: call.isEmpty ? nil : call,
            leftoverNote: HoleDictationParser.uniqueBits(noteBits),
            confidence: confidence, warnings: warnings
        )
    }
}
#endif
