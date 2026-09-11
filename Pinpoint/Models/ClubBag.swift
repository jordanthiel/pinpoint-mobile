import Foundation

/// One club the golfer actually carries, with their carry distance.
struct ClubBagEntry: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var club: GolfClub
    var carryYards: Double

    init(id: UUID = UUID(), club: GolfClub, carryYards: Double? = nil) {
        self.id = id
        self.club = club
        self.carryYards = carryYards ?? club.stockYards
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

    func carry(for club: GolfClub) -> Double? {
        clubs.first { $0.club == club }?.carryYards
    }

    func contains(_ club: GolfClub) -> Bool {
        clubs.contains { $0.club == club }
    }

    var clubsNotInBag: [GolfClub] {
        GolfClub.allCases.filter { !contains($0) }
    }

    mutating func upsert(_ club: GolfClub, carryYards: Double) {
        let yards = min(400, max(20, carryYards))
        if let idx = clubs.firstIndex(where: { $0.club == club }) {
            clubs[idx].carryYards = yards
        } else {
            clubs.append(ClubBagEntry(club: club, carryYards: yards))
        }
    }

    mutating func remove(_ club: GolfClub) {
        clubs.removeAll { $0.club == club }
    }
}
