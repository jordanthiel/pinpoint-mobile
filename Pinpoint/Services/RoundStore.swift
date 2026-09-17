import Foundation

/// Cloud responses live in memory. Disk holds the active round and pending
/// mutations so play can continue through poor connectivity.
@Observable
final class RoundStore {
    @ObservationIgnored private(set) var dataGeneration: UInt64 = 0
    var activeRound: GolfRound? { didSet { dataGeneration &+= 1 } }
    var pastRounds: [GolfRound] = [] { didSet { dataGeneration &+= 1; historyGeneration &+= 1 } }
    var clubBag: ClubBag = .standard { didSet { dataGeneration &+= 1; historyGeneration &+= 1 } }
    var lastError: String?

    let watchDetector = WatchShotDetector()

    @ObservationIgnored private var historyGeneration: UInt64 = 0
    @ObservationIgnored private var persistedHistoryGeneration: UInt64 = 0
    @ObservationIgnored private var persistedActiveID: UUID?
    @ObservationIgnored var lastLocationEvaluation = Date.distantPast
    @ObservationIgnored private let persistenceQueue = DispatchQueue(label: "pinpoint.golf.persistence", qos: .utility)
    @ObservationIgnored private var lastTrailSync = Date.distantPast
    private let fileManager = FileManager.default
    private var isApplyingRecap = false
    private let storageDirectory: URL?

    private(set) var localStorageHealthy = true
    private(set) var accountID: UUID?
    var practiceSessions: [PracticeSession] = [] { didSet { dataGeneration &+= 1; historyGeneration &+= 1 } }
    var cloudStatus = "Sign in to sync golf data"
    var cloudSyncing = false
    var cloudHistoryLoaded = false
    /// Backend rows the last sync could not decode (left untouched server-side).
    var cloudSkippedRecords = 0
    /// Why the last sync failed, when it did. Cleared on the next success.
    var cloudErrorDetail: String?
    /// Which backend rows the last sync skipped, when any did.
    var cloudSkipReport: String?
    @ObservationIgnored var onLocalChange: (() -> Void)?
    private(set) var pendingUpload: GolfPendingUpload?
    private(set) var cloudCheckpoint: GolfRecordCheckpoint?
    private(set) var cloudRevision = 0
    private(set) var cloudBase: GolfCloudState = .empty

    private var baseURL: URL {
        storageDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinpoint", isDirectory: true)
    }
    private var ownerURL: URL { baseURL.appendingPathComponent("golf-legacy-owner.json") }
    private var rootURL: URL {
        let url: URL
        if let accountID { url = baseURL.appendingPathComponent("accounts/" + accountID.uuidString.lowercased()) }
        else if fileManager.fileExists(atPath: ownerURL.path) { url = baseURL.appendingPathComponent("guest") }
        else { url = baseURL }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var stateURL: URL { rootURL.appendingPathComponent("golf-state.json") }
    var cloudData: GolfCloudState {
        .init(rounds: (activeRound.map { [$0] } ?? []) + pastRounds, bag: clubBag, practice: practiceSessions)
    }

    private var roundsURL: URL { rootURL.appendingPathComponent("rounds.json") }
    private var activeURL: URL { rootURL.appendingPathComponent("active-round.json") }
    private var bagURL: URL { rootURL.appendingPathComponent("club-bag.json") }

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
        load()
    }

    /// Navigation retains identity, never a snapshot of cloud data.
    func round(id: UUID?) -> GolfRound? {
        guard let id else { return activeRound ?? pastRounds.first }
        if activeRound?.id == id { return activeRound }
        return pastRounds.first { $0.id == id }
    }

    // MARK: - Persistence

