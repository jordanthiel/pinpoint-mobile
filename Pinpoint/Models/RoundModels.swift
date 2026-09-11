import Foundation

// MARK: - Clubs

enum GolfClub: String, Codable, CaseIterable, Identifiable, Hashable {
    case driver
    case wood3, wood5
    case hybrid
    case iron3, iron4, iron5, iron6, iron7, iron8, iron9
    case pitchingWedge, gapWedge, sandWedge, lobWedge
    case putter

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .driver: return "Dr"
        case .wood3: return "3W"
        case .wood5: return "5W"
        case .hybrid: return "Hy"
        case .iron3: return "3i"
        case .iron4: return "4i"
        case .iron5: return "5i"
        case .iron6: return "6i"
        case .iron7: return "7i"
        case .iron8: return "8i"
        case .iron9: return "9i"
        case .pitchingWedge: return "PW"
        case .gapWedge: return "GW"
        case .sandWedge: return "SW"
        case .lobWedge: return "LW"
        case .putter: return "Pt"
        }
    }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .wood3: return "3 Wood"
        case .wood5: return "5 Wood"
        case .hybrid: return "Hybrid"
        case .iron3: return "3 Iron"
        case .iron4: return "4 Iron"
        case .iron5: return "5 Iron"
        case .iron6: return "6 Iron"
        case .iron7: return "7 Iron"
        case .iron8: return "8 Iron"
        case .iron9: return "9 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .gapWedge: return "Gap Wedge"
        case .sandWedge: return "Sand Wedge"
        case .lobWedge: return "Lob Wedge"
        case .putter: return "Putter"
        }
    }

    var isPutter: Bool { self == .putter }

    /// Stock carry distances (yards) used until the golfer builds personal averages.
    var stockYards: Double {
        switch self {
        case .driver: return 260
        case .wood3: return 235
        case .wood5: return 220
        case .hybrid: return 205
        case .iron3: return 195
        case .iron4: return 185
        case .iron5: return 175
        case .iron6: return 165
        case .iron7: return 155
        case .iron8: return 142
        case .iron9: return 130
        case .pitchingWedge: return 118
        case .gapWedge: return 105
        case .sandWedge: return 92
        case .lobWedge: return 78
        case .putter: return 0
        }
    }

    /// Matches phrases like "seven iron", "7i", "sand wedge", "SW", "driver", "putter".
    static func match(in text: String) -> GolfClub? {
        let squashed = text.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        let t = " \(squashed) "
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        // Clubs first. "putt" is last so "sand wedge … putt" stays a wedge.
        if has(" driver ", " dr ") { return .driver }
        if has(" 3 wood ", " 3w ", " three wood ") { return .wood3 }
        if has(" 5 wood ", " 5w ", " five wood ") { return .wood5 }
        if has(" hybrid ", " rescue ", " utility ") { return .hybrid }
        if has(" lob wedge ", " lw ", " lob ") { return .lobWedge }
        if has(" sand wedge ", " sw ", " sand iron ") { return .sandWedge }
        if has(" gap wedge ", " gw ", " approach wedge ") { return .gapWedge }
        if has(" pitching wedge ", " pw ", " pitch ") { return .pitchingWedge }
        let irons: [(String, GolfClub)] = [
            ("3", .iron3), ("4", .iron4), ("5", .iron5), ("6", .iron6),
            ("7", .iron7), ("8", .iron8), ("9", .iron9),
        ]
        let names = ["three": "3", "four": "4", "five": "5", "six": "6",
                     "seven": "7", "eight": "8", "nine": "9"]
        for (digit, club) in irons {
            if t.contains(" \(digit) iron ") || t.contains(" \(digit)i ")
                || t.contains(" \(digit)-iron ") { return club }
        }
        for (word, digit) in names {
            if t.contains(" \(word) iron ") || t.contains(" \(word)-iron ") {
                return irons.first { $0.0 == digit }?.1
            }
        }
        if has(" nine iron ", " 9 iron ") { return .iron9 }
        if has(" putter ", " putts ", " putt ", " pt ") { return .putter }
        return nil
    }
}

