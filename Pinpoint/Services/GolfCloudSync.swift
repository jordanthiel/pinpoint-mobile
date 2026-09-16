import Foundation
import Supabase

@MainActor
@Observable
final class GolfCloudSync {
    private let store: RoundStore
    private var epoch = UUID()
    private var syncing = false
    private var requested = false
    private var lastSyncedGeneration: UInt64?
    private var debounce: Task<Void, Never>?

    init(store: RoundStore) { self.store = store }

    func observeAccount() async {
        guard !CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-hole-") }) else { return }
        store.onLocalChange = { [weak self] in
            Task { @MainActor in self?.schedule() }
        }
        guard let client = PinpointSupabase.client else { return }
        for await (_, session) in client.auth.authStateChanges {
            if Task.isCancelled { return }
            let user = session?.user.id
            if user != store.accountID {
                epoch = UUID()
                lastSyncedGeneration = nil
                guard store.selectAccount(user) else { store.cloudStatus = store.lastError ?? "Account data unavailable"; continue }
            }
            if user == nil { store.cloudStatus = "Sign in to sync golf data" }
            else { schedule() }
        }
    }

    func schedule() {
        guard store.accountID != nil else { return }
        store.cloudStatus = "Changes saved on this device · sync pending"
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await self?.sync()
        }
    }

    private struct Pull: Encodable { var after_cursor: Int }
    private struct Commit: Encodable { var changes: [GolfRecords.Change] }
    private struct Receipt: Decodable { var accepted: Bool }

    func sync() async {
        guard let client = PinpointSupabase.client, let account = store.accountID, store.localStorageHealthy else { return }
        if syncing { requested = true; return }
        syncing = true; store.cloudSyncing = true
        let run = epoch
        defer {
            syncing = false; store.cloudSyncing = false
            if requested { requested = false; schedule() }
        }
        do {
            let session = try await client.auth.session
            guard session.user.id == account, run == epoch,
                  let url = PinpointSupabase.configURL, let key = PinpointSupabase.configKey else { return }
            // Bind all requests in this pass to the captured user. A simultaneous
            // sign-out/sign-in must never switch the bearer token under a write.
            let token = session.accessToken
            let scoped = SupabaseClient(supabaseURL: url, supabaseKey: key,
                options: .init(auth: .init(autoRefreshToken: false, accessToken: { token })))
            for _ in 0..<4 {
                let checkpoint = store.cloudCheckpoint ?? GolfRecordCheckpoint(cursor: 0, records: [])
                let response = try await scoped.rpc("pull_golf_records", params: Pull(after_cursor: checkpoint.cursor)).execute()
                let bytes = response.data
                let delta = try await Task.detached(priority: .utility) {
                    try JSONDecoder().decode(GolfRecordCheckpoint.self, from: bytes)
                }.value
                guard run == epoch, store.accountID == account, client.auth.currentUser?.id == account else { return }
                if delta.records.isEmpty, lastSyncedGeneration == store.dataGeneration {
                    store.cloudStatus = "Golf data synced"
                    return
                }
                let generation = store.dataGeneration
                let data = store.cloudData
                let base = store.cloudBase
                let activeID = store.activeRound?.id
                let previousCheckpoint = checkpoint
                let prepared = try await Task.detached(priority: .utility) {
                    var checkpoint = previousCheckpoint
                    checkpoint.apply(delta)
                    return try GolfPreparedSync.prepare(local: data, base: base, checkpoint: checkpoint, activeID: activeID)
                }.value
                guard run == epoch, store.accountID == account, client.auth.currentUser?.id == account else { return }
                switch await store.applyPreparedCloud(prepared, expectedGeneration: generation, owner: account) {
                case .superseded: continue
                case .failed: throw SyncError.localWrite
                case .applied: break
                }
                guard run == epoch, store.accountID == account, client.auth.currentUser?.id == account else { return }
                let changes = prepared.changes
                if changes.isEmpty {
                    lastSyncedGeneration = store.dataGeneration
                    store.cloudStatus = "Golf data synced"
                    return
                }
                let _: Receipt = try await Task.detached(priority: .utility) {
                    try await scoped.rpc("commit_golf_records", params: Commit(changes: changes)).execute().value
                }.value
                guard run == epoch, store.accountID == account, client.auth.currentUser?.id == account else { return }
                // Pull the committed rows on the next pass. The persisted base and
                // current local data also preserve edits made during this request.

            }
            store.cloudStatus = "Changes saved locally · another device is syncing. Retrying soon."
        } catch {
            guard run == epoch else { return }
            store.cloudStatus = "Golf data saved locally · sync unavailable. We'll retry when connected."
        }
    }
    private enum SyncError: Error { case localWrite }
}
