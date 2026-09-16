import Foundation

struct GolfLocationSample: Codable, Hashable {
    var point: GeoPoint
    var timestamp: Date
    var accuracy: Double
    var speed: Double
}

struct GolfStop: Identifiable, Equatable {
    var id: Date { began }
    var point: GeoPoint
    var began: Date
    var ended: Date
    var watchConfirmed = false
}

/// GPS is evidence for placement, never proof that a stroke was played.
struct GolfLocationTrail: Equatable {
    var breadcrumbs: [GeoPoint] = []
    var stops: [GolfStop] = []
    /// Contiguous observed movement only; never connect a GPS outage with a guessed route.
    var movementPaths: [[GeoPoint]] = []

    init(samples: [GolfLocationSample] = [], swings: [SwingCandidate] = []) {
        var path: [GeoPoint] = []
        var previous: GolfLocationSample?
        func finishPath() {
            if path.count >= 2 { movementPaths.append(path) }
            path = []
        }
        for sample in samples {
            guard sample.accuracy > 0, sample.accuracy <= 25 else { finishPath(); previous = nil; continue }
            if let previous, sample.timestamp.timeIntervalSince(previous.timestamp) > 15 ||
                sample.timestamp < previous.timestamp || previous.point.yards(to: sample.point) > 100 {
                finishPath()
            }
            if path.last.map({ $0.yards(to: sample.point) >= 4 }) ?? true { path.append(sample.point) }
            previous = sample
        }
        finishPath()
        var cluster: [GolfLocationSample] = []
        func finish() {
            guard let first = cluster.first, let last = cluster.last else { return }
            if last.timestamp.timeIntervalSince(first.timestamp) >= 10 {
                let weight = cluster.reduce(0.0) { $0 + 1 / max(1, $1.accuracy * $1.accuracy) }
                let lat = cluster.reduce(0.0) { $0 + $1.point.latitude / max(1, $1.accuracy * $1.accuracy) } / weight
                let lon = cluster.reduce(0.0) { $0 + $1.point.longitude / max(1, $1.accuracy * $1.accuracy) } / weight
                stops.append(GolfStop(point: GeoPoint(latitude: lat, longitude: lon), began: first.timestamp, ended: last.timestamp))
            } else { breadcrumbs += cluster.map(\.point) }
            cluster = []
        }
        for sample in samples {
            guard sample.accuracy > 0, sample.accuracy <= 25 else { finish(); continue }
            if let first = cluster.first, let last = cluster.last,
               sample.timestamp.timeIntervalSince(last.timestamp) > 15 || first.point.yards(to: sample.point) > 10 {
                finish()
            }
            if sample.speed > 0.8 { finish(); breadcrumbs.append(sample.point) }
            else { cluster.append(sample) }
        }
        finish()
        for swing in swings where swing.state != .dismissed && swing.locationSource == "watch" {
            guard let lat = swing.latitude, let lon = swing.longitude,
                  let accuracy = swing.accuracy, accuracy >= 0, accuracy <= 20 else { continue }
            let point = GeoPoint(latitude: lat, longitude: lon)
            if let index = stops.indices.min(by: { stops[$0].point.yards(to: point) < stops[$1].point.yards(to: point) }),
               stops[index].point.yards(to: point) <= 25,
               swing.timestamp >= stops[index].began.addingTimeInterval(-20),
               swing.timestamp <= stops[index].ended.addingTimeInterval(20) {
                stops[index].point = point
                stops[index].watchConfirmed = true
            } else {
                stops.append(GolfStop(point: point, began: swing.timestamp, ended: swing.timestamp, watchConfirmed: true))
            }
        }
        stops.sort { $0.began < $1.began }
    }

    func nearest(to point: GeoPoint, radiusYards: Double = 12) -> GolfStop? {
        guard let stop = stops.min(by: { $0.point.yards(to: point) < $1.point.yards(to: point) }),
              stop.point.yards(to: point) <= radiusYards else { return nil }
        return stop
    }

    func preferred(excluding used: [GeoPoint], near reference: GeoPoint? = nil) -> GolfStop? {
        let available = stops.filter { stop in !used.contains { $0.yards(to: stop.point) < 10 } }
        let watch = available.filter(\.watchConfirmed)
        let choices = watch.isEmpty ? available : watch
        if let reference { return choices.min { $0.point.yards(to: reference) < $1.point.yards(to: reference) } }
        return choices.last
    }
}

