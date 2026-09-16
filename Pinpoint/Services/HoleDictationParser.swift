import Foundation

/// Structured result of parsing a hole dictation, e.g.
/// "hit a driver off the tee, slightly toed it, so missed left, then hit a
///  four iron, chunked it, hit sand wedge, good contact, put it to about
///  10 feet, putt, miss the putt on the high side for a par."
struct HoleDictationResult: Equatable {
    struct ParsedShot: Equatable {
        var club: GolfClub?
        var lie: Lie?
        var contact: Contact?
        var shape: ShotShape?
        var quality: ShotQuality?
        /// "to five feet" / "to 150 yards" — distance the ball finished from the pin.
        var leftFeet: Double?
        var putts: Int?
        /// Miss/result outcome: "missed left", "missed right", "short", "long",
        /// "fairway", "green", "bunker", "water", "out of bounds", "holed".
        var outcome: String = ""
        /// "hit it 250" / "drove it about 280 yards" — how far the shot went.
        var distanceYards: Double?
        /// Break direction on/around the green: "left to right", "right to left".
        var breakDirection: String = ""
        /// Spoken detail that didn't map to a field (feel, wind, misc color).
        var note: String
        var observations: ShotObservations = .init()
        var sourceQuote: String? = nil
    }

    var shots: [ParsedShot]
    /// Total putts mentioned (e.g. "two putts", "missed then made").
    var puttsMentioned: Int?
    /// "for a par / birdie / bogey" when the golfer called the hole.
    var scoreCall: String?
    /// Hole-level leftovers for later analysis.
    var leftoverNote: String
    var confidence: Double // 0...1
    var warnings: [String]

    var isEmpty: Bool { shots.isEmpty && puttsMentioned == nil && scoreCall == nil && leftoverNote.isEmpty }
}

/// Rule-based, on-device parser. No network, deterministic, simulator-safe.
/// Speech transcription feeds it; a typed fallback works identically.
enum HoleDictationParser {
    static let examplePrompt =
        "Hit a driver off the tee, slightly toed it, so missed left, then hit a four iron, chunked it, hit sand wedge, good contact, put it to about 10 feet, putt, missed on the high side for a par."

    static func parse(_ transcript: String) -> HoleDictationResult {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return HoleDictationResult(shots: [], puttsMentioned: nil, scoreCall: nil,
                                       leftoverNote: "", confidence: 0,
                                       warnings: ["Nothing to parse yet."])
        }
        let lower = normalize(text)
        var warnings: [String] = []

        let clauses = splitByClubs(lower)
        var shots: [HoleDictationResult.ParsedShot] = []
        var putts: Int?
        var leftoverBits: [String] = []

