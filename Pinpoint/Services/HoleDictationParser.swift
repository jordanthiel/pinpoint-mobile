import Foundation

/// Structured result of parsing a hole dictation, e.g.
/// "I hit a seven iron, off the toe, and I pulled it, then my approach
///  with a sand wedge to five feet. Good shot."
struct HoleDictationResult: Equatable {
    struct ParsedShot: Equatable {
        var club: GolfClub?
        var contact: Contact?
        var shape: ShotShape?
        var quality: ShotQuality?
        /// "to five feet" / "to 150 yards" — distance the ball finished from the pin.
        var leftFeet: Double?
        var putts: Int?
        var note: String
    }

    var shots: [ParsedShot]
    /// Total putts mentioned (e.g. "two putts", "one-putted").
    var puttsMentioned: Int?
    var confidence: Double // 0...1
    var warnings: [String]

    var isEmpty: Bool { shots.isEmpty && puttsMentioned == nil }
}

/// Rule-based, on-device parser. No network, deterministic, simulator-safe.
/// `Speech` transcription feeds it; a typed fallback works identically.
enum HoleDictationParser {
    static let examplePrompt = "I hit a seven iron, off the toe, and I pulled it. Then my approach, sand wedge to five feet. Good shot. Two putts."

    static func parse(_ transcript: String) -> HoleDictationResult {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return HoleDictationResult(shots: [], puttsMentioned: nil,
                                       confidence: 0, warnings: ["Nothing to parse yet."])
        }
        let lower = text.lowercased()
        var warnings: [String] = []

        // Split into per-shot clauses. "approach", "then", "next", periods all split.
        var clauses = splitClauses(lower)
        if clauses.isEmpty { clauses = [lower] }
        // Cap: a hole rarely needs more than 10 tracked full swings.
        if clauses.count > 10 {
            warnings.append("Split into \(clauses.count) parts — keeping the first 10.")
            clauses = Array(clauses.prefix(10))
        }

        var shots: [HoleDictationResult.ParsedShot] = []
        var putts: Int?
        for clause in clauses {
            if let p = parsePutts(clause) {
                if putts == nil { putts = p } else { putts! += p }
                continue
            }
            let club = GolfClub.match(in: clause)
            let contact = parseContact(clause)
            let shape = parseShape(clause)
            let quality = parseQuality(clause)
            let leftFeet = parseLeftDistance(clause)
            // Skip filler clauses with no signal ("yeah that was it").
            if club == nil && contact == nil && shape == nil && quality == nil && leftFeet == nil {
                continue
            }
            let parsed = HoleDictationResult.ParsedShot(club: club, contact: contact, shape: shape,
                                                              quality: quality, leftFeet: leftFeet,
                                                              putts: nil, note: "")
            if parsed.club == nil, var last = shots.last {
                // Continuation ("…and I pulled it", "good shot"): fold detail
                // into the previous shot instead of minting a clubless one.
                if last.contact == nil { last.contact = parsed.contact }
                if last.shape == nil { last.shape = parsed.shape }
                if last.quality == nil { last.quality = parsed.quality }
                if last.leftFeet == nil { last.leftFeet = parsed.leftFeet }
                shots[shots.count - 1] = last
            } else {
                shots.append(parsed)
            }
        }

        // Global putt mentions also count ("finished with two putts" as its own clause
        // is handled above; this catches "...and two-putted for par").
        if putts == nil { putts = parsePutts(lower) }

        if shots.isEmpty && putts == nil {
            warnings.append("Couldn't pick out clubs or putts — tap a shot to add it manually.")
        }
        if shots.contains(where: { $0.club == nil }) {
            warnings.append("One shot has no club — pick it before saving.")
        }

