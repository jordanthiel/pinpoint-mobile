import Foundation

struct GolfActivityState: Codable, Hashable {
    var hole: Int
    var par: Int
    var yards: Int?
    var estimated: Bool
    var score: Int?
    var toPar: String
    var holesCompleted: Int
}
