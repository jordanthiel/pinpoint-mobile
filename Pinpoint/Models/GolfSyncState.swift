import Foundation
import CryptoKit

struct PracticeSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date().golfRoundedToMilliseconds
    var focus: String
    var made: Int
    var attempts: Int
    var note: String
}

struct GolfCloudState: Codable, Equatable {
    var rounds: [GolfRound]
    var bag: ClubBag
    var practice: [PracticeSession]
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rounds.sorted { $0.id.uuidString < $1.id.uuidString } == rhs.rounds.sorted { $0.id.uuidString < $1.id.uuidString }
        && lhs.bag.clubs.sorted { $0.id.uuidString < $1.id.uuidString } == rhs.bag.clubs.sorted { $0.id.uuidString < $1.id.uuidString }
        && lhs.practice.sorted { $0.id.uuidString < $1.id.uuidString } == rhs.practice.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    static var initialBag: ClubBag {
        var bag = ClubBag.standard
        for i in bag.clubs.indices {
            let slot = GolfClub.allCases.firstIndex(of: bag.clubs[i].club)! + 1
            bag.clubs[i].id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", slot))!
        }
        return bag
    }
    static var empty: Self { .init(rounds: [], bag: ClubBag(clubs: []), practice: []) }
}

/// Persisted before sending. Replayed with the same ID after a lost response or restart.
struct GolfPendingUpload: Codable {
    var id = UUID()
    var snapshot: GolfCloudState
    var changes: [GolfRecords.Change]
}

struct GolfLocalState: Codable {
    var data: GolfCloudState
    var activeID: UUID?
    var revision: Int = 0
    var base: GolfCloudState = .empty
    var checkpoint: GolfRecordCheckpoint?
    var pendingUpload: GolfPendingUpload?

    /// Disk is an outbox plus the on-course cache, never a mirror of history.
    /// Retain matching base entities for conflict resolution and deletions.
    func localCache() -> Self {
        func changedIDs<T: Identifiable & Equatable>(_ current: [T], _ previous: [T]) -> Set<T.ID> {
            let current = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            let previous = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
            return Set(current.keys).union(previous.keys).filter { current[$0] != previous[$0] }
        }
        let cachedActiveID = data.rounds.first { $0.id == activeID && $0.status == .active }?.id
            ?? data.rounds.filter { $0.status == .active }.max { $0.startedAt < $1.startedAt }?.id
        var roundIDs = changedIDs(data.rounds, base.rounds)
        if let cachedActiveID { roundIDs.insert(cachedActiveID) }
        var clubIDs = cachedActiveID == nil ? changedIDs(data.bag.clubs, base.bag.clubs)
            : Set(data.bag.clubs.map(\.id)).union(base.bag.clubs.map(\.id))
        var practiceIDs = changedIDs(data.practice, base.practice)
        if let pendingUpload {
            // An edit can revert to the old base while a different value is in
            // flight. Keep it until the receipt establishes the new base.
            roundIDs.formUnion(changedIDs(pendingUpload.snapshot.rounds, base.rounds))
            clubIDs.formUnion(changedIDs(pendingUpload.snapshot.bag.clubs, base.bag.clubs))
            practiceIDs.formUnion(changedIDs(pendingUpload.snapshot.practice, base.practice))
        }
        func filtered(_ source: GolfCloudState) -> GolfCloudState {
            .init(rounds: source.rounds.filter { roundIDs.contains($0.id) },
                  bag: ClubBag(clubs: source.bag.clubs.filter { clubIDs.contains($0.id) }),
                  practice: source.practice.filter { practiceIDs.contains($0.id) })
        }
        var cachedUpload = pendingUpload
        if let pendingUpload { cachedUpload?.snapshot = filtered(pendingUpload.snapshot) }
        return Self(data: filtered(data), activeID: cachedActiveID, base: filtered(base), pendingUpload: cachedUpload)
    }
}