// MARK: - Lie / contact / shape

enum Lie: String, Codable, CaseIterable, Identifiable, Hashable {
    case tee, fairway, rough, sand, recovery, fringe, green

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tee: return "Tee"
        case .fairway: return "Fairway"
        case .rough: return "Rough"
        case .sand: return "Sand"
        case .recovery: return "Recovery"
        case .fringe: return "Fringe"
        case .green: return "Green"
        }
    }

    var code: String {
        switch self {
        case .tee: return "T"
        case .fairway: return "F"
        case .rough: return "R"
        case .sand: return "S"
        case .recovery: return "RC"
        case .fringe: return "FR"
        case .green: return "G"
        }
    }

    var systemImage: String {
        switch self {
        case .tee: return "flag"
        case .fairway: return "align.horizontal.center"
        case .rough: return "leaf"
        case .sand: return "circle.dotted"
        case .recovery: return "arrow.uturn.left"
        case .fringe: return "circle.dashed"
        case .green: return "circle.fill"
        }
    }
}

enum Contact: String, Codable, CaseIterable, Identifiable, Hashable {
    case pure, toe, heel, thin, fat, top, shank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pure: return "Centered"
        case .toe: return "Toe"
        case .heel: return "Heel"
        case .thin: return "Thin"
        case .fat: return "Heavy"
        case .top: return "Topped"
        case .shank: return "Shank"
        }
    }
}

enum ShotShape: String, Codable, CaseIterable, Identifiable, Hashable {
    case straight, draw, fade, pull, push, slice, hook

    var id: String { rawValue }

    var label: String {
        switch self {
        case .straight: return "Straight"
        case .draw: return "Draw"
        case .fade: return "Fade"
        case .pull: return "Pull"
        case .push: return "Push"
        case .slice: return "Slice"
        case .hook: return "Hook"
        }
    }
}

enum ShotQuality: String, Codable, CaseIterable, Identifiable, Hashable {
    case great, good, ok, poor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .great: return "Great"
        case .good: return "Good"
        case .ok: return "OK"
        case .poor: return "Poor"
        }
    }
}

enum ShotSource: String, Codable, Hashable {
    case manual
    case watch
    case dictation
    case imported

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .watch: return "Watch"
        case .dictation: return "Dictated"
        case .imported: return "Imported"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: return "hand.tap"
        case .watch: return "applewatch"
        case .dictation: return "mic"
        case .imported: return "square.and.arrow.down"
        }
    }
}

// MARK: - Geo

struct GeoPoint: Codable, Hashable, Equatable {
    var latitude: Double
    var longitude: Double

    /// Haversine distance in yards.
    func yards(to other: GeoPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(a)) * 1.09361
    }
}

// MARK: - Shot

struct TrackedShot: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var number: Int
    var club: GolfClub?
    var lie: Lie
    var distanceToPinBeforeYards: Double?
    var carryYards: Double?
    var start: GeoPoint?
    var end: GeoPoint?
    var contact: Contact?
    var shape: ShotShape?
    var quality: ShotQuality?
    var includeInTrueDistance: Bool
    var source: ShotSource
    var timestamp: Date
    var note: String

    init(
        id: UUID = UUID(),
        number: Int,
        club: GolfClub? = nil,
        lie: Lie = .tee,
        distanceToPinBeforeYards: Double? = nil,
        carryYards: Double? = nil,
        start: GeoPoint? = nil,
        end: GeoPoint? = nil,
        contact: Contact? = nil,
        shape: ShotShape? = nil,
        quality: ShotQuality? = nil,
        includeInTrueDistance: Bool = true,
        source: ShotSource = .manual,
        timestamp: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.number = number
        self.club = club
        self.lie = lie
        self.distanceToPinBeforeYards = distanceToPinBeforeYards
        self.carryYards = carryYards
        self.start = start
        self.end = end
        self.contact = contact
        self.shape = shape
        self.quality = quality
        self.includeInTrueDistance = includeInTrueDistance && !(club?.isPutter ?? false)
        self.source = source
        self.timestamp = timestamp
        self.note = note
    }

    var isPutt: Bool { club?.isPutter ?? false }

    var summary: String {
        var bits: [String] = []
        if let club { bits.append(club.displayName) }
        bits.append("from \(lie.label)")
        if let carryYards { bits.append("\(Int(carryYards)) yds") }
        if let shape, shape != .straight { bits.append(shape.label.lowercased()) }
        if let contact, contact != .pure { bits.append("off the \(contact.label.lowercased())") }
        return bits.joined(separator: ", ").capitalized
    }
}