        for clause in clauses {
            if isMostlyPutt(clause) {
                // A score-first total isn't the first shot in the narrated trail.
                // The store appends these counted putts after the full swings.
                if clause.range(of: #"\bwith\s+(?:zero|one|two|three|four|\d+)[ -]putts?\b"#, options: .regularExpression) != nil,
                   let count = parsePutts(clause) {
                    putts = count
                    leftoverBits.append(clause)
                    continue
                }
                let n = max(1, countPuttMentions(clause))
                if let existing = parsePutts(clause) {
                    putts = (putts ?? 0) + max(existing, n)
                } else {
                    putts = (putts ?? 0) + n
                }
                let note = leftover(in: clause, club: .putter, contact: parseContact(clause),
                                    shape: parseShape(clause), quality: parseQuality(clause),
                                    lie: parseLie(clause), leftFeet: parseLeftDistance(clause))
                if GolfClub.match(in: clause) == .putter || n > 0 {
                    shots.append(.init(
                        club: .putter, lie: .green, contact: parseContact(clause),
                        shape: parseShape(clause), quality: parseQuality(clause) ?? (clause.contains("miss") ? .poor : nil),
                        leftFeet: parseLeftDistance(clause), putts: n,
                        outcome: parseOutcome(clause), breakDirection: parseBreak(clause), note: note, observations: parseObservations(clause)
                    ))
                }
                continue
            }

            let club = GolfClub.match(in: clause)
            let contact = parseContact(clause)
            let shape = parseShape(clause)
            let quality = parseQuality(clause)
            let lie = parseLie(clause)
            let leftFeet = parseLeftDistance(clause)
            let outcome = parseOutcome(clause)
            let distanceYards = parseShotDistance(clause)
            let breakDirection = parseBreak(clause)
            if club == nil && contact == nil && shape == nil && quality == nil && leftFeet == nil && lie == nil
                && outcome.isEmpty && distanceYards == nil && breakDirection.isEmpty {
                let extra = tidy(clause)
                if !extra.isEmpty { leftoverBits.append(extra) }
                continue
            }
            let note = leftover(in: clause, club: club, contact: contact, shape: shape,
                                quality: quality, lie: lie, leftFeet: leftFeet)
            let parsed = HoleDictationResult.ParsedShot(
                club: club, lie: lie, contact: contact, shape: shape,
                quality: quality, leftFeet: leftFeet, putts: nil,
                outcome: outcome, distanceYards: distanceYards,
                breakDirection: breakDirection, note: note, observations: parseObservations(clause)
            )
            if parsed.club == nil, var last = shots.last {
                last.observations.merge(parsed.observations)
                if last.contact == nil { last.contact = parsed.contact }
                if last.shape == nil { last.shape = parsed.shape }
                if last.quality == nil { last.quality = parsed.quality }
                if last.lie == nil { last.lie = parsed.lie }
                if last.leftFeet == nil { last.leftFeet = parsed.leftFeet }
                if last.outcome.isEmpty { last.outcome = parsed.outcome }
                if last.distanceYards == nil { last.distanceYards = parsed.distanceYards }
                if last.breakDirection.isEmpty { last.breakDirection = parsed.breakDirection }
                if last.note.isEmpty { last.note = parsed.note }
                else if !parsed.note.isEmpty { last.note += "; " + parsed.note }
                shots[shots.count - 1] = last
            } else {
                shots.append(parsed)
            }
        }

        if putts == nil { putts = parsePutts(lower) }
        let putterShots = shots.filter { $0.club == .putter }.count
        if let putts, putts > putterShots {
            // Keep structured putt shots; extra count is recorded on the result.
        } else if putterShots > 0, putts == nil {
            putts = putterShots
        }

        let scoreCall = parseScoreCall(lower)
        if shots.isEmpty && putts == nil {
            warnings.append("Couldn't pick out clubs or putts — tap a shot to add it manually.")
        }
        if shots.contains(where: { $0.club == nil }) {
            warnings.append("One shot has no club — pick it before saving.")
        }

        var noteBits = leftoverBits
        for shot in shots where !shot.note.isEmpty { noteBits.append(shot.note) }
        noteBits.append(contentsOf: analysisKeepers(in: lower))
        let leftoverNote = uniqueBits(noteBits)
        let clubbed = Double(shots.filter { $0.club != nil }.count)
        let detailed = Double(shots.filter { $0.shape != nil || $0.contact != nil || !$0.note.isEmpty }.count)
        let puttBonus = putts != nil ? 0.15 : 0.0
        let confidence = min(1.0, 0.35 + 0.15 * clubbed + 0.1 * detailed + puttBonus)
        return HoleDictationResult(shots: shots, puttsMentioned: putts, scoreCall: scoreCall,
                                   leftoverNote: leftoverNote, confidence: confidence, warnings: warnings)
    }

    // MARK: - Normalize / split

