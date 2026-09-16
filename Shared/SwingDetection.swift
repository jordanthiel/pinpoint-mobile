import Foundation

struct SwingCandidate: Codable, Identifiable, Hashable, Equatable {
    enum State: String, Codable { case pending, confirmed, dismissed }
    var id = UUID()
    var roundID: UUID
    var hole: Int
    var timestamp: Date
    var latitude: Double?
    var longitude: Double?
    var accuracy: Double?
    var locationSource: String // watch, phone, estimated
    var peakG: Double
    var rotation: Double
    var dwellSeconds: Double
    var state: State = .pending
}

/// Conservative, testable motion gate. Candidate only: practice swings still need review.
struct SwingDetectionGate {
    var restSince: Double?
    var lastRest: Double?
    var rotationSince: Double?
    var cooldownUntil: Double = 0
    mutating func sample(time: Double, acceleration: Double, rotation: Double, stationary: Bool) -> Bool {
        guard time.isFinite, acceleration.isFinite, rotation.isFinite else { return false }
        if acceleration < 0.25 && rotation < 0.8 {
            if restSince == nil { restSince = time }
            if time - (restSince ?? time) >= 2 { lastRest = time }
        } else { restSince = nil }
        if rotation > 2 {
            if rotationSince == nil { rotationSince = time }
        } else if rotation < 0.8 { rotationSince = nil }
        let duration = time - (rotationSince ?? time)
        guard time >= cooldownUntil, stationary,
              time - (lastRest ?? -.infinity) < 4,
              acceleration >= 2.2, rotation >= 4,
              duration >= 0.08, duration <= 2.5 else { return false }
        cooldownUntil = time + 10
        lastRest = nil; rotationSince = nil
        return true
    }
}