// MARK: - Hole / course

struct GolfHole: Codable, Hashable, Equatable {
    var number: Int // 1-based
    var par: Int
    var handicap: Int
    var yardage: Int
    /// -1 (dogleg left) ... +1 (dogleg right); used if a hole has no GPS layout.
    var dogleg: Double
    /// Real tee / green / corridor GPS when we have course survey data.
    var layout: HoleLayout?
}

struct CourseTee: Codable, Hashable, Equatable {
    var name: String
    var totalYardage: Int
    var rating: Double
    var slope: Int
}

struct GolfCourse: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var name: String
    var location: String
    var tees: [CourseTee]
    var holes: [GolfHole]
    var coordinate: GeoPoint?

    var totalPar: Int { holes.reduce(0) { $0 + $1.par } }

    func tee(named name: String) -> CourseTee? {
        tees.first { $0.name == name }
    }

    func layout(for holeNumber: Int) -> HoleLayout? {
        holes.first { $0.number == holeNumber }?.layout ?? GeorgetownGPS.layout(for: holeNumber)
    }
}

enum RoundType: String, Codable, CaseIterable, Identifiable {
    case eighteen, front9, back9

    var id: String { rawValue }

    var label: String {
        switch self {
        case .eighteen: return "18 Holes"
        case .front9: return "Front 9"
        case .back9: return "Back 9"
        }
    }
}

enum ScoringMode: String, Codable, CaseIterable, Identifiable {
    case classic, smart

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .smart: return "Smart Tracking"
        }
    }
}

enum RoundStatus: String, Codable {
    case active, finished
}

// MARK: - Hole score (live)

struct HoleScore: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var holeNumber: Int // 1-based course hole number
    var shots: [TrackedShot]
    var penaltyStrokes: Int
    var pinPosition: PinPosition
    var firstPuttFeet: Double?
    var dictateTranscript: String
    /// Leftover spoken detail that didn't fit a structured field — for later analysis.
    var analysisNote: String?
    var isComplete: Bool

    struct PinPosition: Codable, Hashable, Equatable {
        /// Normalized 0...1 position on the green (x right, y up). Used when
        /// a hole has no surveyed pin coordinate yet.
        var x: Double
        var y: Double
        /// Absolute pin when the golfer dropped it on the satellite green.
        var latitude: Double?
        var longitude: Double?

        var coordinate: GeoPoint? {
            guard let latitude, let longitude else { return nil }
            return GeoPoint(latitude: latitude, longitude: longitude)
        }
    }

    init(holeNumber: Int) {
        id = UUID()
        self.holeNumber = holeNumber
        shots = []
        penaltyStrokes = 0
        pinPosition = PinPosition(x: 0.5, y: 0.62)
        firstPuttFeet = nil
        dictateTranscript = ""
        analysisNote = ""
        isComplete = false
    }

    var grossScore: Int { shots.count + penaltyStrokes }
    var putts: Int { shots.filter(\.isPutt).count }
    var hasScore: Bool { !shots.isEmpty || penaltyStrokes > 0 }

    func scoreName(par: Int) -> String {
        guard hasScore else { return "–" }
        switch grossScore - par {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double"
        default: return "+\(grossScore - par)"
        }
    }

    func fairwayHit(par: Int) -> Bool? {
        guard par > 3, shots.count >= 2 else { return nil }
        let second = shots[1]
        return second.lie == .fairway || second.lie == .green
    }

    /// True when the ball reached the green (or fringe) within par-2 strokes,
    /// or was holed out in par-2 or fewer (ace, chip-in). Nil while the hole
    /// is still in progress and the outcome can't be judged yet.
    func greenInRegulation(par: Int) -> Bool? {
        guard !shots.isEmpty else { return nil }
        let target = max(1, par - 2)
        if shots.count > target {
            // The (target+1)-th shot exists: GIR iff it was played from the
            // green or fringe, meaning the ball arrived in regulation.
            let next = shots[target]
            return next.lie == .green || next.lie == .fringe
        }
        // Holed out in <= target strokes implies the green was reached in
        // regulation; an unfinished hole can't be judged yet.
        return isComplete ? true : nil
    }
}