    func load() {
        persistenceQueue.sync {} // Drain older GPS snapshots before reading or switching accounts.
        localStorageHealthy = true
        cloudSkippedRecords = 0
        cloudHistoryLoaded = false
        cloudErrorDetail = nil
        cloudSkipReport = nil
        activeRound = nil; pastRounds = []; practiceSessions = []
        cloudRevision = 0; cloudBase = .empty; cloudCheckpoint = nil; pendingUpload = nil
        if fileManager.fileExists(atPath: stateURL.path) {
            do {
                var state = try JSONDecoder().decode(GolfLocalState.self, from: Data(contentsOf: stateURL))
                let journal = stateURL.appendingPathExtension("round")
                if fileManager.fileExists(atPath: journal.path) {
                    let canonicalDate = try stateURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                    let journalDate = try journal.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                    if journalDate >= canonicalDate {
                        let round = try JSONDecoder().decode(GolfRound.self, from: Data(contentsOf: journal))
                        if round.id == state.activeID, let index = state.data.rounds.firstIndex(where: { $0.id == round.id }) { state.data.rounds[index] = round }
                    }
                }
                // Migrate old full-history caches without dropping unsent edits.
                pendingUpload = state.pendingUpload
                state = state.localCache()
                try writeState(state, to: stateURL)
                install(state.data, activeID: state.activeID)
                cloudRevision = state.revision; cloudBase = state.base; cloudCheckpoint = state.checkpoint
                persistedHistoryGeneration = historyGeneration; persistedActiveID = activeRound?.id
            } catch { localStorageHealthy = false; lastError = "Couldn't read saved golf data. Your files have been kept." }
            return
        }
        clubBag = .standard
        if let data = try? Data(contentsOf: roundsURL),
           let decoded = try? JSONDecoder().decode([GolfRound].self, from: data) {
            pastRounds = decoded.sorted { $0.startedAt > $1.startedAt }
        }
        if let data = try? Data(contentsOf: activeURL),
           let decoded = try? JSONDecoder().decode(GolfRound.self, from: data),
           decoded.status == .active, !pastRounds.contains(where: { $0.id == decoded.id }) {
            activeRound = decoded
        }
        if let data = try? Data(contentsOf: bagURL),
           let decoded = try? JSONDecoder().decode(ClubBag.self, from: data),
           !decoded.clubs.isEmpty {
            clubBag = decoded
        } else {
            clubBag = .standard
        }
        if accountID == nil, !fileManager.fileExists(atPath: ownerURL.path),
           let data = UserDefaults.standard.data(forKey: "pinpoint.practice.sessions"),
           let decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
            practiceSessions = decoded
        }
    }

    private func replaceBag(_ bag: ClubBag) {
        let previous = clubBag
        clubBag = bag
        if !save() { clubBag = previous }
    }

    private func install(_ data: GolfCloudState, activeID: UUID?) {
        let chosen = data.rounds.first { $0.id == activeID && $0.status == .active }
            ?? data.rounds.filter { $0.status == .active }.sorted { $0.startedAt > $1.startedAt }.first
        activeRound = chosen
        pastRounds = data.rounds.filter { $0.id != chosen?.id }.sorted { $0.startedAt > $1.startedAt }
        clubBag = data.bag
        practiceSessions = data.practice.sorted { $0.date > $1.date }
    }

    @discardableResult
    func selectAccount(_ id: UUID?) -> Bool {
        guard id != accountID else { return true }
        let previousID = accountID
        let previous = GolfLocalState(data: cloudData, activeID: activeRound?.id, revision: cloudRevision, base: cloudBase, checkpoint: cloudCheckpoint)
        let migrate = id != nil && previousID == nil && !fileManager.fileExists(atPath: ownerURL.path)
        accountID = id
        if migrate && !fileManager.fileExists(atPath: stateURL.path) {
            var data = previous.data
            // A fresh installation's random default club IDs must not duplicate
            // the existing account bag. Only import a bag that was customized.
            let standard = ClubBag.standard
            let customized = data.bag.clubs.count != standard.clubs.count || data.bag.clubs.contains { entry in
                entry.nickname != nil || standard.carry(for: entry.club) != entry.carryYards
            }
            if !customized { data.bag = ClubBag(clubs: []) }
            do {
                try JSONEncoder().encode(GolfLocalState(data: data, activeID: previous.activeID)).write(to: stateURL, options: [.atomic])
                try JSONEncoder().encode(id).write(to: ownerURL, options: [.atomic])
            } catch {
                accountID = previousID; install(previous.data, activeID: previous.activeID)
                lastError = "Couldn't prepare your account's golf data."; return false
            }
        }
        if migrate && !fileManager.fileExists(atPath: ownerURL.path) {
            do { try JSONEncoder().encode(id).write(to: ownerURL, options: [.atomic]) }
            catch { accountID = previousID; lastError = "Couldn't assign local golf data to this account."; return false }
        }
        if id != nil && !fileManager.fileExists(atPath: stateURL.path) {
            do { try JSONEncoder().encode(GolfLocalState(data: .empty, activeID: nil)).write(to: stateURL, options: [.atomic]) }
            catch { accountID = previousID; lastError = "Couldn't open account storage."; return false }
        }
        load()
        notifyRoundEnded() // Also refresh companion/live activity state when the account changes.
        return localStorageHealthy
    }

    @discardableResult
    func applyCloud(_ data: GolfCloudState, revision: Int, base: GolfCloudState, checkpoint: GolfRecordCheckpoint? = nil) -> Bool {
        if data == cloudData && revision == cloudRevision && base == cloudBase && checkpoint == cloudCheckpoint { return true }
        let state = GolfLocalState(data: data, activeID: activeRound?.id, revision: revision, base: base, checkpoint: checkpoint)
        do { try writeState(state, to: stateURL) }
        catch { lastError = "Couldn't save pending golf changes."; return false }
        install(data, activeID: state.activeID)
        cloudRevision = revision; cloudBase = base; cloudCheckpoint = checkpoint
        notifyRoundEnded()
        return true
    }

    enum PreparedCloudResult { case applied, superseded, failed }

    /// The worker already encoded the snapshot. Await ordered IO without blocking
    /// gestures, and never install a snapshot superseded by edits during the wait.
    @MainActor
    func applyPreparedCloud(_ prepared: GolfPreparedSync, expectedGeneration: UInt64, owner: UUID?) async -> PreparedCloudResult {
        guard dataGeneration == expectedGeneration, accountID == owner, pendingUpload == nil else { return .superseded }
        let destination = stateURL
        let encodedState = prepared.encodedState
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                persistenceQueue.async {
                    do {
                        try encodedState.write(to: destination, options: [.atomic])
                        try? FileManager.default.removeItem(at: destination.appendingPathExtension("round"))
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } catch {
            if accountID == owner { lastError = "Couldn't save pending golf changes." }
            return .failed
        }
        guard dataGeneration == expectedGeneration, accountID == owner, pendingUpload == nil else { return .superseded }
        cloudSkippedRecords = prepared.undecodableKeys.count
        cloudSkipReport = prepared.skipReport
        if prepared.dataChanged {
            install(prepared.merged, activeID: prepared.activeID)
            notifyRoundEnded()
        }
        cloudRevision = prepared.checkpoint.cursor
        cloudBase = prepared.remote
        cloudCheckpoint = prepared.checkpoint
        persistedHistoryGeneration = historyGeneration; persistedActiveID = activeRound?.id
        return .applied
    }

    /// A receipt acknowledges the submitted snapshot, even if newer edits now
    /// exist. Persist those edits against that baseline before releasing the batch.
    @discardableResult
    func advanceCloudBase(to merged: GolfCloudState, owner: UUID?) -> Bool {
        guard accountID == owner else { return false }
        return persistUploadState(base: merged, pending: pendingUpload)
    }

    func enqueueUpload(_ upload: GolfPendingUpload, owner: UUID?) -> Bool {
        guard accountID == owner, pendingUpload == nil else { return false }
        return persistUploadState(base: cloudBase, pending: upload)
    }

    func resolveUpload(id: UUID, accepted: Bool, owner: UUID?) -> Bool {
        guard accountID == owner, let pending = pendingUpload, pending.id == id else { return false }
        return persistUploadState(base: accepted ? pending.snapshot : cloudBase, pending: nil)
    }

    private func persistUploadState(base: GolfCloudState, pending: GolfPendingUpload?) -> Bool {
        let previous = pendingUpload
        pendingUpload = pending
        let state = GolfLocalState(data: cloudData, activeID: activeRound?.id,
                                   revision: cloudRevision, base: base, checkpoint: cloudCheckpoint)
        do { try writeState(state, to: stateURL) }
        catch {
            pendingUpload = previous
            lastError = "Couldn't save the upload acknowledgement. Your pending changes have been kept."
            return false
        }
        cloudBase = base
        persistedHistoryGeneration = historyGeneration; persistedActiveID = activeRound?.id
        return true
    }

    @discardableResult
    func savePracticeSession(_ session: PracticeSession) -> Bool {
        let previous = practiceSessions
        practiceSessions.insert(session, at: 0)
        guard save() else { practiceSessions = previous; return false }
        return true
    }

    func resumeRound(_ id: UUID) {
        guard let index = pastRounds.firstIndex(where: { $0.id == id && $0.status == .active }) else { return }
        let selected = pastRounds.remove(at: index)
        if let activeRound { pastRounds.insert(activeRound, at: 0) }
        activeRound = selected
        _ = save()
    }

    func setBagCarry(_ club: GolfClub, yards: Double) {
        var bag = clubBag
        bag.upsert(club, carryYards: yards)
        replaceBag(bag)
    }

    func updateBagEntry(_ entry: ClubBagEntry) {
        var bag = clubBag
        bag.update(entry)
        replaceBag(bag)
    }

    func addClubToBag(_ club: GolfClub, nickname: String? = nil, yards: Double? = nil) {
        var bag = clubBag
        bag.add(club, nickname: nickname, carryYards: yards)
        replaceBag(bag)
    }

    func removeClubFromBag(_ club: GolfClub) {
        var bag = clubBag
        bag.remove(club)
        replaceBag(bag)
    }

    func removeBagEntry(id: UUID) {
        var bag = clubBag
        bag.remove(id: id)
        replaceBag(bag)
    }

    func resetClubBag() {
        replaceBag(.standard)
    }

    func bagCarry(for club: GolfClub) -> Double {
        clubBag.carry(for: club) ?? club.stockYards
    }

    @discardableResult
    func assignNFCTag(_ tag: String?, to entryID: UUID) -> Bool {
        guard let index = clubBag.clubs.firstIndex(where: { $0.id == entryID }) else { return false }
        if let tag, clubBag.clubs.contains(where: { $0.id != entryID && $0.nfcTagID == tag }) {
            lastError = "That tag is already assigned to another club. Unlink it in My Bag first."
            return false
        }
        let previous = clubBag
        clubBag.clubs[index].nfcTagID = tag
        guard save() else { clubBag = previous; return false }
        return true
    }

    /// A deliberate scan records one origin. Location estimates remain editable;
    /// scores and measured carry are never manufactured from the scan.
    func logNFCShot(tag: String, roundID: UUID, hole number: Int, phonePoint: GeoPoint?, now: Date = Date()) -> TrackedShot? {
        guard let round = activeRound, round.id == roundID, let hole = round.score(for: number) else { return nil }
        let matches = clubBag.clubs.filter { $0.nfcTagID == tag }
        guard matches.count == 1, let entry = matches.first else {
            lastError = matches.isEmpty ? "Unknown tag. Assign it to a club in My Bag first." : "This tag matches multiple clubs. Update its assignment in My Bag."
            return nil
        }
        if let last = hole.shots.last, last.nfcTagID == tag, now.timeIntervalSince(last.timestamp) < 10 {
            lastError = "This club was just logged. Wait a moment before scanning it for another shot."
            return nil
        }
        let layout = round.playLayout(for: number)
        let gps = phonePoint.flatMap { p in layout?.isStandingOnHole(p) == true ? p : nil }
        let swing = (round.swingCandidates ?? []).filter {
            $0.hole == number && $0.state == .pending && abs(now.timeIntervalSince($0.timestamp)) <= 20 &&
            ($0.accuracy ?? .infinity) <= 20 && $0.latitude != nil && $0.longitude != nil
        }.max { $0.timestamp < $1.timestamp }
        let watchPoint = swing.flatMap { event -> GeoPoint? in
            let p = GeoPoint(latitude: event.latitude!, longitude: event.longitude!)
            return layout?.isStandingOnHole(p) == true && (gps.map { $0.yards(to: p) <= 30 } ?? true) ? p : nil
        }
        let fallback = suggestedStop(number) ?? round.teeCoordinate(for: number)
        guard let point = watchPoint ?? gps ?? fallback else { lastError = "No location available. Add this shot on the map."; return nil }
        let origin = watchPoint != nil ? "detected swing" : gps != nil ? "phone GPS" : "estimated location — review on map"
        var shot = TrackedShot(number: (hole.shots.map(\.number).max() ?? 0) + 1, club: entry.club,
            lie: entry.club.isPutter ? .green : hole.shots.isEmpty ? .tee : .fairway,
            start: point, includeInTrueDistance: false, timestamp: now,
            note: "NFC · \(entry.fullLabel) · \(origin)")
        shot.nfcTagID = tag; shot.bagEntryID = entry.id; shot.lieWasInferred = true
        guard let holeIndex = round.holeScores.firstIndex(where: { $0.holeNumber == number }) else { return nil }
        var updated = round
        updated.holeScores[holeIndex].shots.append(shot)
        refreshMappedDistances(&updated.holeScores[holeIndex], pin: round.pinCoordinate(for: number))
        if watchPoint != nil, let swing, let index = updated.swingCandidates?.firstIndex(where: { $0.id == swing.id }) {
            updated.swingCandidates?[index].state = .confirmed
        }
        activeRound = updated
        guard save() else { activeRound = round; return nil }
        return shot
    }

    func updateWind(_ wind: CourseWind, roundID: UUID) {
        guard var round = activeRound, round.id == roundID, round.courseWind != wind else { return }
        let previous = round
        round.courseWind = wind
        round.windMph = wind.mph
        round.windFromDegrees = wind.fromDegrees ?? 0
        activeRound = round
        if !save() { activeRound = previous }
    }

    @discardableResult
    private func save() -> Bool {
        guard localStorageHealthy else { return false }
        if isApplyingRecap { return true }
        do {
            let state = GolfLocalState(data: cloudData, activeID: activeRound?.id, revision: cloudRevision, base: cloudBase, checkpoint: cloudCheckpoint)
            if let round = activeRound, persistedActiveID == round.id, persistedHistoryGeneration == historyGeneration {
                let destination = stateURL
                try persistenceQueue.sync { try Self.writeRoundJournal(round, to: destination) }
            } else {
                try writeState(state, to: stateURL)
                persistedHistoryGeneration = historyGeneration; persistedActiveID = activeRound?.id
            }
            onLocalChange?()
            #if !PINPOINT_STORE_SMOKE
            NotificationCenter.default.post(name: .pinpointRoundChanged, object: nil)
            #endif
            return true
        } catch {
            lastError = "Couldn't save your rounds."
            return false
        }
    }

    /// All canonical writes share an ordered queue: an older background GPS
    /// snapshot can never overwrite a newer score edit or cloud checkpoint.
    private func writeState(_ state: GolfLocalState, to url: URL) throws {
        var state = state
        state.pendingUpload = pendingUpload
        try persistenceQueue.sync {
            try JSONEncoder().encode(state.localCache()).write(to: url, options: [.atomic])
            try? FileManager.default.removeItem(at: url.appendingPathExtension("round"))
        }
    }

    /// Small durable round journal: GPS and score edits never re-encode history or cloud checkpoints.
    private static func writeRoundJournal(_ round: GolfRound, to canonical: URL) throws {
        guard try canonical.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CocoaError(.fileWriteUnknown) }
        try JSONEncoder().encode(round).write(to: canonical.appendingPathExtension("round"), options: [.atomic])
    }

    func saveLocationSample(_ sample: GolfLocationSample, hole number: Int) {
        guard localStorageHealthy, var round = activeRound,
              let index = round.holeScores.firstIndex(where: { $0.holeNumber == number }) else { return }
        round.holeScores[index].locationSamples = Array(((round.holeScores[index].locationSamples ?? []) + [sample]).suffix(720))
        activeRound = round
        let destination = stateURL
        let owner = accountID
        let shouldSync = sample.timestamp.timeIntervalSince(lastTrailSync) >= 30
        if shouldSync { lastTrailSync = sample.timestamp }
        persistenceQueue.async { [weak self] in
            do {
                try Self.writeRoundJournal(round, to: destination)
                if shouldSync {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.accountID == owner else { return }
                        self.onLocalChange?()
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.accountID == owner else { return }
                    self.lastError = "Couldn't save the location trail."
                }
            }
        }
    }

    // MARK: - Round lifecycle

    func startRound(course: GolfCourse, teeName: String, roundType: RoundType,
                   scoringMode: ScoringMode, startHole: Int = 1) {
        let round = GolfRound(course: course, teeName: teeName, roundType: roundType,
                              scoringMode: scoringMode, startHole: startHole)
        // Holes start empty; the GPS view seeds distance-to-pin from each
        // hole's yardage until the golfer adds, claims, or dictates shots.
        let previous = activeRound
        activeRound = round
        if !save() { activeRound = previous }
    }

    @discardableResult
    func finishRound(saveAsNine: Bool = false, recap: String? = nil) -> Bool {
        guard var round = activeRound else { return false }
        if saveAsNine {
            guard let numbers = round.nineHoleNumbers else { lastError = "Score exactly nine holes first."; return false }
            round.savedHoleNumbers = numbers
            if Set(numbers) == Set(1...9) { round.roundType = .front9 }
            else if Set(numbers) == Set(10...18) { round.roundType = .back9 }
        }
        round.status = saveAsNine || round.holeScores.allSatisfy(\.hasScore) ? .finished : .unfinished
        round.finishedAt = Date().golfRoundedToMilliseconds
        if let recap { round.recap = recap }
        let previous = activeRound; let history = pastRounds
        pastRounds = [round] + pastRounds.filter { $0.id != round.id }
        activeRound = nil
        guard save() else { activeRound = previous; pastRounds = history; return false }
        return true
    }

    @discardableResult
    func discardActiveRound() -> Bool {
        guard let previous = activeRound else { return false }
        activeRound = nil
        guard save() else { activeRound = previous; return false }
        return true
    }

    @discardableResult
    func deleteRound(_ id: UUID) -> Bool {
        guard activeRound?.id == id || pastRounds.contains(where: { $0.id == id }) else { return false }
        let previous = activeRound; let history = pastRounds
        if activeRound?.id == id { activeRound = nil }
        pastRounds.removeAll { $0.id == id }
        guard save() else { activeRound = previous; pastRounds = history; return false }
        return true
    }

    private func notifyRoundEnded() {
        #if !PINPOINT_STORE_SMOKE
        NotificationCenter.default.post(name: .pinpointRoundChanged, object: nil)
        #endif
    }

    func setCurrentHole(_ number: Int) {
        guard let previous = activeRound, previous.currentHoleNumber != number,
              previous.hole(number) != nil else { return }
        activeRound?.currentHoleNumber = number
        if !save() { activeRound = previous }
    }

    func setRecap(_ text: String) {
        activeRound?.recap = text
        save()
    }

    // MARK: - Hole editing

    @discardableResult
    func updateHole(_ holeNumber: Int, mutate: (inout HoleScore) -> Void) -> Bool {
        guard var round = activeRound,
              let idx = round.holeScores.firstIndex(where: { $0.holeNumber == holeNumber })
        else { return false }
        mutate(&round.holeScores[idx])
        let previous = activeRound
        activeRound = round
        guard save() else { activeRound = previous; return false }
        return true
    }

    /// Commit score entry as one durable edit. Keep mapped shots and optional stats intact.
    @discardableResult
    func saveScoreEntry(_ holeNumber: Int, score: Int, putts: Int?, penalties: Int? = nil, penaltiesByShot: [Int: Int]? = nil, advance: Bool = false, commandID: UUID? = nil) -> Bool {
        guard var round = activeRound,
              let index = round.holeScores.firstIndex(where: { $0.holeNumber == holeNumber }),
              score > 0, putts.map({ $0 >= 0 && $0 <= score }) ?? true,
              (penalties ?? round.holeScores[index].penaltyStrokes) >= 0,
              (penalties ?? round.holeScores[index].penaltyStrokes) + (putts ?? 0) <= score else {
            lastError = "Choose a score. Putts plus penalties cannot exceed the total score."
            return false
        }
        if let assignments = penaltiesByShot {
            let total = penalties ?? round.holeScores[index].penaltyStrokes
            let physicalShots = score - (putts ?? 0) - total
            guard assignments.allSatisfy({ $0.key > 0 && $0.key <= physicalShots && $0.value >= 0 }),
                  assignments.values.reduce(0, +) <= total else {
                lastError = "Penalty assignments must match the strokes in your score."
                return false
            }
        }
        let previous = activeRound
        if let penaltiesByShot { round.holeScores[index].penaltiesByShot = penaltiesByShot.filter { $0.value > 0 } }
        else if let penalties, penalties != round.holeScores[index].penaltyStrokes {
            round.holeScores[index].penaltiesByShot = nil
        }
        if round.holeScores[index].recordedScore != score || round.holeScores[index].recordedPutts != putts ||
            round.holeScores[index].penaltyStrokes != (penalties ?? round.holeScores[index].penaltyStrokes) {
            round.holeScores[index].dismissedShotSuggestions = nil
        }
        round.holeScores[index].recordedScore = score
        round.holeScores[index].recordedPutts = putts
        if let penalties { round.holeScores[index].penaltyStrokes = penalties }
        round.holeScores[index].isComplete = true
        if let commandID { round.companionCommandIDs = Array(((round.companionCommandIDs ?? []) + [commandID]).suffix(128)) }
        if advance, round.currentHoleNumber == holeNumber, let next = round.nextHole(after: holeNumber) {
            round.currentHoleNumber = next
        }
        activeRound = round
        guard save() else { activeRound = previous; return false }
        lastError = nil
        return true
    }

    @discardableResult
    func saveGreenPosition(_ holeNumber: Int, point: GeoPoint, isPin: Bool) -> Bool {
        guard var round = activeRound, let index = round.holeScores.firstIndex(where: { $0.holeNumber == holeNumber }),
              point.latitude.isFinite, point.longitude.isFinite,
              (-90...90).contains(point.latitude), (-180...180).contains(point.longitude) else { return false }
        if isPin {
            round.holeScores[index].pinPosition.latitude = point.latitude
            round.holeScores[index].pinPosition.longitude = point.longitude
        } else { round.holeScores[index].firstPuttPosition = point }
        if let ball = round.holeScores[index].firstPuttPosition, let pin = round.pinCoordinate(for: holeNumber) {
            round.holeScores[index].firstPuttFeet = ball.yards(to: pin) * 3
        }
        let mappedPin = round.pinCoordinate(for: holeNumber)
        refreshMappedDistances(&round.holeScores[index], pin: mappedPin)
        let previous = activeRound; activeRound = round
        guard save() else { activeRound = previous; return false }
        return true
    }

    /// Writes the hole sheet (score / putts / penalties / fairway) without requiring shots.
    /// Later shot mapping does not overwrite `recordedScore` / `recordedPutts`.
    func recordHoleScore(_ holeNumber: Int, score: Int, putts: Int, penalties: Int, fairwayHit: Bool?) {
        updateHole(holeNumber) { hole in
            hole.applyRecordedScore(score: score, putts: putts, penalties: penalties, fairwayHit: fairwayHit)
        }
    }

    /// Save candidates independently of the scorecard. IDs remain as durable receipts.
    @discardableResult
    func receiveSwing(_ input: SwingCandidate, phonePoint: GeoPoint? = nil) -> Bool {
        guard input.state == .pending, input.peakG.isFinite, input.rotation.isFinite,
              input.timestamp.timeIntervalSinceNow < 60 else { return false }
        let isActive = activeRound?.id == input.roundID
        guard var round = isActive ? activeRound : pastRounds.first(where: { $0.id == input.roundID }),
              round.hole(input.hole) != nil else { return false }
        if round.swingCandidates?.contains(where: { $0.id == input.id }) == true { return true }
        var event = input
        let validWatch = input.locationSource == "watch" && (input.accuracy.map { $0 >= 0 && $0 <= 20 } ?? false)
            && (input.latitude.map { $0.isFinite && (-90...90).contains($0) } ?? false)
            && (input.longitude.map { $0.isFinite && (-180...180).contains($0) } ?? false)
        if !validWatch {
            let estimate = round.score(for: input.hole)?.shots.last.flatMap { $0.end ?? $0.start }
                ?? round.playLayout(for: input.hole)?.tee
            let point = phonePoint ?? estimate
            event.latitude = point?.latitude; event.longitude = point?.longitude
            event.locationSource = phonePoint == nil ? "estimated" : "phone"
            event.accuracy = nil
        }
        round.swingCandidates = (round.swingCandidates ?? []) + [event]
        let previous = activeRound; let previousPast = pastRounds
        if isActive { activeRound = round }
        else if let index = pastRounds.firstIndex(where: { $0.id == round.id }) { pastRounds[index] = round }
        guard save() else { activeRound = previous; pastRounds = previousPast; return false }
        return true
    }

    @discardableResult
    func reviewSwing(_ id: UUID, holeNumber: Int, club: GolfClub?, point: GeoPoint?, dismiss: Bool) -> Bool {
        guard var round = activeRound,
              let index = round.swingCandidates?.firstIndex(where: { $0.id == id }),
              round.swingCandidates?[index].state == .pending,
              let holeIndex = round.holeScores.firstIndex(where: { $0.holeNumber == holeNumber }) else { return false }
        let event = round.swingCandidates![index]
        if !dismiss {
            guard let club, let point, point.latitude.isFinite, point.longitude.isFinite,
                  (-90...90).contains(point.latitude), (-180...180).contains(point.longitude) else { return false }
            let shot = TrackedShot(id: event.id, number: round.holeScores[holeIndex].shots.count + 1,
                club: club, lie: club.isPutter ? .green : (round.holeScores[holeIndex].shots.isEmpty ? .tee : .fairway),
                start: point, includeInTrueDistance: false, source: .watch, timestamp: event.timestamp,
                note: "Reviewed Watch swing · \(event.locationSource) location")
            round.holeScores[holeIndex].shots.append(shot)
            round.holeScores[holeIndex].shots.sort { $0.timestamp < $1.timestamp }
            for i in round.holeScores[holeIndex].shots.indices { round.holeScores[holeIndex].shots[i].number = i + 1 }
        }
        round.swingCandidates![index].state = dismiss ? .dismissed : .confirmed
        let previous = activeRound; activeRound = round
        guard save() else { activeRound = previous; return false }
        return true
    }

    @discardableResult
    func addShot(_ holeNumber: Int, _ shot: TrackedShot) -> Bool {
        updateHole(holeNumber) { hole in
            var s = shot
            s.number = (hole.shots.map(\.number).max() ?? 0) + 1
            hole.shots.append(s)
            hole.shots.sort { $0.number < $1.number }
        }
    }

    @discardableResult
    func updateShot(_ holeNumber: Int, _ shot: TrackedShot) -> Bool {
        updateHole(holeNumber) { hole in
            if let idx = hole.shots.firstIndex(where: { $0.id == shot.id }) {
                hole.shots[idx] = shot
                let enteredDistance = shot.mappedDistanceYards
                refreshMappedDistances(&hole, pin: activeRound?.pinCoordinate(for: holeNumber))
                if let enteredDistance { hole.shots[idx].mappedDistanceYards = enteredDistance }
            }
        }
    }

    /// Move an existing swing, or confirm one estimated origin, without inventing carry.
    @discardableResult
    func moveShot(_ holeNumber: Int, shot: TrackedShot, to point: GeoPoint) -> Bool {
        guard point.latitude.isFinite, point.longitude.isFinite,
              (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
              var round = activeRound,
              let index = round.holeScores.firstIndex(where: { $0.holeNumber == holeNumber }) else { return false }
        var moved = round.holeScores[index].shots.first(where: { $0.id == shot.id }) ?? shot
        moved.start = point
        if let pin = round.pinCoordinate(for: holeNumber) { moved.distanceToPinBeforeYards = point.yards(to: pin) }
        if let existing = round.holeScores[index].shots.firstIndex(where: { $0.id == shot.id }) {
            round.holeScores[index].shots[existing] = moved
        } else {
            moved.note = "Manually placed shot"
            round.holeScores[index].shots.append(moved)
            round.holeScores[index].shots.sort { $0.number < $1.number }
        }
        let mappedPin = round.pinCoordinate(for: holeNumber)
        refreshMappedDistances(&round.holeScores[index], pin: mappedPin)
        let previous = activeRound
        activeRound = round
        guard save() else { activeRound = previous; return false }
        return true
    }

    /// Commit the reviewed map in one durable write. Navigation only proceeds on success.
    @discardableResult
    func confirmMappedShots(_ number: Int, suggestions: [TrackedShot]) -> Bool {
        guard let round = activeRound, let hole = round.score(for: number) else { return false }
        let expected = hole.suggestedShotCount ?? 0
        let additions = suggestions.filter { draft in
            draft.number > 0 && draft.number <= expected && !draft.isPutt &&
            !hole.shots.contains { $0.id == draft.id || $0.number == draft.number }
        }
        guard !additions.isEmpty else { return true }
        guard Set(additions.map(\.number)).count == additions.count,
              additions.allSatisfy({ shot in
                  guard let p = shot.start else { return false }
                  return p.latitude.isFinite && p.longitude.isFinite && (-90...90).contains(p.latitude) && (-180...180).contains(p.longitude)
              }) else { lastError = "Check the suggested shot positions before saving."; return false }
        let pin = round.pinCoordinate(for: number)
        return updateHole(number) { hole in
            hole.shots += additions.map { draft in
                var saved = draft
                saved.note = draft.note.replacingOccurrences(of: " — review before saving", with: " — confirmed on shot map")
                saved.distanceToPinBeforeYards = saved.start.flatMap { start in pin.map { start.yards(to: $0) } }
                return saved
            }
            hole.shots.sort { $0.number < $1.number }
            refreshMappedDistances(&hole, pin: pin)
        }
    }

    private func refreshMappedDistances(_ hole: inout HoleScore, pin: GeoPoint?) {
        guard let pin else { return }
        let indices = hole.shots.indices.filter { !hole.shots[$0].isPutt }.sorted { hole.shots[$0].number < hole.shots[$1].number }
        for (offset, index) in indices.enumerated() {
            let following = offset + 1 < indices.count ? hole.shots[indices[offset + 1]] : nil
            let next = following?.number == hole.shots[index].number + 1 ? following?.start : nil
            let expected = hole.suggestedShotCount
            let finishes = following == nil && (expected == nil || hole.shots[index].number >= expected!)
            guard let start = hole.shots[index].start,
                  let end = hole.shots[index].mappedEndpoint(nextStart: next, firstPutt: finishes ? hole.firstPuttPosition : nil, pin: pin, putts: finishes ? hole.recordedPutts : nil) else {
                hole.shots[index].mappedDistanceYards = nil
                continue
            }
            let distance = start.yards(to: end)
            hole.shots[index].mappedDistanceYards = distance
            if hole.shots[index].club == nil || hole.shots[index].clubWasSuggested == true {
                hole.shots[index].club = CaddieEngine.suggestedShotClub(for: distance, bag: clubBag)
                hole.shots[index].clubWasSuggested = true
            }
        }
    }

    func deleteShot(_ holeNumber: Int, id: UUID) {
        updateHole(holeNumber) { hole in
            guard let shot = hole.shots.first(where: { $0.id == id }) else { return }
            if !shot.isPutt { hole.dismissedShotSuggestions = (hole.dismissedShotSuggestions ?? 0) + 1 }
            if let assignments = hole.penaltiesByShot {
                hole.penaltiesByShot = assignments.reduce(into: [:]) { result, pair in
                    if pair.key != shot.number { result[pair.key > shot.number ? pair.key - 1 : pair.key] = pair.value }
                }
            }
            hole.shots.removeAll { $0.id == id }
            for i in hole.shots.indices { hole.shots[i].number = i + 1 }
        }
    }

    func nextShotNumber(_ holeNumber: Int) -> Int {
        guard let round = activeRound,
              let hole = round.score(for: holeNumber)
        else { return 1 }
        return (hole.shots.map(\.number).max() ?? 0) + 1
    }

    /// Current ball state for the GPS view: distance left + suggested lie.
    func ballState(_ holeNumber: Int) -> (distanceYards: Double, lie: Lie) {
        guard let round = activeRound,
              let holeDef = round.hole(holeNumber),
              let hole = round.score(for: holeNumber)
        else { return (150, .tee) }
        if hole.shots.isEmpty {
            if let ball = round.ballCoordinate(for: holeNumber),
               let pin = round.pinCoordinate(for: holeNumber) {
                return (ball.yards(to: pin), .tee)
            }
            return (Double(holeDef.yardage), .tee)
        }
        // Prefer live GPS remaining when the last shot has an end point.
        if let ball = round.ballCoordinate(for: holeNumber),
           let pin = round.pinCoordinate(for: holeNumber) {
            let remaining = ball.yards(to: pin)
            return (remaining, nextLie(after: hole.shots[hole.shots.count - 1], remaining: remaining))
        }
        var remaining = Double(holeDef.yardage)
        var lie: Lie = .tee
        for shot in hole.shots {
            if let carry = shot.carryYards {
                remaining = max(0, remaining - carry)
            } else if let d = shot.distanceToPinBeforeYards {
                remaining = max(0, d - (shot.club?.stockYards ?? 150))
            } else {
                remaining = max(0, remaining - (shot.club?.stockYards ?? 150))
            }
            lie = nextLie(after: shot, remaining: remaining)
        }
        return (remaining, lie)
    }

    private func nextLie(after shot: TrackedShot, remaining: Double) -> Lie {
        if shot.club?.isPutter == true { return .green }
        if remaining <= 25 { return .green }
        if remaining <= 45 { return .fringe }
        // Misses scatter: poor quality or lateral shapes find the rough.
        // Deterministic on purpose — the suggestion must not flip between recomputes.
        if shot.quality == .poor || shot.shape == .slice || shot.shape == .hook {
            return .rough
        }
        if shot.lie == .sand { return .fairway }
        return .fairway
    }

    // MARK: - Dictation

    /// Converts a parsed dictation into real shots appended to the hole.
    /// Returns the number of shots added.
    @discardableResult
    func applyDictation(_ result: HoleDictationResult, to holeNumber: Int, preserveReviewedFields: Bool = false) -> Int {
        guard let round = activeRound,
              let holeDef = round.hole(holeNumber),
              var hole = round.score(for: holeNumber)
        else { return 0 }
        var added = 0
        var nextNumber = (hole.shots.map(\.number).max() ?? 0) + 1
        var lie: Lie = hole.shots.isEmpty ? .tee : ballState(holeNumber).lie
        var remaining = hole.shots.isEmpty ? Double(holeDef.yardage) : ballState(holeNumber).distanceYards

        for parsed in result.shots {
            let club = parsed.club
            let shotLie: Lie = parsed.lie ?? (club?.isPutter == true ? .green : lie)
            let stock = club.map { bagCarry(for: $0) } ?? 0
            var noteBits: [String] = []
            if !parsed.outcome.isEmpty { noteBits.append(parsed.outcome) }
            if let d = parsed.distanceYards { noteBits.append("\(Int(d)) yds") }
            if !parsed.breakDirection.isEmpty { noteBits.append("breaks \(parsed.breakDirection)") }
            if !parsed.note.isEmpty { noteBits.append(parsed.note) }
            var shot = TrackedShot(
                number: nextNumber,
                club: club,
                lie: shotLie,
                distanceToPinBeforeYards: parsed.observations.startingDistanceFeet.map { $0 / 3 },
                carryYards: parsed.observations.carryYards,
                contact: parsed.contact,
                shape: parsed.shape,
                quality: parsed.quality,
                includeInTrueDistance: parsed.observations.carryYards != nil,
                source: .dictation,
                note: noteBits.joined(separator: " · ")
            )
            shot.lieWasInferred = parsed.lie == nil
            shot.observations = parsed.observations
            shot.traveledYards = parsed.distanceYards
            shot.remainingFeet = parsed.leftFeet
            hole.shots.append(shot)
            nextNumber += 1
            added += 1
            if let leftFeet = parsed.leftFeet {
                remaining = leftFeet / 3.0
                lie = remaining <= 8 ? .green : .fringe
            } else {
                remaining = max(0, remaining - stock)
                lie = remaining <= 25 ? .green : .fairway
            }
        }
        let structuredPutts = result.shots.filter { $0.club?.isPutter == true }.count
        if !preserveReviewedFields, let putts = result.puttsMentioned, putts > structuredPutts {
            for _ in 0..<(putts - structuredPutts) {
                hole.shots.append(TrackedShot(number: nextNumber, club: .putter,
                                              lie: .green, distanceToPinBeforeYards: remaining,
                                              source: .dictation))
                nextNumber += 1
                added += 1
            }
        }
        if hole.firstPuttFeet == nil, result.puttsMentioned != nil || structuredPutts > 0 {
            hole.firstPuttFeet = result.shots.first(where: { $0.club == .putter })?.observations.startingDistanceFeet
                ?? (preserveReviewedFields ? nil : result.shots.prefix(while: { $0.club != .putter }).last?.leftFeet)
        }
        var analysis = result.leftoverNote
        if let call = result.scoreCall {
            let line = "Called \(call)"
            if analysis.isEmpty {
                analysis = line
            } else if !analysis.localizedCaseInsensitiveContains("called \(call)") {
                analysis += " · " + line
            }
        }
        updateHole(holeNumber) {
            $0.shots = hole.shots
            $0.firstPuttFeet = hole.firstPuttFeet
            // Fill recorded putts / score from the spoken recap only when the
            // golfer hasn't already locked them in on the score sheet.
            if $0.recordedPutts == nil, let mentioned = result.puttsMentioned {
                $0.recordedPutts = mentioned
            }
            if $0.recordedScore == nil,
               let call = result.scoreCall,
               let fromCall = HoleScore.score(fromCall: call, par: holeDef.par) {
                $0.recordedScore = fromCall
                $0.isComplete = true
            }
            if !analysis.isEmpty {
                if let existing = $0.analysisNote, !existing.isEmpty, existing != analysis {
                    $0.analysisNote = existing + " · " + analysis
                } else {
                    $0.analysisNote = analysis
                }
            }
        }
        return added
    }

    /// Reviewed recaps update supplied card fields and replace only earlier voice shots.
    /// Manual/GPS shots survive; an explicit score remains independent of the shot count.
    @discardableResult
    func applyRecaps(_ drafts: [RecapDraft]) -> Bool {
        guard activeRound != nil else { return false }
        let original = activeRound
        isApplyingRecap = true
        for draft in drafts where draft.selected {
            guard activeRound?.score(for: draft.holeNumber) != nil else { continue }
            updateHole(draft.holeNumber) { hole in
                hole.shots.removeAll { $0.source == .dictation }
                for i in hole.shots.indices { hole.shots[i].number = i + 1 }
            }
            var reviewed = draft.result
            reviewed.scoreCall = nil
            reviewed.puttsMentioned = draft.putts.map { min(15, max(0, $0)) }
            applyDictation(reviewed, to: draft.holeNumber, preserveReviewedFields: true)
            updateHole(draft.holeNumber) { hole in
                if let score = draft.score { hole.recordedScore = score; hole.isComplete = true }
                if let putts = draft.putts { hole.recordedPutts = putts }
                if let penalties = draft.penalties { hole.penaltyStrokes = penalties }
                if let fairway = draft.fairway { hole.recordedFairwayHit = fairway }
                hole.dictateTranscript = draft.transcript
            }
        }
        isApplyingRecap = false
        guard save() else { activeRound = original; return false }
        return true
    }

    // MARK: - Stats (review later)

    /// Personal per-club average carry across all finished rounds + active round.
    func clubAverages() -> [GolfClub: Double] {
        var sums: [GolfClub: (total: Double, count: Int)] = [:]
        for round in (pastRounds + (activeRound.map { [$0] } ?? [])) {
            for hole in round.playedHoleScores {
                for shot in hole.shots where shot.includeInTrueDistance {
                    guard let club = shot.club, !club.isPutter,
                          let carry = shot.carryYards, carry > 20, carry < 400
                    else { continue }
                    let cur = sums[club] ?? (0, 0)
                    sums[club] = (cur.total + carry, cur.count + 1)
                }
            }
        }
        return sums.compactMapValues { $0.count > 0 ? $0.total / Double($0.count) : nil }
    }

    struct RoundStats: Equatable {
        var holesPlayed: Int
        var fairwaysHit: Int
        var fairwaysTotal: Int
        var girHit: Int
        var girTotal: Int
        var totalPutts: Int
        var avgFirstPuttFt: Double?
        var averageScore: Double?

        var fairwayPct: Double? {
            guard fairwaysTotal > 0 else { return nil }
            return Double(fairwaysHit) / Double(fairwaysTotal) * 100
        }

        var girPct: Double? {
            guard girTotal > 0 else { return nil }
            return Double(girHit) / Double(girTotal) * 100
        }
    }

    func stats(for rounds: [GolfRound]) -> RoundStats {
        var fwHit = 0, fwTotal = 0, girHit = 0, girTotal = 0, putts = 0
        var firstPutts: [Double] = []
        var scores: [Int] = []
        for round in rounds {
            for hole in round.playedHoleScores where hole.hasScore {
                guard let def = round.hole(hole.holeNumber) else { continue }
                if let fw = round.fairwayHit(for: hole.holeNumber) {
                    fwTotal += 1
                    if fw { fwHit += 1 }
                }
                if let gir = hole.greenInRegulation(par: def.par) {
                    girTotal += 1
                    if gir { girHit += 1 }
                }
                putts += hole.putts
                if let fp = hole.firstPuttFeet { firstPutts.append(fp) }
                scores.append(hole.grossScore)
            }
        }
        return RoundStats(
            holesPlayed: scores.count,
            fairwaysHit: fwHit, fairwaysTotal: fwTotal,
            girHit: girHit, girTotal: girTotal,
            totalPutts: putts,
            avgFirstPuttFt: firstPutts.isEmpty ? nil : firstPutts.reduce(0, +) / Double(firstPutts.count),
            averageScore: scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
        )
    }

    var allRoundsStats: RoundStats {
        stats(for: pastRounds + (activeRound.map { [$0] } ?? []))
    }
}
