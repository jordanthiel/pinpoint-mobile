import Foundation

struct CourseWind: Codable, Equatable, Hashable {
    var mph: Double
    var fromDegrees: Double?
    var observedAt: Date
    var station: String
    var stationID: String
    func isFresh(at now: Date = Date()) -> Bool {
        (-300...5400).contains(now.timeIntervalSince(observedAt))
    }
    var compass: String {
        guard let fromDegrees else { return mph < 0.5 ? "Calm" : "Variable" }
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((fromDegrees / 45).rounded()) % 8]
    }
    func helping(toward bearing: Double) -> Double {
        guard let fromDegrees, isFresh() else { return 0 }
        return -cos((bearing - fromDegrees) * .pi / 180)
    }
    static func milesPerHour(value: Double?, unit: String) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        switch unit {
        case "wmoUnit:km_h-1": return value / 1.609344
        case "wmoUnit:m_s-1": return value * 2.2369362921
        case "wmoUnit:kn": return value * 1.150779448
        case "wmoUnit:mi_h-1": return value
        default: return nil
        }
    }
}