// MARK: - Round

struct GolfRound: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var courseID: UUID
    var courseName: String
    var teeName: String
    var roundType: RoundType
    var scoringMode: ScoringMode
    var holesSnapshot: [GolfHole]
    var holeScores: [HoleScore] // in play order
    var currentHoleNumber: Int
    var status: RoundStatus
    var startedAt: Date
    var finishedAt: Date?
    var windMph: Double
    var windFromDegrees: Double
    var recap: String
    var courseRating: String

    init(
        id: UUID = UUID(),
        course: GolfCourse,
        teeName: String,
        roundType: RoundType,
        scoringMode: ScoringMode,
        startHole: Int = 1,
        windMph: Double = 5,
        windFromDegrees: Double = 180
    ) {
        self.id = id
        courseID = course.id
        courseName = course.name
        self.teeName = teeName
        self.roundType = roundType
        self.scoringMode = scoringMode
        holesSnapshot = course.holes
        let numbers: [Int]
        switch roundType {
        case .eighteen: numbers = Array(1...18)
        case .front9: numbers = Array(1...9)
        case .back9: numbers = Array(10...18)
        }
        // Rotate so play starts at the requested hole.
        let startIdx = max(0, numbers.firstIndex(of: startHole) ?? 0)
        let ordered = Array(numbers[startIdx...] + numbers[..<startIdx])
        holeScores = ordered.map { HoleScore(holeNumber: $0) }
        currentHoleNumber = ordered.first ?? 1
        status = .active
        startedAt = Date()
        finishedAt = nil
        self.windMph = windMph
        self.windFromDegrees = windFromDegrees
        recap = ""
        courseRating = ""
    }

    func hole(_ number: Int) -> GolfHole? {
        holesSnapshot.first { $0.number == number }
    }

    func score(for number: Int) -> HoleScore? {
        holeScores.first { $0.holeNumber == number }
    }

    var totalGross: Int { holeScores.reduce(0) { $0 + $1.grossScore } }
    var totalPar: Int {
        holeScores.reduce(0) { $0 + (hole($1.holeNumber)?.par ?? 4) }
    }

    var toPar: Int { totalGross - totalPar }

    var toParLabel: String {
        if toPar == 0 { return "E" }
        return toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }

    /// Holes the player has finished. Mid-round, to-par over *all* holes is
    /// meaningless (e.g. 3 strokes on hole 1 of 18 reads "-69"), so the resume
    /// card scores only completed holes.
    var completedHoles: [HoleScore] { holeScores.filter(\.isComplete) }

    var completedToPar: Int {
        completedHoles.reduce(0) { $0 + $1.grossScore - (hole($1.holeNumber)?.par ?? 4) }
    }

    var completedToParLabel: String {
        let v = completedToPar
        if v == 0 { return "E" }
        return v > 0 ? "+\(v)" : "\(v)"
    }

    var durationLabel: String {
        let end = finishedAt ?? Date()
        let mins = max(1, Int(end.timeIntervalSince(startedAt) / 60))
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    func layout(for holeNumber: Int) -> HoleLayout? {
        hole(holeNumber)?.layout ?? GeorgetownGPS.layout(for: holeNumber)
    }

    func pinCoordinate(for holeNumber: Int) -> GeoPoint? {
        guard let layout = layout(for: holeNumber) else { return nil }
        if let geo = score(for: holeNumber)?.pinPosition.coordinate {
            return geo
        }
        let pin = score(for: holeNumber)?.pinPosition
        return layout.resolvedPin(normalizedX: pin?.x ?? 0.5, normalizedY: pin?.y ?? 0.62)
    }

    func ballCoordinate(for holeNumber: Int) -> GeoPoint? {
        guard let layout = layout(for: holeNumber) else { return nil }
        let hole = score(for: holeNumber)
        if let end = hole?.shots.last(where: { $0.end != nil })?.end {
            return end
        }
        if hole?.shots.isEmpty ?? true {
            return layout.tee
        }
        return layout.point(afterTravelling: travelledYards(holeNumber), toward: pinCoordinate(for: holeNumber) ?? layout.pin)
    }

    func travelledYards(_ holeNumber: Int) -> Double {
        guard let def = hole(holeNumber), let hole = score(for: holeNumber) else { return 0 }
        var remaining = Double(def.yardage)
        for shot in hole.shots {
            if let end = shot.end, let pin = pinCoordinate(for: holeNumber) {
                remaining = end.yards(to: pin)
            } else if let carry = shot.carryYards {
                remaining = max(0, remaining - carry)
            } else if let d = shot.distanceToPinBeforeYards {
                remaining = max(0, d - (shot.club?.stockYards ?? 150))
            } else {
                remaining = max(0, remaining - (shot.club?.stockYards ?? 150))
            }
        }
        return max(0, Double(def.yardage) - remaining)
    }
}