/// Camera frames reuse the processed trail; GPS/IMU changes rebuild it once.
final class GolfLocationTrailCache {
    private var samples: [GolfLocationSample] = []
    private var swings: [SwingCandidate] = []
    private var value = GolfLocationTrail()
    func resolve(samples: [GolfLocationSample], swings: [SwingCandidate]) -> GolfLocationTrail {
        if self.samples != samples || self.swings != swings {
            self.samples = samples; self.swings = swings
            value = GolfLocationTrail(samples: samples, swings: swings)
        }
        return value
    }
}

extension RoundStore {
    func locationTrail(_ hole: Int) -> GolfLocationTrail {
        GolfLocationTrail(samples: activeRound?.score(for: hole)?.locationSamples ?? [],
                          swings: (activeRound?.swingCandidates ?? []).filter { $0.hole == hole })
    }

    func suggestedStop(_ hole: Int, near reference: GeoPoint? = nil) -> GeoPoint? {
        let used = activeRound?.score(for: hole)?.shots.compactMap(\.start) ?? []
        let trail = locationTrail(hole)
        if used.isEmpty, activeRound?.score(for: hole)?.shots.isEmpty == true,
           let tee = activeRound?.teeCoordinate(for: hole) {
            let stop = trail.preferred(excluding: [], near: tee)
            return stop.flatMap { $0.point.yards(to: tee) <= 30 ? $0.point : nil } ?? tee
        }
        return trail.preferred(excluding: used, near: reference)?.point
    }

    func recordLocation(_ sample: GolfLocationSample) {
        guard let round = activeRound, sample.timestamp >= round.startedAt,
              abs(sample.timestamp.timeIntervalSinceNow) < 20, sample.accuracy > 0, sample.accuracy <= 25,
              sample.timestamp.timeIntervalSince(lastLocationEvaluation) >= 5 else { return }
        lastLocationEvaluation = sample.timestamp
        guard let number = round.locationRecordingHole(at: sample.point) else { return }
        // Five-second samples preserve dwell timing while bounding disk and sync traffic.
        if let previous = round.score(for: number)?.locationSamples?.last,
           sample.timestamp.timeIntervalSince(previous.timestamp) < 5 { return }
        saveLocationSample(sample, hole: number)
    }
}

extension GolfRound {
    /// Keep logging where the golfer is, even while they edit an earlier hole.
    func locationRecordingHole(at point: GeoPoint) -> Int? {
        let matches = holeScores.compactMap { score -> (Int, Double)? in
            guard let layout = playLayout(for: score.holeNumber), layout.isStandingOnHole(point) else { return nil }
            return (score.holeNumber, layout.distanceToCorridor(point))
        }
        guard let closest = matches.min(by: { $0.1 < $1.1 }), closest.1 < 85 else { return nil }
        if let current = matches.first(where: { $0.0 == currentHoleNumber }), current.1 < 85, current.1 <= closest.1 + 14 {
            return current.0 // Shared tees/fairways: prefer the active hole unless clearly elsewhere.
        }
        return closest.0
    }
}

extension GolfRound {
    /// A stop is only a possible shot after the player leaves it. IMU evidence wins
    /// over an unconfirmed cart stop; a newer saved shot supersedes that evidence.
    func lastShotAnchor(for number: Int, current: GeoPoint?) -> CompanionShotAnchor? {
        let saved = score(for: number)?.shots.filter { !$0.isPutt && $0.start != nil }
            .max { $0.number < $1.number }
        let swing = (swingCandidates ?? []).filter {
            $0.hole == number && $0.state == .pending && $0.latitude != nil && $0.longitude != nil &&
            ($0.accuracy ?? .infinity) <= 40 && $0.timestamp >= startedAt
        }.max { $0.timestamp < $1.timestamp }
        if let swing, saved == nil || swing.timestamp > saved!.timestamp {
            return CompanionShotAnchor(latitude: swing.latitude!, longitude: swing.longitude!,
                timestamp: swing.timestamp, estimated: true)
        }
        if swing == nil, let current,
           let stop = GolfLocationTrail(samples: score(for: number)?.locationSamples ?? []).stops.last(where: {
               $0.point.yards(to: current) > 15 && (saved == nil || $0.began > saved!.timestamp)
           }) {
            return CompanionShotAnchor(latitude: stop.point.latitude, longitude: stop.point.longitude,
                timestamp: stop.ended, estimated: true)
        }
        if let saved, let point = saved.start {
            return CompanionShotAnchor(latitude: point.latitude, longitude: point.longitude,
                timestamp: saved.timestamp, estimated: false)
        }
        return nil
    }
}
