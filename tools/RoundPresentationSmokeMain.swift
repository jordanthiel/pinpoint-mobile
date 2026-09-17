import Foundation

final class WatchShotDetector {}

@main
struct RoundPresentationSmokeMain {
    @MainActor static func main() throws {
        guard let fixture = ProcessInfo.processInfo.environment["PINPOINT_RECORD_RESPONSE"] else {
            fatalError("Set PINPOINT_RECORD_RESPONSE to a cloud record response fixture")
        }
        let checkpoint = try JSONDecoder().decode(GolfRecordCheckpoint.self,
            from: Data(contentsOf: URL(fileURLWithPath: fixture)))
        let (fresh, badKeys) = GolfRecords.assembleTolerant(checkpoint.records)
        precondition(badKeys.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoundStore(storageDirectory: directory)
        var stale = fresh
        for i in stale.rounds.indices {
            for j in stale.rounds[i].holeScores.indices { stale.rounds[i].holeScores[j].shots = [] }
        }
        precondition(store.applyCloud(stale, revision: 0, base: stale))
        let selectedID = stale.rounds[0].id
        precondition(store.round(id: selectedID)!.holeScores.allSatisfy { $0.shots.isEmpty })
        precondition(store.applyCloud(fresh, revision: checkpoint.cursor, base: fresh))
        let detail = store.round(id: selectedID)!
        let expected = fresh.rounds.first { $0.id == selectedID }!
        let count = detail.holeScores.reduce(0) { $0 + $1.shots.count }
        precondition(count > 0 && count == expected.holeScores.reduce(0) { $0 + $1.shots.count })
        let detailSG = Core11.compute(rounds: [detail], level: .default)
        let insightsSG = Core11.compute(rounds: [expected], level: .default)
        precondition(detailSG.hasSG && detailSG.sgTotal.perRound == insightsSG.sgTotal.perRound)
        print("PASS selected round observes cloud refresh: \(count) shots and matching Insights SG")
        precondition(store.deleteRound(selectedID))
        precondition(store.round(id: selectedID) == nil)
        precondition(store.round(id: UUID()) == nil)
        print("PASS missing/deleted selection never falls back to a different round")
    }
}