// MARK: - Sample course

enum SampleCourses {
    static let georgetown: GolfCourse = {
        // Published Blue scorecard (par 70 / 5374 / 67.6 / 119) plus OSM hole GPS.
        let pars = [4, 4, 3, 5, 4, 5, 3, 4, 4, 3, 4, 4, 4, 3, 5, 4, 3, 4]
        let hcps = [5, 3, 17, 1, 15, 7, 9, 11, 13, 8, 2, 18, 4, 10, 12, 14, 16, 6]
        let yds = [344, 357, 121, 523, 267, 510, 133, 277, 257,
                   193, 384, 243, 343, 148, 439, 353, 138, 344]
        let dogs = [0.2, -0.35, 0.0, 0.45, -0.2, 0.3, 0.0, -0.4, 0.15,
                    0.1, 0.0, -0.45, 0.35, -0.15, 0.0, 0.4, -0.3, 0.2]
        let holes = (0..<18).map {
            GolfHole(number: $0 + 1, par: pars[$0], handicap: hcps[$0],
                     yardage: yds[$0], dogleg: dogs[$0],
                     layout: GeorgetownGPS.layout(for: $0 + 1))
        }
        return GolfCourse(
            id: UUID(uuidString: "6E3B1C44-1E2A-4A7B-9C0D-00CC6E07E001") ?? UUID(),
            name: "Georgetown Country Club",
            location: "Georgetown, TX · \(GeorgetownGPS.address)",
            tees: [
                CourseTee(name: "Blue", totalYardage: 5374, rating: 67.6, slope: 119),
                CourseTee(name: "White", totalYardage: 5076, rating: 66.0, slope: 112),
                CourseTee(name: "Yellow", totalYardage: 4540, rating: 63.5, slope: 107),
                CourseTee(name: "Red", totalYardage: 4239, rating: 62.6, slope: 104),
            ],
            holes: holes,
            coordinate: GeorgetownGPS.courseCenter
        )
    }()

    static let all: [GolfCourse] = [georgetown]
}

// MARK: - Formatting

enum GolfFormat {
    static func yards(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))"
    }

    static func feet(_ value: Double?) -> String {
        guard let value else { return "–" }
        if value < 20 { return String(format: "%.0f", value) }
        return "\(Int(value.rounded()))"
    }
}