/// Three-way merge: disjoint field/shot edits combine. Conflicting edits keep
/// the remote original plus a named local copy, never silently overwriting it.
enum GolfCloudMerge {
    static func merge(base: GolfCloudState, local: GolfCloudState, remote: GolfCloudState) throws -> GolfCloudState {
        let encoder = JSONEncoder()
        func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value)) }
        func same(_ a: Any?, _ b: Any?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (a?, b?): return NSDictionary(dictionary: ["v": a]).isEqual(to: ["v": b])
            default: return false
            }
        }
        func mergeValue(_ b: Any?, _ l: Any?, _ r: Any?, field: String = "", path: String = "", conflicts: inout Set<String>) -> Any? {
            if same(l, b) { return r }
            if same(r, b) || same(l, r) { return l }
            // Navigation and weather are live state, not competing score edits.
            if ["currentHoleNumber", "windMph", "windHelping", "windFromDegrees"].contains(field) { return l ?? r }
            if field == "courseWind", let l = l as? [String: Any], let r = r as? [String: Any] {
                return (l["observedAt"] as? Double ?? 0) > (r["observedAt"] as? Double ?? 0) ? l : r
            }
            if field == "locationSamples", let l = l as? [[String: Any]], let r = r as? [[String: Any]] {
                var keyed: [String: [String: Any]] = [:]
                for sample in r + l {
                    let key = String(Int(((sample["timestamp"] as? Double ?? 0) * 1000).rounded()))
                    if let old = keyed[key] {
                        let oldAccuracy = old["accuracy"] as? Double ?? .infinity
                        let newAccuracy = sample["accuracy"] as? Double ?? .infinity
                        if oldAccuracy < newAccuracy { continue }
                        if oldAccuracy == newAccuracy,
                           let oldData = try? JSONSerialization.data(withJSONObject: old, options: [.sortedKeys]),
                           let newData = try? JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys]),
                           oldData.lexicographicallyPrecedes(newData) { continue }
                    }
                    keyed[key] = sample
                }
                return Array(keyed.values.sorted { ($0["timestamp"] as? Double ?? 0) < ($1["timestamp"] as? Double ?? 0) }.suffix(720))
            }
            if field == "companionCommandIDs", let l = l as? [String], let r = r as? [String] {
                return Array(Set(l + r).sorted().suffix(128))
            }
            // Deletions win over offline edits; no deleted record resurrection.
            if b != nil && (l == nil || r == nil) { return nil }
            if let l = l as? [String: Any], let r = r as? [String: Any] {
                let b = b as? [String: Any] ?? [:]
                var result: [String: Any] = [:]
                for key in Set(b.keys).union(l.keys).union(r.keys) {
                    let child = path.isEmpty ? key : path + "." + key
                    result[key] = mergeValue(b[key], l[key], r[key], field: key, path: child, conflicts: &conflicts)
                }
                return result
            }
            if let l = l as? [[String: Any]], let r = r as? [[String: Any]],
               l.allSatisfy({ $0["id"] is String }), r.allSatisfy({ $0["id"] is String }) {
                let b = b as? [[String: Any]] ?? []
                func keyed(_ a: [[String: Any]]) -> [String: [String: Any]] {
                    a.reduce(into: [:]) { if let id = $1["id"] as? String { $0[id] = $1 } }
                }
                let bm = keyed(b), lm = keyed(l), rm = keyed(r)
                // Keep remote order, then locally added identities.
                let order = (r + l).compactMap { $0["id"] as? String }
                var seen = Set<String>()
                return order.filter { seen.insert($0).inserted }.compactMap {
                    mergeValue(bm[$0], lm[$0], rm[$0], path: path + "[" + ($0.prefix(8)) + "]", conflicts: &conflicts)
                }
            }
            conflicts.insert(path.isEmpty ? field : path)
            return r
        }
        func mergedRecords<T: Codable & Identifiable & Equatable>(_ b: [T], _ l: [T], _ r: [T], copy: (T, [String]) -> T) throws -> [T] where T.ID == UUID {
            let bm = Dictionary(b.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            let lm = Dictionary(l.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            let rm = Dictionary(r.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            var result: [T] = []
            for id in Set(bm.keys).union(lm.keys).union(rm.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
                // No common ancestor: the record is new since the base, so it
                // can only be our own uncommitted work (local is the descendant
                // of remote) or a remote add. Merging field-by-field against
                // nothing would mistake in-flight edits for conflicts and mint
                // copies every pass while the base lags, so take a side.
                guard bm[id] != nil else {
                    if let local = lm[id] { result.append(local) }
                    else if let remote = rm[id] { result.append(remote) }
                    continue
                }
                var conflicts = Set<String>()
                let value = mergeValue(try bm[id].map(object), try lm[id].map(object), try rm[id].map(object), conflicts: &conflicts)
                if let value {
                    result.append(try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value)))
                    if !conflicts.isEmpty, let local = lm[id] {
                        let preserved = copy(local, conflicts.sorted())
                        if lm[preserved.id] == nil && rm[preserved.id] == nil { result.append(preserved) }
                    }
                }
            }
            return result
        }
        func conflictID<T: Encodable>(_ value: T, kind: String) -> UUID {
            let stable = JSONEncoder(); stable.outputFormatting = [.sortedKeys]
            let bytes = Array(SHA256.hash(data: Data(kind.utf8) + (try! stable.encode(value))).prefix(16))
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        // Copy IDs derive from the record identity plus the conflicting field
        // paths — never the full local content, which drifts every pass (GPS
        // trail appends) and would otherwise mint a fresh copy per pass for
        // the same conflict. The same conflict therefore preserves exactly one
        // copy; a genuinely different conflict mints its own.
        func conflictSeed(id: UUID, paths: [String]) -> String { id.uuidString + "|" + paths.joined(separator: ",") }
        func conflictSummary(paths: [String]) -> String {
            let shown = paths.prefix(6).joined(separator: ", ")
            return paths.count > 6 ? shown + " (+\(paths.count - 6) more)" : shown
        }
        let rounds = try mergedRecords(base.rounds, local.rounds, remote.rounds) { original, paths in
            var copy = original; copy.id = conflictID(conflictSeed(id: original.id, paths: paths), kind: "round"); copy.courseName += " (conflict copy)"
            copy.status = .unfinished; copy.finishedAt = original.finishedAt ?? original.startedAt
            copy.recap = "Conflicting device edits were preserved in this copy.\nConflicting fields: " + conflictSummary(paths: paths) + "\n" + copy.recap
            return copy
        }
        let clubs = try mergedRecords(base.bag.clubs, local.bag.clubs, remote.bag.clubs) { original, paths in
            var copy = original; copy.id = conflictID(conflictSeed(id: original.id, paths: paths), kind: "club"); copy.nickname = original.fullLabel + " (conflict copy)"; return copy
        }
        let practice = try mergedRecords(base.practice, local.practice, remote.practice) { original, paths in
            var copy = original; copy.id = conflictID(conflictSeed(id: original.id, paths: paths), kind: "practice"); copy.note = "Conflicting device edits — review this copy.\nConflicting fields: " + conflictSummary(paths: paths) + "\n" + copy.note; return copy
        }
        return .init(rounds: rounds, bag: ClubBag(clubs: clubs), practice: practice)
    }
}

