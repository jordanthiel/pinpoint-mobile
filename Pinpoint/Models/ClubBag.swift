import Foundation

/// One club the golfer actually carries, with their carry distance.
struct ClubBagEntry: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var club: GolfClub
    var carryYards: Double
    /// “4 Hybrid”, “60°”, etc. Empty uses the stock name.
    var nickname: String?

    init(id: UUID = UUID(), club: GolfClub, carryYards: Double? = nil, nickname: String? = nil) {
        self.id = id
        self.club = club
        self.carryYards = carryYards ?? club.stockYards
        self.nickname = nickname
    }

    var shortLabel: String {
        let n = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? club.shortName : n
    }

    var fullLabel: String {
        let n = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? club.displayName : n
    }
}

/// The player's bag. Map recommendations use these carries, not stock numbers.
struct ClubBag: Codable, Equatable {
    var clubs: [ClubBagEntry]

    /// Typical 14-club set with stock carries until the golfer edits them.
    static var standard: ClubBag {
        let order: [GolfClub] = [
            .driver, .wood3, .wood5, .hybrid,
            .iron5, .iron6, .iron7, .iron8, .iron9,
            .pitchingWedge, .gapWedge, .sandWedge, .lobWedge,
            .putter,
        ]
        return ClubBag(clubs: order.map { ClubBagEntry(club: $0) })
    }

    var isEmpty: Bool { clubs.isEmpty }

    /// Full shots only, shortest carry first — used to pick a club.
    var shotClubs: [ClubBagEntry] {
        clubs.filter { !$0.club.isPutter }.sorted { $0.carryYards < $1.carryYards }
    }

    /// Longest first, for the bag editor and pickers.
    var displayClubs: [ClubBagEntry] {
        clubs.sorted { $0.carryYards > $1.carryYards }
    }

    func entry(for club: GolfClub) -> ClubBagEntry? {
        displayClubs.first { $0.club == club } ?? clubs.first { $0.club == club }
    }

    func carry(for club: GolfClub) -> Double? {
        entry(for: club)?.carryYards
    }

    func contains(_ club: GolfClub) -> Bool {
        clubs.contains { $0.club == club }
    }

    var clubsNotInBag: [GolfClub] {
        GolfClub.allCases.filter { !contains($0) }
    }

    mutating func upsert(_ club: GolfClub, carryYards: Double) {
        let yards = min(400, max(15, carryYards))
        if let idx = clubs.firstIndex(where: { $0.club == club }) {
            clubs[idx].carryYards = yards
        } else {
            clubs.append(ClubBagEntry(club: club, carryYards: yards))
        }
    }

    mutating func update(_ entry: ClubBagEntry) {
        var next = entry
        next.carryYards = min(400, max(15, entry.carryYards))
        if let idx = clubs.firstIndex(where: { $0.id == entry.id }) {
            clubs[idx] = next
        } else {
            clubs.append(next)
        }
    }

    mutating func add(_ club: GolfClub, nickname: String? = nil, carryYards: Double? = nil) {
        clubs.append(ClubBagEntry(club: club, carryYards: carryYards, nickname: nickname))
    }

    mutating func remove(_ club: GolfClub) {
        clubs.removeAll { $0.club == club }
    }

    mutating func remove(id: UUID) {
        clubs.removeAll { $0.id == id }
    }
}
