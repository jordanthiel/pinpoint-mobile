import Foundation

#if PINPOINT_STORE_SMOKE
final class WatchShotDetector {}
#endif

@main
struct SyncPerformanceMain {
    @MainActor final class Heartbeat {
        var worst = 0.0
        var ticks = 0
        var last = Date()
        func tick() {
            worst = max(worst, Date().timeIntervalSince(last))
            last = Date(); ticks += 1
        }
    }

    @MainActor static func main() async throws {
        var rounds: [GolfRound] = []
        for _ in 0..<3 {
            var round = GolfRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
            for index in round.holeScores.indices {
                let tee = round.layout(for: index + 1)!.tee
                round.holeScores[index].recordedScore = 4
                round.holeScores[index].recordedPutts = 2
                round.holeScores[index].isComplete = true
                round.holeScores[index].locationSamples = (0..<120).map {
                    GolfLocationSample(point: tee.offset(eastYards: Double($0), northYards: 0),
                        timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double($0 * 5)), accuracy: 5, speed: 2)
                }
                round.holeScores[index].shots = (1...4).map { TrackedShot(number: $0, club: $0 > 2 ? .putter : .iron7, start: tee) }
            }
            rounds.append(round)
        }
        let input = GolfCloudState(rounds: rounds, bag: .standard, practice: [])
        let records = try GolfRecords.flatten(input)
        let base = try GolfRecords.assemble(records)
        let checkpoint = GolfRecordCheckpoint(cursor: 1, records: records)
        let activeID = rounds.first?.id
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoundStore(storageDirectory: directory)
        store.activeRound = rounds[0]
        store.pastRounds = Array(rounds.dropFirst())
        precondition(store.applyCloud(base, revision: 1, base: base, checkpoint: checkpoint))
        // Warm up the first checkpoint after cloud installation.
        precondition(store.saveScoreEntry(1, score: 4, putts: 2))
        let canonical = directory.appendingPathComponent("golf-state.json")
        let before = try Data(contentsOf: canonical)
        var longest = 0.0
        for index in 0..<30 {
            let start = Date()
            precondition(store.saveScoreEntry(1, score: index % 2 == 0 ? 5 : 4, putts: 2))
            longest = max(longest, Date().timeIntervalSince(start))
        }
        let journal = try Data(contentsOf: canonical.appendingPathExtension("round"))
        let after = try Data(contentsOf: canonical)
        precondition(after == before)
        let reloaded = RoundStore(storageDirectory: directory)
        precondition(reloaded.activeRound?.score(for: 1)?.recordedScore == 4)
        precondition(reloaded.cloudCheckpoint?.cursor == 1)
        print("Round journal: longest of 30 durable score saves=\(Int(longest * 1000))ms, journal=\(journal.count) bytes, unchanged canonical=\(before.count) bytes")
        for background in [false, true] {
            let heartbeat = Heartbeat()
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    heartbeat.tick()
                    do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
                }
            }
            try await Task.sleep(for: .milliseconds(20))
            let started = Date()
            let prepared: GolfPreparedSync
            if background {
                prepared = try await Task.detached(priority: .utility) {
                    try GolfPreparedSync.prepare(local: base, base: base, checkpoint: checkpoint, activeID: activeID)
                }.value
            } else {
                prepared = try GolfPreparedSync.prepare(local: base, base: base, checkpoint: checkpoint, activeID: activeID)
            }
            let duration = Date().timeIntervalSince(started)
            try await Task.sleep(for: .milliseconds(20))
            ticker.cancel()
            print("\(background ? "Background worker" : "Main-thread baseline"): reconcile=\(Int(duration * 1000))ms, longest UI heartbeat gap=\(Int(heartbeat.worst * 1000))ms, ticks=\(heartbeat.ticks), checkpoint=\(prepared.encodedState.count) bytes, outgoing changes=\(prepared.changes.count)")
            precondition(prepared.changes.isEmpty && !prepared.dataChanged)
        }
    }
}
