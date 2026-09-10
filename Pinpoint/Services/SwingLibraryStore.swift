import AVFoundation
import Foundation
import UIKit

@Observable
final class SwingLibraryStore: @unchecked Sendable {
    private(set) var swings: [Swing] = []
    var isSyncing = false
    var lastError: String?
    var isSignedIn = false
    var accountEmail: String?
    var needsAuth = false

    private let cloud = SupabaseSyncService()
    private let fileManager = FileManager.default

    private var rootURL: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinpoint", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var videosURL: URL {
        let url = rootURL.appendingPathComponent("Videos", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var thumbnailsURL: URL {
        let url = rootURL.appendingPathComponent("Thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var manifestURL: URL {
        rootURL.appendingPathComponent("swings.json")
    }

    init() {
        load()
        Task { await observeAuth() }
    }

    func videoURL(for swing: Swing) -> URL {
        videosURL.appendingPathComponent(swing.fileName)
    }

    func thumbnailURL(for swing: Swing) -> URL {
        thumbnailsURL.appendingPathComponent(swing.thumbnailFileName)
    }

    func load() {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            swings = []
            return
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            swings = try JSONDecoder().decode([Swing].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            lastError = "Couldn't read saved swings."
            swings = []
        }
    }

    func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(swings)
            try data.write(to: manifestURL, options: [.atomic])
        } catch {
            lastError = "Couldn't save your library."
        }
    }

    @discardableResult
    func importRecording(
        from temporaryURL: URL,
        preset: CapturePreset,
        title: String,
        tags: [SwingTag] = []
    ) async throws -> Swing {
        let id = UUID()
        let fileName = "\(id.uuidString).mov"
        let thumbnailName = "\(id.uuidString).jpg"
        let destination = videosURL.appendingPathComponent(fileName)
        try fileManager.moveItem(at: temporaryURL, to: destination)

        let asset = AVURLAsset(url: destination)
        let duration = try await asset.load(.duration).seconds
        var width = preset.width
        var height = preset.height
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rendered = size.applying(transform)
            width = Int(abs(rendered.width))
            height = Int(abs(rendered.height))
        }

        if let thumbnail = await ThumbnailService.image(from: destination) {
            if let data = thumbnail.jpegData(compressionQuality: 0.82) {
                try data.write(to: thumbnailsURL.appendingPathComponent(thumbnailName), options: [.atomic])
            }
        }

        let swing = Swing(
            id: id,
            title: title,
            createdAt: Date(),
            duration: duration,
            frameRate: Double(preset.fps),
            width: width,
            height: height,
            fileName: fileName,
            thumbnailFileName: thumbnailName,
            annotations: [],
            cloudRecordName: nil,
            syncStatus: .local,
            tags: tags.ordered
        )