// Flat wire records keep typed database rows independent of the local document.
struct GolfRecord: Codable, Equatable {
    var kind: String
    var id: UUID
    var round_id: UUID?
    var hole_id: UUID?
    var position: Int
    var revision: Int
    var deleted: Bool
    var data: [String: GolfJSON]
    var key: String { "\(kind):\(round_id?.uuidString ?? ""):\(id.uuidString)" }
}
struct GolfRecordCheckpoint: Codable, Equatable {
    var cursor: Int
    var records: [GolfRecord]
    mutating func apply(_ delta: Self) {
        var indexed = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
        for record in delta.records { indexed[record.key] = record }
        records = indexed.values.sorted { $0.key < $1.key }; cursor = delta.cursor
    }
}
indirect enum GolfJSON: Codable, Equatable {
    case object([String: GolfJSON]), array([GolfJSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
enum GolfRecords {
    struct Change: Codable {
        var kind: String; var id: UUID; var round_id: UUID?; var hole_id: UUID?
        var position: Int; var expected_revision: Int; var deleted: Bool
        var data: [String: GolfJSON]
        init(_ row: GolfRecord, expected: Int) {
            kind = row.kind; id = row.id; round_id = row.round_id; hole_id = row.hole_id
            position = row.position; expected_revision = expected; deleted = row.deleted; data = row.data
        }
    }
    static func flatten(_ state: GolfCloudState) throws -> [GolfRecord] {
        var result: [GolfRecord] = []
        func append<T: Encodable>(_ value: T, kind: String, id: UUID, position: Int, round: UUID? = nil, hole: UUID? = nil, excluding: String? = nil) throws {
            var data = try JSONDecoder().decode([String: GolfJSON].self, from: JSONEncoder().encode(value))
            if let excluding { data.removeValue(forKey: excluding) }
            for key in ["startedAt", "finishedAt", "timestamp", "date"] {
                if case .number(let seconds) = data[key] { data[key] = .number((seconds * 1000).rounded() / 1000) }
            }
            result.append(.init(kind: kind, id: id, round_id: round, hole_id: hole, position: position, revision: 0, deleted: false, data: data))
        }
        // Root collections are unordered domain entities; stable positions avoid reorder writes after merges.
        for (i, round) in state.rounds.sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() {
            var roundFields = round
            roundFields.holeScores = []
            try append(roundFields, kind: "round", id: round.id, position: i, excluding: "holeScores")
            for (j, hole) in round.holeScores.enumerated() {
                var holeFields = hole
                holeFields.shots = []
                try append(holeFields, kind: "hole", id: hole.id, position: j, round: round.id, excluding: "shots")
                for (k, shot) in hole.shots.enumerated() {
                    try append(shot, kind: "shot", id: shot.id, position: k, round: round.id, hole: hole.id)
                }
            }
        }
        for (i, club) in state.bag.clubs.sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() { try append(club, kind: "club", id: club.id, position: i) }
        for (i, practice) in state.practice.sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() { try append(practice, kind: "practice", id: practice.id, position: i) }
        return result
    }
    /// Decodes pulled rows entity by entity. Rows this client cannot decode
    /// (values written by a newer/different writer) are reported as bad keys
    /// instead of failing the whole pull. Bad rows stay in the checkpoint
    /// verbatim: the client must neither display, modify, nor tombstone what
    /// it cannot understand. Children of a bad parent are bad too, so an
    /// orphaned hole or shot is never mistaken for a deletion.
    static func assembleTolerant(_ records: [GolfRecord]) -> (state: GolfCloudState, badKeys: Set<String>, firstErrors: [String]) {
        let live = records.filter { !$0.deleted }
        var bad = Set<String>()
        var errors: [String] = []
        func decode<T: Decodable>(_ type: T.Type, _ row: GolfRecord, _ data: [String: GolfJSON]) -> T? {
            guard let bytes = try? JSONEncoder().encode(GolfJSON.object(data)) else { return nil }
            do {
                return try JSONDecoder().decode(type, from: bytes)
            } catch {
                // Bounded, token-free reason so the device can report what's
                // missing instead of failing silently: kind, short id, fields.
                if errors.count < 4 {
                    let reason = String(describing: error).prefix(120).replacingOccurrences(of: "\n", with: " ")
                    errors.append("\(row.kind) \(row.id.uuidString.prefix(8)): \(reason)")
                }
                return nil
            }
        }
        /// Nullable backend text the client models require: a stripped null
        /// decodes as "" rather than skipping the whole row. Re-uploading ""
        /// over null is semantically identical, so this never destroys data.
        func defaulted(_ data: [String: GolfJSON], keys: String...) -> [String: GolfJSON] {
            var data = data
            for key in keys where data[key] == nil { data[key] = .string("") }
            return data
        }
        func holeKey(_ row: GolfRecord) -> String { "\(row.round_id?.uuidString ?? ""):\(row.id.uuidString)" }
        // Shots decode independently; orphans are excluded when the parent fails.
        var shotsByHole: [String: [(position: Int, shot: TrackedShot)]] = [:]
        var shotKeysByHole: [String: [String]] = [:]
        for row in live where row.kind == "shot" {
            let parentKey = "\(row.round_id?.uuidString ?? ""):\(row.hole_id?.uuidString ?? "")"
            shotKeysByHole[parentKey, default: []].append(row.key)
            guard let shot: TrackedShot = decode(TrackedShot.self, row, defaulted(row.data, keys: "note")) else { bad.insert(row.key); continue }
            shotsByHole[parentKey, default: []].append((row.position, shot))
        }
        // Holes pick up their decoded shots.
        var holesByRound: [UUID: [(position: Int, hole: HoleScore)]] = [:]
        var descendantKeysByRound: [UUID: [String]] = [:]
        for row in live where row.kind == "hole" {
            guard let roundID = row.round_id else {
                bad.insert(row.key)
                bad.formUnion(shotKeysByHole[holeKey(row)] ?? [])
                continue
            }
            descendantKeysByRound[roundID, default: []].append(row.key)
            descendantKeysByRound[roundID, default: []].append(contentsOf: shotKeysByHole[holeKey(row)] ?? [])
            var data = defaulted(row.data, keys: "dictateTranscript")
            data["shots"] = .array([])
            guard var hole: HoleScore = decode(HoleScore.self, row, data) else {
                bad.insert(row.key)
                bad.formUnion(shotKeysByHole[holeKey(row)] ?? [])
                continue
            }
            hole.shots = (shotsByHole[holeKey(row)] ?? []).sorted { $0.position < $1.position }.map { $0.shot }
            holesByRound[roundID, default: []].append((row.position, hole))
        }
        // Rounds pick up their decoded holes.
        var rounds: [(position: Int, round: GolfRound)] = []
        for row in live where row.kind == "round" {
            var data = defaulted(row.data, keys: "recap", "courseRating")
            data["holeScores"] = .array([])
            guard var round: GolfRound = decode(GolfRound.self, row, data) else {
                bad.insert(row.key)
                bad.formUnion(descendantKeysByRound[row.id] ?? [])
                continue
            }
            round.holeScores = (holesByRound[row.id] ?? []).sorted { $0.position < $1.position }.map { $0.hole }
            rounds.append((row.position, round))
        }
        var clubs: [(position: Int, club: ClubBagEntry)] = []
        for row in live where row.kind == "club" {
            guard let club: ClubBagEntry = decode(ClubBagEntry.self, row, row.data) else { bad.insert(row.key); continue }
            clubs.append((row.position, club))
        }
        var practice: [(position: Int, session: PracticeSession)] = []
        for row in live where row.kind == "practice" {
            guard let session: PracticeSession = decode(PracticeSession.self, row, row.data) else { bad.insert(row.key); continue }
            practice.append((row.position, session))
        }
        let state = GolfCloudState(
            rounds: rounds.sorted { $0.position < $1.position }.map { $0.round },
            bag: ClubBag(clubs: clubs.sorted { $0.position < $1.position }.map { $0.club }),
            practice: practice.sorted { $0.position < $1.position }.map { $0.session })
        return (state, bad, errors)
    }
    static func assemble(_ records: [GolfRecord]) throws -> GolfCloudState {
        let rows = records.filter { !$0.deleted }.sorted { $0.position == $1.position ? $0.key < $1.key : $0.position < $1.position }
        let holesByRound = Dictionary(grouping: rows.filter { $0.kind == "hole" }, by: \.round_id)
        func parentKey(_ row: GolfRecord) -> String { "\(row.round_id?.uuidString ?? ""):\(row.hole_id?.uuidString ?? "")" }
        let shotsByHole = Dictionary(grouping: rows.filter { $0.kind == "shot" }, by: parentKey)
        let rounds = rows.filter { $0.kind == "round" }.map { round -> GolfJSON in
            var data = round.data
            data["holeScores"] = .array((holesByRound[round.id] ?? []).map { hole in
                var data = hole.data
                data["shots"] = .array((shotsByHole["\(round.id.uuidString):\(hole.id.uuidString)"] ?? []).map { .object($0.data) })
                return .object(data)
            })
            return .object(data)
        }
        let object: GolfJSON = .object(["rounds": .array(rounds), "bag": .object(["clubs": .array(rows.filter { $0.kind == "club" }.map { .object($0.data) })]), "practice": .array(rows.filter { $0.kind == "practice" }.map { .object($0.data) })])
        return try JSONDecoder().decode(GolfCloudState.self, from: JSONEncoder().encode(object))
    }
    static func removingTombstones(from state: GolfCloudState, mirror: [GolfRecord]) throws -> GolfCloudState {
        let deleted = Set(mirror.filter(\.deleted).map(\.key))
        return try assemble(flatten(state).filter { !deleted.contains($0.key) })
    }
    static func changes(local: GolfCloudState, mirror: [GolfRecord], excluding: Set<String> = []) throws -> [Change] {
        let current = try flatten(local)
        let old = Dictionary(uniqueKeysWithValues: mirror.map { ($0.key, $0) })
        let keys = Set(current.map(\.key))
        var changes = current.compactMap { row -> Change? in
            if let before = old[row.key], before.deleted || (before.data == row.data && before.hole_id == row.hole_id && before.position == row.position) { return nil }
            return Change(row, expected: old[row.key]?.revision ?? 0)
        }
        // Rows the client cannot decode stay untouched: a missing local copy
        // is an understanding gap, never evidence of a deletion.
        for var row in mirror where !row.deleted && !keys.contains(row.key) && !excluding.contains(row.key) {
            row.deleted = true; row.data = [:]; changes.append(Change(row, expected: row.revision))
        }
        return changes
    }
}

/// Pure reconciliation runs off the UI actor, including JSON conversion and the
/// potentially large local checkpoint encoding.
/// Client-side timeout for sync network calls. A hung request must fail
/// visibly instead of spinning the UI forever.
enum GolfSyncTimeout: Error { case timedOut }

/// Races `operation` against a sleep. Pure Foundation so it is unit-testable.
func withGolfSyncTimeout<T>(seconds: Int, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)
            throw GolfSyncTimeout.timedOut
        }
        guard let result = try await group.next() else { throw CancellationError() }
        group.cancelAll()
        return result
    }
}

