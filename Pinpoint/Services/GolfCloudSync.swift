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

    private struct Commit: Encodable { var changes: [GolfRecords.Change] }
    private struct Receipt: Decodable { var accepted: Bool }

    /// One page of pull_golf_records. `end_cursor`/`has_more` come from the
    /// paginated overload (migration 20260916120000); they are absent on the
    /// legacy single-argument function, which is treated as one final page.
    private struct PullPage: Decodable {
        var cursor: Int
        var end_cursor: Int?
        var has_more: Bool?
        var records: [GolfRecord]
    }
    private struct LegacyPullPage: Decodable {
        var cursor: Int
        var records: [GolfRecord]
    }

    /// Rows per pull page. Small pages keep each pull_golf_records call under
    /// the backend statement timeout (Postgres 57014 on giant full-history pulls).
    private let pullPageSize = 1000
    /// Hard stop on pages per sync pass; guards against a stuck has_more.
    private let pullMaxPages = 500
    /// The paginated pull_golf_records overload may not be deployed yet. When
    /// the backend reports an unknown function, fall back to the legacy call.
    private var pullPaginationAvailable = true

    private func fetchPullPage(_ scoped: SupabaseClient, after: Int) async throws -> PullPage {
        if pullPaginationAvailable {
            struct Params: Encodable { var after_cursor: Int; var page_limit: Int }
            do {
                let response = try await scoped.rpc("pull_golf_records",
                    params: Params(after_cursor: after, page_limit: pullPageSize)).execute()
                return try await Task.detached(priority: .utility) {
                    try JSONDecoder().decode(PullPage.self, from: response.data)
                }.value
            } catch {
                guard String(describing: error).contains("Could not find the function") else { throw error }
                pullPaginationAvailable = false
            }
        }
        struct LegacyParams: Encodable { var after_cursor: Int }
        let response = try await scoped.rpc("pull_golf_records",
            params: LegacyParams(after_cursor: after)).execute()
        let legacy = try await Task.detached(priority: .utility) {
            try JSONDecoder().decode(LegacyPullPage.self, from: response.data)
        }.value
        return PullPage(cursor: legacy.cursor, end_cursor: nil, has_more: nil, records: legacy.records)
    }

    private func syncedStatus() -> String {
        store.cloudErrorDetail = nil
        return store.cloudSkippedRecords == 0 ? "Golf data synced"
            : "Golf data synced · \(store.cloudSkippedRecords) backend record(s) skipped — update the app to display them"
    }

    func sync() async {
        guard let client = PinpointSupabase.client else {
            if store.accountID != nil { store.cloudErrorDetail = "Cloud sync isn't configured on this build — add the Supabase URL and anon key, then rebuild." }
            return
        }
        guard let account = store.accountID else { return }
        guard store.localStorageHealthy else {
            store.cloudErrorDetail = store.lastError ?? "Local golf data couldn't be read. Your files have been kept."
            return
        }
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
                // Page through pull_golf_records following has_more. A single
                // full-history pull times out server-side (Postgres 57014) once
                // an account accumulates enough rows, and every retry re-attempts
                // the same giant pull, so sync can never progress.
                var afterCursor = checkpoint.cursor
                var pulled: [GolfRecord] = []
                var serverCursor = checkpoint.cursor
                var pages = 0
                while true {
                    let page = try await fetchPullPage(scoped, after: afterCursor)
                    guard run == epoch, store.accountID == account, client.auth.currentUser?.id == account else { return }
                    pulled.append(contentsOf: page.records)
                    serverCursor = page.cursor
                    afterCursor = page.end_cursor ?? serverCursor
                    pages += 1
                    if page.has_more != true || pages >= pullMaxPages { break }
                    try Task.checkCancellation()
                }
                let delta = GolfRecordCheckpoint(cursor: serverCursor, records: pulled)
                guard run == epoch, store.accountID == account, client.auth.currentUser?.id == account else { return }
                if delta.records.isEmpty, lastSyncedGeneration == store.dataGeneration {
                    store.cloudStatus = syncedStatus()
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
                    store.cloudStatus = syncedStatus()
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
            store.cloudErrorDetail = GolfSyncFailure.reason(for: error)
            store.cloudStatus = "Golf data saved locally · sync unavailable. We'll retry when connected."
        }
    }
    private enum SyncError: Error { case localWrite }
}
