import Foundation

/// A reviewable batch. Explicit hole boundaries keep multi-hole narration separate.
struct RecapDraft: Identifiable {
    var id = UUID()
    var holeNumber: Int
    var transcript: String
    var result: HoleDictationResult
    var score: Int?
    var putts: Int?
    var penalties: Int?
    var fairway: Bool?
    var selected = true
}

enum RoundRecapParser {
    static let numbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen"]

    static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth"]

    static func number(_ text: String) -> Int? {
        Int(text) ?? numbers.firstIndex(of: text.lowercased()) ?? ordinals.firstIndex(of: text.lowercased()).map { $0 + 1 }
    }

    static func segments(_ text: String, currentHole: Int) -> [(Int, String)] {
        let pattern = #"\bhole\s*(?:number\s*)?(\d{1,2}|eighteen|seventeen|sixteen|fifteen|fourteen|thirteen|twelve|eleven|ten|nine|eight|seven|six|five|four|three|two|one)\b|\bnext hole\b"#
        let ordinalPattern = ordinals.joined(separator: "|")
        let combined = pattern + "|\\b(" + ordinalPattern + ")\\s+hole\\b|\\bon the (" + ordinalPattern + ")\\b"
        let regex = try! NSRegularExpression(pattern: combined, options: .caseInsensitive)
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [(currentHole, text)] }
        var output: [(Int, String)] = []
        let prefix = ns.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        var hole = currentHole
        if !prefix.isEmpty { output.append((hole, prefix)) }
        for (index, match) in matches.enumerated() {
            if match.range(at: 1).location != NSNotFound {
                hole = number(ns.substring(with: match.range(at: 1)).lowercased()) ?? currentHole
            } else if match.range(at: 2).location != NSNotFound {
                hole = number(ns.substring(with: match.range(at: 2))) ?? currentHole
            } else if match.range(at: 3).location != NSNotFound {
                hole = number(ns.substring(with: match.range(at: 3))) ?? currentHole
            } else { hole += 1 }
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: start, length: end - start))
            output.append((hole, body))
        }
        // Merge repeated references to the same hole in spoken corrections.
        var merged: [(Int, String)] = []
        for (hole, body) in output {
            if let i = merged.firstIndex(where: { $0.0 == hole }) {
                merged[i].1 += ". " + body
            } else { merged.append((hole, body)) }
        }
        return merged
    }

    static func aiDrafts(_ text: String, round: GolfRound, currentHole: Int) async throws -> [RecapDraft] {
        let response = try await OpenAIGolfService.roundRecap(text, round: round, currentHole: currentHole)
        return try HoleRecapLLM.drafts(response, transcript: text, round: round)
    }

    /// Optional offline path, used only when the golfer explicitly selects it.
    static func localDrafts(_ text: String, round: GolfRound, currentHole: Int) -> [RecapDraft] {
        var drafts: [RecapDraft] = []
        for (number, text) in segments(text, currentHole: currentHole) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let result = HoleDictationParser.parse(text)
            let lower = text.lowercased()
            let explicit = captureNumber(#"\b(?:scored|score(?: was| of)?|made a|took a|got a|had a|shot a|it was a|finished with a)\s+(\d{1,2}|[a-z]+)\b"#, in: lower)
            let score = explicit ?? (HoleDictationParser.parseScoreCall(lower) ?? result.scoreCall).flatMap { call in
                round.hole(number).flatMap { HoleScore.score(fromCall: call, par: $0.par) }
            }
            let putts = captureNumber(#"\b(\d{1,2}|[a-z]+)[ -]putts?\b"#, in: lower) ?? result.puttsMentioned
            let penalties = captureNumber(#"\b(\d{1,2}|[a-z]+)\s+penalt(?:y|ies)(?: strokes?)?\b"#, in: lower)
            let fairway: Bool? = lower.contains("missed the fairway") || lower.contains("missed fairway") ? false :
                (lower.contains("hit the fairway") || lower.contains("hit fairway") || lower.contains("found the fairway") ? true : nil)
            drafts.append(RecapDraft(holeNumber: number, transcript: text, result: result,
                                     score: score, putts: putts, penalties: penalties, fairway: fairway,
                                     selected: round.score(for: number) != nil))
        }
        return drafts
    }

    static func captureNumber(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed().compactMap {
            number(ns.substring(with: $0.range(at: 1)))
        }.first
    }
}
