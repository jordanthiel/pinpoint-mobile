import Foundation
final class WatchShotDetector {}

@main struct UploadQueueSmokeMain {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("upload-queue-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RoundStore(storageDirectory: directory)
        store.startRound(course: SampleCourses.georgetown, teeName: "Blue", roundType: .eighteen, scoringMode: .smart)
        precondition(store.saveScoreEntry(1, score: 3, putts: 2))
        let base = try GolfRecords.assemble(GolfRecords.flatten(store.cloudData))
        precondition(store.applyCloud(base, revision: 1, base: base))
        precondition(store.saveScoreEntry(1, score: 4, putts: 2))
        let submitted = store.cloudData
        let upload = GolfPendingUpload(snapshot: submitted,
            changes: try GolfRecords.changes(local: submitted, mirror: GolfRecords.flatten(base)))
        precondition(store.enqueueUpload(upload, owner: nil))
        precondition(!store.enqueueUpload(upload, owner: nil))
        precondition(store.saveScoreEntry(1, score: 5, putts: 2))
        store.load() // Lost response, process killed, then restarted.
        precondition(store.pendingUpload?.id == upload.id)
        precondition(store.pendingUpload?.snapshot.rounds.first?.score(for: 1)?.recordedScore == 4)
        precondition(store.activeRound?.score(for: 1)?.recordedScore == 5)
        precondition(!store.resolveUpload(id: upload.id, accepted: true, owner: UUID()))
        precondition(!store.resolveUpload(id: UUID(), accepted: true, owner: nil))
        precondition(store.resolveUpload(id: upload.id, accepted: true, owner: nil))
        store.load()
        precondition(store.pendingUpload == nil)
        precondition(store.cloudBase.rounds.first?.score(for: 1)?.recordedScore == 4)
        let next = try GolfPreparedSync.prepare(local: store.cloudData, base: store.cloudBase,
            checkpoint: .init(cursor: 2, records: GolfRecords.flatten(submitted)), activeID: store.activeRound?.id)
        precondition(next.merged.rounds.count == 1)
        precondition(next.merged.rounds.first?.score(for: 1)?.recordedScore == 5)
        precondition(!next.changes.isEmpty)
        print("PASS lost response and restart preserve batch identity and racing edit without duplicates")

        // A rejected batch keeps the old base and all local edits for reconciliation.
        let rejected = GolfPendingUpload(snapshot: next.merged, changes: next.changes)
        precondition(store.enqueueUpload(rejected, owner: nil))
        precondition(store.resolveUpload(id: rejected.id, accepted: false, owner: nil))
        store.load()
        precondition(store.pendingUpload == nil && store.cloudBase.rounds.first?.score(for: 1)?.recordedScore == 4)
        precondition(store.activeRound?.score(for: 1)?.recordedScore == 5)
        print("PASS rejected batch preserves local data and acknowledged baseline")

        // Finished rounds remain durable until the exact version is acknowledged.
        precondition(store.finishRound())
        let completed = store.cloudData
        let finalUpload = GolfPendingUpload(snapshot: completed,
            changes: try GolfRecords.changes(local: completed, mirror: GolfRecords.flatten(store.cloudBase)))
        precondition(store.enqueueUpload(finalUpload, owner: nil))
        store.load()
        precondition(store.pastRounds.count == 1 && store.pendingUpload?.id == finalUpload.id)
        precondition(store.resolveUpload(id: finalUpload.id, accepted: true, owner: nil))
        store.load()
        precondition(store.pastRounds.isEmpty && store.pendingUpload == nil)
        print("PASS completed round stays on disk until confirmed receipt")

        // Reverting a completed round to the old base while another version is
        // in flight must still persist that revert, even though data == base.
        var original = completed.rounds[0]
        original.recap = "original"
        let old = GolfCloudState(rounds: [original], bag: GolfCloudState.initialBag, practice: [])
        var sent = old
        sent.rounds[0].recap = "in flight"
        let reverting = GolfPendingUpload(snapshot: sent,
            changes: try GolfRecords.changes(local: sent, mirror: GolfRecords.flatten(old)))
        let cache = GolfLocalState(data: old, activeID: nil, base: old, pendingUpload: reverting).localCache()
        precondition(cache.data.rounds.count == 1 && cache.pendingUpload?.snapshot.rounds[0].recap == "in flight")
        print("PASS reverting to old baseline remains queued during in-flight upload")

        // Unchanged cloud history must not turn into deletions after reload.
        var history = original; history.id = UUID()
        var all = old; all.rounds.append(history)
        var changed = all; changed.rounds[0].recap = "changed"
        let pending = GolfPendingUpload(snapshot: changed,
            changes: try GolfRecords.changes(local: changed, mirror: GolfRecords.flatten(all)))
        let trimmed = GolfLocalState(data: changed, activeID: nil, base: all, pendingUpload: pending).localCache()
        precondition(trimmed.pendingUpload?.snapshot.rounds.count == 1)
        let reconciled = try GolfPreparedSync.prepare(local: trimmed.data, base: trimmed.pendingUpload!.snapshot,
            checkpoint: .init(cursor: 3, records: GolfRecords.flatten(changed)), activeID: nil)
        precondition(reconciled.merged.rounds.count == 2 && reconciled.changes.isEmpty)
        print("PASS acknowledgement after restart does not delete uncached cloud history")
    }
}
