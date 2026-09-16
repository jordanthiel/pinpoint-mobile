import Foundation

struct MappedFairway: Decodable {
    var outer: [GeoPoint]
    var inner: [[GeoPoint]]
    func contains(_ point: GeoPoint) -> Bool {
        Self.contains(point, ring: outer) && !inner.contains { Self.contains(point, ring: $0) }
    }
    static func contains(_ point: GeoPoint, ring: [GeoPoint]) -> Bool {
        guard ring.count >= 3, point.latitude.isFinite, point.longitude.isFinite else { return false }
        var inside = false
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude),
               point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
        }
        return inside
    }
}

extension GolfRound {
    /// Shot markers are origins: shot 2 marks the tee shot's landing location.
    /// Compute from current geometry so edits/deletions cannot leave a stale stat.
    func fairwayHit(for number: Int, reviewing shots: [TrackedShot]? = nil) -> Bool? {
        guard let definition = hole(number), definition.par > 3, let hole = score(for: number) else { return nil }
        if let explicit = hole.recordedFairwayHit { return explicit }
        let ordered = (shots ?? hole.shots).sorted { $0.number < $1.number }
        guard let first = ordered.first(where: { $0.number == 1 }) else { return nil }
        if (hole.penaltiesByShot?[1] ?? 0) > 0 { return false }
        // Explicit finish observations are stronger evidence than a map estimate.
        if let finish = first.observations?.finish {
            return finish == .fairway || finish == .green || finish == .holed
        }
        let second = ordered.first { $0.number == 2 }
        if let second, second.lieWasInferred == false ||
            (second.lieWasInferred == nil && second.lie != .fairway && second.lie != .tee) {
            return second.lie == .fairway || second.lie == .green
        }
        let landing = second?.start ?? first.end
        if let landing, courseID == SampleCourses.georgetown.id,
           let fairways = GeorgetownFairways.holes[number], !fairways.isEmpty {
            if let layout = definition.layout,
               MappedFairway.contains(landing, ring: layout.greenOutline) { return true }
            return fairways.contains { $0.contains(landing) }
        }
        // Without mapped boundaries, only an explicitly reported lie is evidence.
        guard let second, second.lieWasInferred != true else { return nil }
        return second.lie == .fairway || second.lie == .green
    }
}