/// Human-readable sync failure reasons. Pure Foundation so the mapping is
/// unit-testable; never includes tokens or credentials.
enum GolfSyncFailure {
    static func reason(for error: Error) -> String {
        if error is GolfSyncTimeout {
            return "The backend timed out — rounds stay saved on this device. Try Sync now."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No connection — pending changes stay saved on this device. Reconnect to load your rounds."
            case .timedOut:
                return "The backend timed out — pending changes stay saved on this device. Try again."
            default:
                break
            }
        }
        if error is DecodingError {
            return "The backend sent a response this build can't read — update the app, then Sync now."
        }
        let details = String(describing: error).lowercased()
        func has(_ words: String...) -> Bool { words.contains { details.contains($0) } }
        if has("not connected", "offline", "network", "timed out", "connection lost", "connection reset", "broken pipe", "could not connect") {
            return "No connection — pending changes stay saved on this device. Reconnect to load your rounds."
        }
        if has("57014", "statement timeout", "canceling statement") {
            return "The backend timed out — pending changes stay saved on this device. Try again."
        }
        if has("refresh token", "session expired", "session missing", "invalid jwt", "jwt expired", "user not found") {
            return "Sign-in expired — sign out and back in, then Sync now."
        }
        if (has("function") && has("does not exist", "not find", "could not find"))
            || has("42883", "schema cache", "pgrst202", "not found", "404") {
            return "The backend is missing golf sync — apply the Supabase migrations to the linked project, then Sync now."
        }
        if has("401", "unauthorized", "403", "forbidden", "permission denied", "42501", "violates row-level", "restricts") {
            return "The backend refused the request — sign out and back in. If it persists, check the project's migrations and RLS."
        }
        let snippet = String(String(describing: error).prefix(160))
        return "Sync failed — \(snippet)"
    }
}