        await MainActor.run {
            swings.insert(swing, at: 0)
            saveMetadata()
        }
        Task { await autoTagIfNeeded(swing) }
        return swing
    }

    func rename(_ swing: Swing, to title: String) {
        update(swing) { $0.title = title }
        syncMetadataIfNeeded(swingID: swing.id)
    }

    func updateTags(_ swing: Swing, tags: [SwingTag]) {
        update(swing) { $0.tags = tags.ordered }
        syncMetadataIfNeeded(swingID: swing.id)
    }

    func autoTagIfNeeded(_ swing: Swing) async {
        let current = latest(swing)
        guard current.hasLocalVideo, current.needsAutoTags, !current.autoTagged else { return }
        let url = videoURL(for: current)
        guard fileManager.fileExists(atPath: url.path) else { return }

        let suggestions = await SwingAutoTagger.suggestTags(
            videoURL: url,
            duration: current.duration,
            frameRate: current.frameRate
        )
        await MainActor.run {
            update(current) {
                $0.tags = $0.tags.applyingAutoTags(suggestions)
                $0.autoTagged = true
            }
            syncMetadataIfNeeded(swingID: current.id)
        }
    }

    func detectTags(_ swing: Swing) async {
        let current = latest(swing)
        guard current.hasLocalVideo else { return }
        let url = videoURL(for: current)
        guard fileManager.fileExists(atPath: url.path) else { return }

        let suggestions = await SwingAutoTagger.suggestTags(
            videoURL: url,
            duration: current.duration,
            frameRate: current.frameRate
        )
        await MainActor.run {
            update(current) {
                $0.tags = $0.tags.applyingAutoTags(suggestions)
                $0.autoTagged = true
            }
            syncMetadataIfNeeded(swingID: current.id)
        }
    }

    func backfillAutoTags() async {
        let pending = swings.filter { $0.needsAutoTags && !$0.autoTagged }
        for swing in pending {
            await autoTagIfNeeded(swing)
        }
    }

    var customTagsInLibrary: [SwingTag] {
        var seen = Set<String>()
        var result: [SwingTag] = []
        for tag in swings.flatMap(\.tags) where tag.category == .custom {
            if seen.insert(tag.id).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    func updateAnnotations(_ swing: Swing, annotations: [Annotation]) {
        update(swing) { $0.annotations = annotations }
        syncMetadataIfNeeded(swingID: swing.id)
    }

    func delete(_ swing: Swing) async {
        try? fileManager.removeItem(at: videoURL(for: swing))
        try? fileManager.removeItem(at: thumbnailURL(for: swing))
        if swing.cloudRecordName != nil, isSignedIn {
            try? await cloud.delete(swingID: swing.id)
        }
        await MainActor.run {
            swings.removeAll { $0.id == swing.id }
            saveMetadata()
        }
    }

    func upload(_ swing: Swing) async {
        guard swing.hasLocalVideo else { return }
        guard PinpointSupabase.isConfigured else {
            lastError = CloudSyncError.notConfigured.localizedDescription
            return
        }
        guard isSignedIn else {
            needsAuth = true
            lastError = CloudSyncError.notSignedIn.localizedDescription
            return
        }
        update(swing) { $0.syncStatus = .uploading }
        do {
            let recordName = try await cloud.upload(
                swing: latest(swing),
                videoURL: videoURL(for: swing),
                thumbnailURL: thumbnailURL(for: swing)
            )
            update(swing) {
                $0.cloudRecordName = recordName
                $0.syncStatus = .uploaded
            }
        } catch {
            update(swing) { $0.syncStatus = .local }
            await MainActor.run {
                lastError = CloudSyncError.describe(error)
            }
        }
    }

    func download(_ swing: Swing) async {
        guard swing.cloudRecordName != nil else { return }
        guard isSignedIn else {
            needsAuth = true
            lastError = CloudSyncError.notSignedIn.localizedDescription
            return
        }
        update(swing) { $0.syncStatus = .downloading }
        do {
            let downloaded = try await cloud.download(
                swing: swing,
                videoDestination: videoURL(for: swing),
                thumbnailDestination: thumbnailURL(for: swing)
            )
            await MainActor.run {
                if let index = swings.firstIndex(where: { $0.id == swing.id }) {
                    swings[index] = downloaded
                    swings[index].syncStatus = .uploaded
                    saveMetadata()
                }
            }
            await autoTagIfNeeded(latest(swing))
        } catch {
            update(swing) { $0.syncStatus = .cloudOnly }
            await MainActor.run {
                lastError = CloudSyncError.describe(error)
            }
        }
    }

    func refreshFromCloud() async {
        guard PinpointSupabase.isConfigured, isSignedIn else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let remote = try await cloud.fetchAll()
            var existing = Dictionary(uniqueKeysWithValues: swings.map { ($0.id, $0) })
            for item in remote {
                if var local = existing[item.id] {
                    if local.syncStatus == .cloudOnly || !fileManager.fileExists(atPath: videoURL(for: local).path) {
                        local.title = item.title
                        local.createdAt = item.createdAt
                        local.duration = item.duration
                        local.frameRate = item.frameRate
                        local.width = item.width
                        local.height = item.height
                        local.cloudRecordName = item.cloudRecordName
                        local.annotations = item.annotations
                        local.tags = item.tags
                        local.syncStatus = fileManager.fileExists(atPath: videoURL(for: local).path) ? .uploaded : .cloudOnly
                        existing[item.id] = local
                    } else if local.cloudRecordName == nil {
                        local.cloudRecordName = item.cloudRecordName
                        local.syncStatus = .uploaded
                        existing[item.id] = local
                    }
                } else {
                    existing[item.id] = item
                }
            }
            swings = existing.values.sorted { $0.createdAt > $1.createdAt }
            saveMetadata()
        } catch {
            lastError = CloudSyncError.describe(error)
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let client = PinpointSupabase.client else { throw CloudSyncError.notConfigured }
        try await client.auth.signIn(email: email, password: password)
    }

    /// Returns `true` when the user is signed in immediately.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        guard let client = PinpointSupabase.client else { throw CloudSyncError.notConfigured }
        let response = try await client.auth.signUp(email: email, password: password)
        return response.session != nil
    }

    func sendPasswordReset(email: String) async throws {
        guard let client = PinpointSupabase.client else { throw CloudSyncError.notConfigured }
        try await client.auth.resetPasswordForEmail(email)
    }

    func signOut() async {
        try? await PinpointSupabase.client?.auth.signOut()
    }

    private func observeAuth() async {
        guard let client = PinpointSupabase.client else { return }
        for await (event, session) in client.auth.authStateChanges {
            await MainActor.run {
                isSignedIn = session != nil
                accountEmail = session?.user.email
            }
            if session != nil, event == .initialSession || event == .signedIn {
                await refreshFromCloud()
            }
        }
    }

    private func latest(_ swing: Swing) -> Swing {
        swings.first(where: { $0.id == swing.id }) ?? swing
    }

    private func syncMetadataIfNeeded(swingID: UUID) {
        guard isSignedIn, let swing = swings.first(where: { $0.id == swingID }), swing.syncStatus == .uploaded else {
            return
        }
        Task {
            try? await cloud.updateMetadata(swing)
        }
    }

    private func update(_ swing: Swing, mutate: (inout Swing) -> Void) {
        guard let index = swings.firstIndex(where: { $0.id == swing.id }) else { return }
        mutate(&swings[index])
        saveMetadata()
    }
}

enum ThumbnailService {
    static func image(from url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        do {
            let cg = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }
}
