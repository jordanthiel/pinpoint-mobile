import Foundation

struct CompanionHole: Codable, Identifiable, Equatable {
    var id: Int
    var par: Int
    var yardage: Int
    var score: Int?
    var putts: Int?
    var revision: String
    var pinLatitude: Double?
    var pinLongitude: Double?
    var penalties: Int?
    var handicap: Int?
    var shots: [CompanionShot]?
    var lastShotAnchor: CompanionShotAnchor?
}
struct CompanionShotAnchor: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var estimated: Bool
}
struct CompanionShot: Codable, Identifiable, Equatable {
    var id: UUID
    var number: Int
    var club: String
    var isPutt: Bool
    var carryYards: Double?
    var remainingFeet: Double?
    var detail: String
}
struct CompanionRound: Codable, Equatable {
    var id: UUID
    var course: String
    var currentHole: Int
    var holes: [CompanionHole]
    var focus: String
    var updatedAt: Date
    var phoneLocation: CompanionShotAnchor?
}
struct CompanionScoreEdit: Codable {
    var id = UUID()
    var roundID: UUID
    var hole: Int
    var revision: String
    var score: Int
    var putts: Int?
    var penalties: Int?
    var advance = false
}
enum CompanionWire {
    static let snapshot = "roundSnapshot"
    static let edit = "scoreEdit"
    static let refresh = "refreshRound"
    static let noRound = "noRound"
    static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Any?) -> T? {
        guard let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