struct GolfPreparedSync {
    var merged: GolfCloudState
    var remote: GolfCloudState
    var checkpoint: GolfRecordCheckpoint
    var changes: [GolfRecords.Change]
    var encodedState: Data
    var activeID: UUID?
    var dataChanged: Bool
    /// Checkpoint keys the client could not decode. They ride along verbatim
    /// in the checkpoint and are excluded from uploads, so one unreadable row
    /// can no longer block every other round from syncing.
    var undecodableKeys: Set<String>
    /// Human-readable account of skipped rows for the device to display.
    /// Nil when every pulled row decoded.
    var skipReport: String?

    static func prepare(local data: GolfCloudState, base: GolfCloudState, checkpoint: GolfRecordCheckpoint,
                        activeID: UUID?) throws -> Self {
        let (remote, undecodableKeys, skipErrors) = GolfRecords.assembleTolerant(checkpoint.records)
        let local = try GolfRecords.removingTombstones(from: data, mirror: checkpoint.records)
        let normalizedBase = try GolfRecords.assemble(GolfRecords.flatten(base))
        var merged: GolfCloudState
        if local == normalizedBase { merged = remote }
        else if remote == normalizedBase || local == remote { merged = local }
        else { merged = try GolfCloudMerge.merge(base: normalizedBase, local: local, remote: remote) }
        if merged.bag.clubs.isEmpty && remote.bag.clubs.isEmpty && base.bag.clubs.isEmpty && !checkpoint.records.contains(where: { $0.kind == "club" }) {
            merged.bag = GolfCloudState.initialBag
        }
        // The persisted base stays at the just-pulled remote: it only advances
        // to the merged state once the commit below succeeds (see
        // advanceCloudBase). The disk filter keeps this snapshot outbox-only.
        let state = GolfLocalState(data: merged, activeID: activeID, revision: checkpoint.cursor, base: remote, checkpoint: checkpoint)
        let skipReport = skipErrors.isEmpty ? nil
            : "Skipped \(undecodableKeys.count) backend record(s): " + skipErrors.joined(separator: "; ")
        return Self(merged: merged, remote: remote, checkpoint: checkpoint,
                    changes: try GolfRecords.changes(local: merged, mirror: checkpoint.records, excluding: undecodableKeys),
                    encodedState: try JSONEncoder().encode(state.localCache()), activeID: activeID, dataChanged: merged != data,
                    undecodableKeys: undecodableKeys, skipReport: skipReport)
    }
}

/// Debouncing owns only the pending delay. Network work has its own task so
/// rescheduling or cancelling a SwiftUI caller cannot cancel an active pull.
@MainActor
final class GolfSyncScheduler {
    private var pending: Task<Void, Never>?
    private var active: Task<Void, Never>?
    private var requested = false
    private let delay: Duration

    init(delay: Duration = .seconds(1)) { self.delay = delay }

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        if active != nil { requested = true; return }
        guard pending == nil else { return } // Continuous edits must not postpone uploads forever.
        pending = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            await run(operation)
        }
    }

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        if let active {
            requested = true
            await active.value
            return
        }
        pending?.cancel()
        pending = nil
        let task = Task {
            await operation()
            active = nil
            if requested {
                requested = false
                schedule(operation)
            }
        }
        active = task
        await task.value
    }
}