    static func normalize(_ text: String) -> String {
        var t = " " + text.lowercased() + " "
        let replacements = [
            "towed": "toed", " tow ": " toed ", "toey": "toed",
            "4-iron": "four iron", "4 iron": "four iron", "4i": "four iron",
            "7-iron": "seven iron", "3-wood": "3 wood",
            "sandwedge": "sand wedge", "pw ": "pitching wedge ",
            "chunked it": "chunked", "duffed it": "chunked",
            "good contact": "pure contact", "flush": "pure",
            "left-to-right": "left to right",
        ]
        for (a, b) in replacements {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split on club mentions so "hit driver … then four iron … sand wedge" is 3 shots.
    static func splitByClubs(_ text: String) -> [String] {
        let clubs = [
            "driver", "3 wood", "5 wood", "hybrid",
            "three iron", "four iron", "five iron", "six iron", "seven iron", "eight iron", "nine iron",
            "3 iron", "4 iron", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron",
            "3i", "4i", "5i", "6i", "7i", "8i", "9i",
            "pitching wedge", "gap wedge", "sand wedge", "lob wedge",
            "putter",
        ]
        var work = text
        for sep in [" and then ", " then ", ". ", "!", "? ", "; "] {
            work = work.replacingOccurrences(of: sep, with: " · ")
        }
        // Also split before "hit a <club>" / "hit <club>".
        if let regex = try? NSRegularExpression(pattern: #"\b(?:hit|then hit|then)\s+(?:a\s+|an\s+)?(?=(?:driver|putter|(?:[a-z]+|[0-9]) (?:iron|wood|wedge)|hybrid)\b)"#) {
            work = regex.stringByReplacingMatches(in: work, range: NSRange(work.startIndex..., in: work), withTemplate: " · ")
        }

        var parts = work.split(separator: "·").map { tidy(String($0)) }.filter { !$0.isEmpty }
        if parts.count <= 1 {
            parts = splitClauses(text)
        }

        // Merge a clubless fragment into the previous club-bearing clause.
        var merged: [String] = []
        for part in parts {
            if GolfClub.match(in: part) == nil, let last = merged.last,
               GolfClub.match(in: last) != nil, !isMostlyPutt(part) {
                merged[merged.count - 1] = last + " " + part
            } else {
                merged.append(part)
            }
        }

        // If a single blob contains multiple clubs, cut on each club name.
        var exploded: [String] = []
        for part in merged {
            let cuts = cutOnClubNames(part, clubs: clubs)
            exploded.append(contentsOf: cuts)
        }
        var peeled: [String] = []
        for part in exploded {
            peeled.append(contentsOf: peelPutting(part))
        }
        if peeled.count > 10 {
            peeled = Array(peeled.prefix(10))
        }
        return peeled.filter { !$0.isEmpty }
    }

    /// "sand wedge … to 10 feet, putt, miss high side" → approach + putting.
    static func peelPutting(_ part: String) -> [String] {
        let t = part
        guard GolfClub.match(in: t) != nil, GolfClub.match(in: t)?.isPutter != true else {
            return [tidy(t)].filter { !$0.isEmpty }
        }
        let needles = [", putt", " putt,", " putts ", " putted ", " then putt", " and putt"]
        var best: String.Index?
        let lower = t.lowercased()
        for needle in needles {
            if let r = lower.range(of: needle), best == nil || r.lowerBound < best! {
                best = r.lowerBound
            }
        }
        if best == nil, let r = lower.range(of: " putt") {
            let prefix = String(lower[..<r.lowerBound])
            if !prefix.hasSuffix("put") { best = r.lowerBound }
        }
        guard let idx = best else { return [tidy(t)].filter { !$0.isEmpty } }
        let offset = lower.distance(from: lower.startIndex, to: idx)
        let split = t.index(t.startIndex, offsetBy: offset)
        let before = tidy(String(t[..<split]))
        let after = tidy(String(t[split...]))
        return [before, after].filter { !$0.isEmpty }
    }

    static func cutOnClubNames(_ text: String, clubs: [String]) -> [String] {
        let t = text.lowercased()
        var marks: [(Int, String)] = []
        for club in clubs {
            var search = t.startIndex
            while let r = t.range(of: club, range: search..<t.endIndex) {
                marks.append((t.distance(from: t.startIndex, to: r.lowerBound), club))
                search = r.upperBound
            }
        }
        marks.sort { $0.0 < $1.0 }
        // Drop overlapping shorter hits (e.g. "iron" inside "four iron" is not a club here).
        var starts: [Int] = []
        var lastEnd = -1
        for (idx, club) in marks {
            if idx < lastEnd { continue }
            starts.append(idx)
            lastEnd = idx + club.count
        }
        guard starts.count >= 2 else { return [tidy(text)] }
        var out: [String] = []
        for i in 0..<starts.count {
            let a = t.index(t.startIndex, offsetBy: starts[i])
            let b = i + 1 < starts.count
                ? t.index(t.startIndex, offsetBy: starts[i + 1])
                : t.endIndex
            out.append(tidy(String(t[a..<b])))
        }
        return out.filter { !$0.isEmpty }
    }

    static func splitClauses(_ text: String) -> [String] {
        var work = text
        let separators = [" and then ", " then ", ". ", "!", "? ", "; ",
                          " next ", " after that ", " approach ", " my second ",
                          " my third ", " tee shot "]
        for sep in separators {
            work = work.replacingOccurrences(of: sep, with: "\n")
        }
        return work.split(separator: "\n")
            .map { tidy(String($0)) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Attributes

    static func parseLie(_ clause: String) -> Lie? {
        if clause.contains("off the tee") || clause.contains("from the tee") { return .tee }
        for (words, lie) in [("fairway", Lie.fairway), ("rough", .rough), ("bunker", .sand), ("sand", .sand), ("fringe", .fringe), ("green", .green), ("trees", .recovery)] {
            if clause.contains("from the " + words) || clause.contains("out of the " + words) { return lie }
        }
        return nil
    }

    static func parseObservations(_ clause: String) -> ShotObservations {
        let t = clause.lowercased()
        func has(_ pattern: String) -> Bool { t.range(of: pattern, options: .regularExpression) != nil }
        func number(_ pattern: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let r = Range(m.range(at: 1), in: t) else { return nil }
            return Double(t[r])
        }
        var result = ShotObservations()
        for finish in ShotFinish.allCases where finish != .holed {
            let word = finish == .bunker ? "(?:bunker|sand)" : finish.rawValue
            if has("(?:finished|landed|ended up|rolled|into|onto|found|hit|in) (?:in |on |the |a )*" + word + "\\b") {
                result.finish = finish
            }
        }
        if has(#"\b(?:went|hit it|finished) (?:ob|out of bounds)\b"#) { result.finish = .outOfBounds }
        if has(#"\b(?:missed|miss|finished|left it) (?:it |the green |the fairway )?(?:short and |long and )?left\b|\bleft of (?:the )?(?:pin|hole|target|green|fairway)\b"#) { result.lateralMiss = .left }
        if has(#"\b(?:missed|miss|finished|left it) (?:it |the green |the fairway )?(?:short and |long and )?right\b|\bright of (?:the )?(?:pin|hole|target|green|fairway)\b"#) { result.lateralMiss = .right }
        if has(#"\b(?:short of|came up short|left it short|missed short|finished short|missed (?:left|right) and short)\b"#) { result.depthMiss = .short }
        if has(#"\b(?:went long|finished long|missed long|over the green|flew the green|missed (?:left|right) and long)\b"#) { result.depthMiss = .long }
        let isPutt = isMostlyPutt(t) || GolfClub.match(in: t) == .putter
        if isPutt {
            result.puttBreak = PuttBreak(rawValue: parseBreak(t))
            if has(#"\b(?:straight putt|no break|didn't break)\b"#) { result.puttBreak = .straight }
            if has(#"\b(?:high side|missed high)\b"#) { result.puttMissSide = .high }
            if has(#"\b(?:low side|missed low)\b"#) { result.puttMissSide = .low }
            if has(#"\b(?:missed|miss|left it short|came up short)\b"#) { result.holed = false }
        }
        if has(#"\b(?:holed it|sank it|made the putt|drained it)\b"#) && !has(#"\b(?:not|never|nearly|almost) (?:holed|sank|made|drained)\b"#) {
            result.holed = true; result.finish = .holed
        }
        result.carryYards = number(#"\b(?:carried|carry of) (?:it |about )?(\d+(?:\.\d+)?) (?:yards?|yds?)\b"#)
        result.startingDistanceFeet = number(#"\bfrom (\d+(?:\.\d+)?) (?:feet|foot|ft)\b"#)
        if let yards = number(#"\bfrom (\d+(?:\.\d+)?) (?:yards?|yds?)\b"#) { result.startingDistanceFeet = yards * 3 }
        return result
    }

    static func parseContact(_ clause: String) -> Contact? {
        let t = " \(clause) "
        if t.contains(" toed ") || t.contains(" off the toe ") || t.contains(" out of the toe ")
            || t.contains(" toey ") { return .toe }
        if t.contains(" hosel ") || t.contains(" shank ") { return .shank }
        if t.contains(" heel ") { return .heel }
        if t.contains(" thin ") || t.contains(" bladed ") || t.contains(" skull") { return .thin }
        if t.contains(" fat ") || t.contains(" chunk") || t.contains(" heavy ") || t.contains(" behind it ") { return .fat }
        if t.contains(" top") || t.contains(" topped ") { return .top }
        if t.contains(" pure ") || t.contains(" pured ") || t.contains(" centered ")
            || t.contains(" middle of the face ") || t.contains(" flushed ")
            || t.contains(" good contact ") || t.contains(" pure contact ") { return .pure }
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

    /// Miss/result outcome: "missed left", "missed right", "short", "long",
    /// "fairway", "green", "bunker", "water", "out of bounds", "holed".
    static func parseOutcome(_ clause: String) -> String {
        let t = " \(clause.lowercased()) "
        if t.contains(" out of bounds ") || t.contains(" ob ") { return "out of bounds" }
        if t.contains(" in the water ") || t.contains(" into the water ") || t.contains(" water hazard ") { return "water" }
        if t.contains(" holed ") || t.contains(" holed it ") || t.contains(" sank it ")
            || t.contains(" made the putt ") || t.contains(" drained it ") { return "holed" }
        if t.contains(" missed left ") || t.contains(" miss left ") || t.contains(" left of ")
            || t.contains(" pulled it ") { return "missed left" }
        if t.contains(" missed right ") || t.contains(" miss right ") || t.contains(" right of ")
            || t.contains(" pushed it ") { return "missed right" }
        if t.contains(" came up short ") || t.contains(" left it short ") || t.contains(" short of ")
            || t.contains(" short sided ") || t.contains(" short side ") { return "short" }
        if t.contains(" went long ") || t.contains(" long of ") || t.contains(" through the green ")
            || t.contains(" over the green ") || t.contains(" flew the green ") { return "long" }
        if t.contains(" in the bunker ") || t.contains(" in a bunker ") || t.contains(" greenside bunker ")
            || t.contains(" plugged ") { return "bunker" }
        if t.contains(" on the green ") || t.contains(" onto the green ") || t.contains(" hit the green ") { return "green" }
        if t.contains(" fairway ") || t.contains(" down the middle ") { return "fairway" }
        return ""
    }

    /// Break direction: "left to right" / "right to left".
    static func parseBreak(_ clause: String) -> String {
        let t = " \(clause.lowercased()) "
        if t.contains(" left to right ") { return "left to right" }
        if t.contains(" right to left ") { return "right to left" }
        return ""
    }

    /// "hit it 250" / "drove it about 280 yards" / "carried 240" — shot distance.
    static func parseShotDistance(_ clause: String) -> Double? {
        let t = clause.lowercased()
        let pattern = #"(?:hit|drove|carried|went|flew|striped)\s+(?:it\s+)?(?:about\s+|roughly\s+|around\s+)?(\d+)\s*(yards?|yds?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 1), in: t),
              let value = Double(t[r])
        else { return nil }
        return value
    }

    static func parseQuality(_ clause: String) -> ShotQuality? {
        let t = " \(clause) "
        if t.contains(" great ") || t.contains(" excellent ") || t.contains(" perfect ")
            || t.contains(" striped ") || t.contains(" money ") { return .great }
        if t.contains(" good ") || t.contains(" nice ") || t.contains(" solid ")
            || t.contains(" decent ") { return .good }
        if t.contains(" miss") || t.contains(" poor ") || t.contains(" bad ") || t.contains(" terrible ")
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
        let pattern = #"(?:to(?:\s+about)?|leaving)\s+(\d+|[a-z]+)\s*(feet|foot|ft|yards?|yds?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let numRange = Range(m.range(at: 1), in: t),
           let unitRange = Range(m.range(at: 2), in: t) {
            let numStr = String(t[numRange])
            let unit = String(t[unitRange])
            let value = Double(numStr) ?? numbers[numStr]
            if let value {
                return unit.hasPrefix("y") ? value * 3 : value
            }
        }
        return nil
    }

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
        return nil
    }

    static func parseScoreCall(_ text: String) -> String? {
        // Last stated result wins (e.g. “missed for birdie, made par”).
        // Course descriptions and putt intentions alone aren't card scores.
        let pattern = #"\b(albatross|eagle|birdie|double(?: bogey)?|triple(?: bogey)?|bogey|par)\b(?![ -]+(?:three|four|five|3|4|5|putt|chance|opportunity)\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return ns.substring(with: match.range(at: 1)).lowercased().replacingOccurrences(of: " bogey", with: "")
    }

    static func isMostlyPutt(_ clause: String) -> Bool {
        let t = " \(clause) "
        return t.contains(" putt") && GolfClub.match(in: clause).map(\.isPutter) != false
            && !t.contains(" iron ") && !t.contains(" wedge ") && !t.contains(" driver ")
    }

    static func countPuttMentions(_ clause: String) -> Int {
        let t = clause.lowercased()
        var n = 0
        if t.contains("miss") { n += 1 }
        if t.contains("made") || t.contains("sank") || t.contains("holed") { n += 1 }
        if n == 0 { n = 1 }
        return n
    }

    /// Strip structured phrases; keep the rest as a note for later analysis.
    static func leftover(in clause: String, club: GolfClub?, contact: Contact?,
                         shape: ShotShape?, quality: ShotQuality?, lie: Lie?,
                         leftFeet: Double?) -> String {
        var t = " \(clause.lowercased()) "
        let drop = [
            "hit a", "hit an", "hit", "then", "so", "and", "off the tee", "from the tee",
            "slightly", "it", "a", "the", "my", "i", "to about", "about", "roughly", "around",
            "put it", "putted", "putt", "putts", "contact", "pure contact",
            "four iron", "three iron", "five iron", "six iron", "seven iron", "eight iron", "nine iron",
            "driver", "sand wedge", "gap wedge", "lob wedge", "pitching wedge", "putter",
            "3 wood", "5 wood", "hybrid", "toed", "towed", "chunked", "chunk",
            "missed left", "missed right", "miss left", "miss right", "missed", "miss",
            "good", "nice", "solid", "poor", "bad", "great", "on the",
            "feet", "foot", "ft", "yards", "yard", "yds",
            "for a par", "for par", "for a birdie", "for birdie", "for a bogey",
            "left to right", "right to left",
            "out of bounds", "in the water", "into the water", "water hazard", "holed it", "sank it",
            "came up short", "left it short", "short of", "short sided", "short side", "went long",
            "in the bunker", "in a bunker", "down the middle", "onto the green",
            "drove", "carried", "striped", "flew", "drained it", "made the putt",
        ]
        for phrase in drop {
            t = t.replacingOccurrences(of: " \(phrase) ", with: " ")
        }
        if leftFeet != nil {
            t = t.replacingOccurrences(of: #"\d+"#, with: " ", options: .regularExpression)
        }
        let cleaned = tidy(t)
        // Keep directional / miss-location color that we didn't structure.
        let keepers = ["high side", "low side", "left or right", "short sided",
                       "short side", "plugged", "flyer"]
        let kept = keepers.filter { clause.lowercased().contains($0) }
        if kept.isEmpty { return cleaned }
        let extra = kept.joined(separator: ", ")
        if cleaned.isEmpty { return extra }
        if keepers.contains(where: { cleaned.contains($0) }) { return cleaned }
        return extra + (cleaned.isEmpty ? "" : " · " + cleaned)
    }

    static func analysisKeepers(in text: String) -> [String] {
        let phrases = [
            "high side", "low side", "left or right", "right or left",
            "short sided", "short side", "above the hole", "below the hole",
            "plugged", "flyer", "into the wind", "downwind", "hung it out",
            "blocked out", "came up short",
        ]
        return phrases.filter { text.contains($0) }
    }

    static func tidy(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.·"))
        s = s.replacingOccurrences(of: ",", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func uniqueBits(_ bits: [String]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for bit in bits {
            let t = tidy(bit)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        return out.joined(separator: " · ")
    }
}