        let clubbed = Double(shots.filter { $0.club != nil }.count)
        let detailed = Double(shots.filter { $0.shape != nil || $0.contact != nil }.count)
        let puttBonus = putts != nil ? 0.15 : 0.0
        let confidence = min(1.0, 0.35 + 0.15 * clubbed + 0.1 * detailed + puttBonus)
        return HoleDictationResult(shots: shots, puttsMentioned: putts,
                                   confidence: confidence, warnings: warnings)
    }

    // MARK: - Clauses

    static func splitClauses(_ text: String) -> [String] {
        var work = text
        let separators = [" and then ", " then ", ". ", "!", "? ", "; ",
                          " next ", " after that ", " approach ", " my second ",
                          " my third ", " tee shot "]
        for sep in separators {
            work = work.replacingOccurrences(of: sep, with: "\n")
        }
        return work.split(separator: "\n")
            .map { raw -> String in
                var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
                s = s.replacingOccurrences(of: ",", with: " ")
                while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
                return s
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - Attributes

    static func parseContact(_ clause: String) -> Contact? {
        let t = " \(clause) "
        if t.contains(" off the toe ") || t.contains(" out of the toe ") || t.contains(" toey ") { return .toe }
        if t.contains(" off the heel ") || t.contains(" hosel ") || t.contains(" shank ") { return .shank }
        if t.contains(" heel ") { return .heel }
        if t.contains(" thin ") || t.contains(" bladed ") || t.contains(" skull") { return .thin }
        if t.contains(" fat ") || t.contains(" chunk") || t.contains(" heavy ") || t.contains(" behind it ") { return .fat }
        if t.contains(" top") || t.contains(" topped ") { return .top }
        if t.contains(" pure ") || t.contains(" pured ") || t.contains(" centered ")
            || t.contains(" middle of the face ") || t.contains(" flushed ") { return .pure }
        return nil
    }

    static func parseShape(_ clause: String) -> ShotShape? {
        let t = " \(clause) "
        if t.contains(" pull") { return .pull }
        if t.contains(" push") { return .push }
        if t.contains(" slice") { return .slice }
        if t.contains(" hook") { return .hook }
        if t.contains(" draw") { return .draw }
        if t.contains(" fade ") || t.contains(" cut ") { return .fade }
        if t.contains(" straight ") || t.contains(" right at it ") || t.contains(" down the middle ") { return .straight }
        return nil
    }

    static func parseQuality(_ clause: String) -> ShotQuality? {
        let t = " \(clause) "
        if t.contains(" great ") || t.contains(" excellent ") || t.contains(" perfect ")
            || t.contains(" striped ") || t.contains(" money ") { return .great }
        if t.contains(" good ") || t.contains(" nice ") || t.contains(" solid ")
            || t.contains(" decent ") { return .good }
        if t.contains(" poor ") || t.contains(" bad ") || t.contains(" terrible ")
            || t.contains(" awful ") || t.contains(" duff") { return .poor }
        if t.contains(" okay ") || t.contains(" ok ") || t.contains(" fine ") { return .ok }
        return nil
    }

    /// "...to five feet" / "...to 12 ft" / "...150 yards out" / "...pin high".
    static func parseLeftDistance(_ clause: String) -> Double? {
        let t = clause.lowercased()
        let numbers: [String: Double] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
            "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        ]
        // "to <n> feet/ft"
        let pattern = #"(?:to|about|roughly|around)\s+(\d+|[a-z]+)\s*(feet|foot|ft|yards?|yds?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let numRange = Range(m.range(at: 1), in: t),
           let unitRange = Range(m.range(at: 2), in: t) {
            let numStr = String(t[numRange])
            let unit = String(t[unitRange])
            let value = Double(numStr) ?? numbers[numStr]
            if let value {
                return unit.hasPrefix("y") ? value * 3 : value // normalize to feet
            }
        }
        if t.contains("pin high") || t.contains("hole high") { return 15 }
        if t.contains(" gimme") || t.contains(" kick-in") || t.contains(" kick in") { return 3 }
        if t.contains(" stuffed ") || t.contains(" tight ") { return 6 }
        return nil
    }

    /// "two putts" / "one-putt" / "three-putted" / "made the putt".
    static func parsePutts(_ clause: String) -> Int? {
        let t = " \(clause.lowercased()) "
        let spelled = ["one": 1, "two": 2, "three": 3, "four": 4]
        for (word, n) in spelled {
            if t.contains(" \(word) putt") || t.contains(" \(word)-putt") { return n }
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d)\s*-?\s*putts?\b"#),
           let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let r = Range(m.range(at: 1), in: t),
           let n = Int(t[r]) { return n }
        if t.contains(" made the putt") || t.contains(" sank it") || t.contains(" holed it")
            || t.contains(" one-putted") || t.contains(" one putted") { return 1 }
        if t.contains(" lagged ") && t.contains(" putt") { return 2 }
        return nil
    }
}
