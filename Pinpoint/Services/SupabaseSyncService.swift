import Foundation
import Supabase

struct SupabaseSyncService {
    private var supabase: SupabaseClient {
        get throws {
            guard let client = PinpointSupabase.client else {
                throw CloudSyncError.notConfigured
            }
            return client
        }
    }

    func currentUserID() async throws -> UUID {
        let session = try await supabase.auth.session
        return session.user.id
    }

    func upload(swing: Swing, videoURL: URL, thumbnailURL: URL) async throws -> String {
        let client = try supabase
        let userID = try await currentUserID()
        let videoPath = storagePath(userID: userID, swingID: swing.id, ext: "mov")
        let thumbnailPath = storagePath(userID: userID, swingID: swing.id, ext: "jpg")
        let storage = client.storage.from(PinpointSupabase.bucket)

        try await storage.upload(
            videoPath,
            fileURL: videoURL,
            options: FileOptions(cacheControl: "3600", contentType: "video/quicktime", upsert: true)
        )

        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            try await storage.upload(
                thumbnailPath,
                fileURL: thumbnailURL,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
            )
        }

        let record = SwingRecord(swing: swing, userID: userID, videoPath: videoPath, thumbnailPath: thumbnailPath)
        try await client
            .from(PinpointSupabase.table)
            .upsert(record, onConflict: "id")
            .execute()

        return swing.id.uuidString
    }

    func updateMetadata(_ swing: Swing) async throws {
        let client = try supabase
        let userID = try await currentUserID()
        let patch = SwingMetadataPatch(
            title: swing.title,
            annotations_json: Self.encodeAnnotations(swing.annotations),
            tags_json: Self.encodeTags(swing.tags)
        )
        try await client
            .from(PinpointSupabase.table)
            .update(patch)
            .eq("id", value: swing.id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    func fetchAll() async throws -> [Swing] {
        let client = try supabase
        _ = try await currentUserID()
        let rows: [SwingRecord] = try await client
            .from(PinpointSupabase.table)
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.asSwing() }
    }

    func download(
        swing: Swing,
        videoDestination: URL,
        thumbnailDestination: URL
    ) async throws -> Swing {
        let client = try supabase
        let rows: [SwingRecord] = try await client
            .from(PinpointSupabase.table)
            .select()
            .eq("id", value: swing.id.uuidString)
            .limit(1)
            .execute()
            .value
        guard let record = rows.first else {
            throw CloudSyncError.invalidRecord
        }

        let storage = client.storage.from(PinpointSupabase.bucket)
        try await Self.downloadFile(
            storage: storage,
            path: record.video_path,
            destination: videoDestination
        )
        if !record.thumbnail_path.isEmpty {
            try? await Self.downloadFile(
                storage: storage,
                path: record.thumbnail_path,
                destination: thumbnailDestination
            )
        }

        var downloaded = record.asSwing()
        downloaded.syncStatus = .uploaded
        return downloaded
    }

    func delete(swingID: UUID) async throws {
        let client = try supabase
        let userID = try await currentUserID()
        let videoPath = storagePath(userID: userID, swingID: swingID, ext: "mov")
        let thumbnailPath = storagePath(userID: userID, swingID: swingID, ext: "jpg")
        _ = try? await client.storage.from(PinpointSupabase.bucket).remove(paths: [videoPath, thumbnailPath])
        try await client
            .from(PinpointSupabase.table)
            .delete()
            .eq("id", value: swingID.uuidString)
            .execute()
    }

    private static func downloadFile(
        storage: StorageFileApi,
        path: String,
        destination: URL
    ) async throws {
        let signedURL = try await storage.createSignedURL(path: path, expiresIn: 3600)
        let (tempURL, response) = try await URLSession.shared.download(from: signedURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CloudSyncError.message("Couldn't download that swing (\(http.statusCode)).")
        }
        try replaceItem(at: destination, with: tempURL)
    }

    private func storagePath(userID: UUID, swingID: UUID, ext: String) -> String {
        "\(userID.uuidString.lowercased())/\(swingID.uuidString.lowercased()).\(ext)"
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    static func encodeAnnotations(_ annotations: [Annotation]) -> String {
        guard let data = try? JSONEncoder().encode(annotations),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func encodeTags(_ tags: [SwingTag]) -> String {
        guard let data = try? JSONEncoder().encode(tags),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func decodeTags(_ json: String?) -> [SwingTag] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SwingTag].self, from: data)) ?? []
    }
}

private struct SwingMetadataPatch: Encodable {
    let title: String
    let annotations_json: String
    let tags_json: String
}

struct SwingRecord: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let created_at: Date
    let duration: Double
    let frame_rate: Double
    let width: Int
    let height: Int
    let file_name: String
    let thumbnail_file_name: String
    let annotations_json: String
    let tags_json: String?
    let video_path: String
    let thumbnail_path: String

    init(swing: Swing, userID: UUID, videoPath: String, thumbnailPath: String) {
        id = swing.id
        user_id = userID
        title = swing.title
        created_at = swing.createdAt
        duration = swing.duration
        frame_rate = swing.frameRate
        width = swing.width
        height = swing.height
        file_name = swing.fileName
        thumbnail_file_name = swing.thumbnailFileName
        annotations_json = SupabaseSyncService.encodeAnnotations(swing.annotations)
        tags_json = SupabaseSyncService.encodeTags(swing.tags)
        video_path = videoPath
        thumbnail_path = thumbnailPath
    }

    func asSwing() -> Swing {
        var annotations: [Annotation] = []
        if let data = annotations_json.data(using: .utf8) {
            annotations = (try? JSONDecoder().decode([Annotation].self, from: data)) ?? []
        }
        return Swing(
            id: id,
            title: title,
            createdAt: created_at,
            duration: duration,
            frameRate: frame_rate,
            width: width,
            height: height,
            fileName: file_name,
            thumbnailFileName: thumbnail_file_name,
            annotations: annotations,
            cloudRecordName: id.uuidString,
            syncStatus: .cloudOnly,
            tags: SupabaseSyncService.decodeTags(tags_json)
        )
    }
}

enum CloudSyncError: LocalizedError {
    case notConfigured
    case notSignedIn
    case invalidRecord
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your project URL and anon key to SupabaseConfig.plist."
        case .notSignedIn:
            return "Sign in to sync swings with Supabase."
        case .invalidRecord:
            return "That swing couldn't be found in Supabase."
        case .message(let text):
            return text
        }
    }

    static func describe(_ error: Error) -> String {
        if let cloud = error as? CloudSyncError {
            return cloud.localizedDescription
        }
        if let storage = error as? StorageError {
            let text = storage.message
            if text.localizedCaseInsensitiveContains("row-level security")
                || text.localizedCaseInsensitiveContains("unauthorized")
                || storage.error == "Unauthorized" {
                return "Cloud storage blocked the upload. Try again after rebuilding, or check that you're signed in."
            }
            return text
        }
        if let postgrest = error as? PostgrestError {
            return postgrest.message
        }
        return error.localizedDescription
    }
}
