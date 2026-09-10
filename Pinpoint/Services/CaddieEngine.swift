import Foundation

/// Plays-like + club recommendation engine.
/// Adjusts raw yardage for wind and elevation, then picks the smallest
/// club whose effective distance covers the shot.
enum CaddieEngine {
    /// Wind-adjusted yardage. `windHelping`: +1 full tailwind, -1 full headwind,
    /// 0 crosswind. Elevation positive = uphill.
    static func playsLike(
        yards: Double,
        windMph: Double,
        windHelping: Double,
        elevationFeet: Double = 0
    ) -> Double {
        let windEffect = -windHelping * windMph * 1.1
        let elevationEffect = elevationFeet * 1.0
        return max(0, yards + windEffect + elevationEffect)
    }

    /// Picks the shortest club that covers `playsLikeYards`.
    /// - Parameters:
    ///   - averages: personal per-club averages (yards). Missing clubs fall back to stock.
    ///   - maxSwing: 1.0 = full stock swing; scales all distances (e.g. 0.9 for smooth).
    static func recommendClub(
        for playsLikeYards: Double,
        averages: [GolfClub: Double],
        maxSwing: Double = 1.0
    ) -> (club: GolfClub, swingEffort: Double)? {
        guard playsLikeYards > 12 else { return nil } // putting territory
        let bag: [GolfClub] = [.lobWedge, .sandWedge, .gapWedge, .pitchingWedge,
                               .iron9, .iron8, .iron7, .iron6, .iron5,
                               .iron4, .hybrid, .wood5, .wood3, .driver]
        for club in bag {
            let dist = (averages[club] ?? club.stockYards) * maxSwing
            if dist >= playsLikeYards {
                return (club, min(1.0, playsLikeYards / max(dist, 1)))
            }
        }
        return (.driver, 1.0)
    }

    /// Human-readable caddie line, e.g. "226 plays like 217 — smooth 5i".
    static func adviceLine(
        yards: Double,
        playsLike: Double,
        recommendation: (club: GolfClub, swingEffort: Double)?
    ) -> String {
        guard let rec = recommendation else { return "Putter time — read it well." }
        let effort: String
        switch rec.swingEffort {
        case ..<0.62: effort = "easy"
        case ..<0.82: effort = "smooth"
        case ..<0.95: effort = "stock"
        default: effort = "full"
        }
        if abs(playsLike - yards) < 3 {
            return "\(Int(yards)) — \(effort) \(rec.club.shortName)"
        }
        return "\(Int(yards)) plays like \(Int(playsLike)) — \(effort) \(rec.club.shortName)"
    }

    // MARK: - Green reading

    struct GreenRead: Equatable {
        /// Compass-ish description of the dominant break, e.g. "left-to-right".
        var breakDirection: String
        /// 0 (flat) ... 3 (severe).
        var severity: Int
        var paceAdvice: String
        var summary: String
    }

    /// Placeholder green read: deterministic per hole number + pin position so
    /// the same hole reads the same way every visit, but the break is a
    /// heuristic estimate — not measured from green scans. The UI presents it
    /// as an estimate, never as AI analysis.
    static func readGreen(holeNumber: Int, pinX: Double, pinY: Double, puttFeet: Double?) -> GreenRead {
        var seed = UInt64(holeNumber &* 2_654_435_761 &+ 0x9E3779B9)
        func next() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 1000) / 1000.0
        }
        let slope = next() // 0 flat ... 1 severe
        let tilt = next() * 360
        let severity = slope < 0.25 ? 0 : slope < 0.5 ? 1 : slope < 0.78 ? 2 : 3

        // Break direction relative to a putt coming from below the pin.
        let dir: String
        switch tilt {
        case 0..<45: dir = "right-to-left"
        case 45..<135: dir = "straight uphill"
        case 135..<225: dir = "left-to-right"
        case 225..<315: dir = "straight downhill"
        default: dir = "right-to-left"
        }

        let pace: String
        switch severity {
        case 0: pace = "Flat — be aggressive at the hole."
        case 1: pace = "Gentle slope — firm pace, take the break out."
        case 2: pace = "Two-putt pace — borrow a cup outside."
        default: pace = "Lag it — dying pace, big borrow."
        }

        let pinSide = pinX < 0.33 ? "left" : pinX > 0.66 ? "right" : "middle"
        let depth = pinY > 0.66 ? "back" : pinY < 0.33 ? "front" : "middle"
        var summary = "Pin is \(depth)-\(pinSide). "
        if severity == 0 {
            summary += "Green is fairly flat here. "
        } else {
            summary += "Reads \(dir). "
        }
        summary += pace
        if let feet = puttFeet {
            summary += " (\(Int(feet)) ft)."
        }
        return GreenRead(breakDirection: dir, severity: severity, paceAdvice: pace, summary: summary)
    }
}
