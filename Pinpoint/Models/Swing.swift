import Foundation

enum SyncStatus: String, Codable, Hashable {
    case local
    case uploading
    case uploaded
    case downloading
    case cloudOnly

    var title: String {
        switch self {
        case .local: return "On this iPhone"
        case .uploading: return "Uploading"
        case .uploaded: return "Cloud"
        case .downloading: return "Downloading"
        case .cloudOnly: return "In the cloud"
        }
    }

    var systemImage: String {
        switch self {
        case .local: return "iphone"
        case .uploading: return "arrow.up.circle"
        case .uploaded: return "cloud.fill"
        case .downloading: return "arrow.down.circle"
        case .cloudOnly: return "cloud"
        }
    }
}

struct Swing: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var frameRate: Double
    var width: Int
    var height: Int
    var fileName: String
    var thumbnailFileName: String
    var annotations: [Annotation]
    var cloudRecordName: String?
    var syncStatus: SyncStatus
    var tags: [SwingTag]
    var autoTagged: Bool

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        duration: Double,
        frameRate: Double,
        width: Int,
        height: Int,
        fileName: String,
        thumbnailFileName: String,
        annotations: [Annotation],
        cloudRecordName: String?,
        syncStatus: SyncStatus,
        tags: [SwingTag] = [],
        autoTagged: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.frameRate = frameRate
        self.width = width
        self.height = height
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.annotations = annotations
        self.cloudRecordName = cloudRecordName
        self.syncStatus = syncStatus
        self.tags = tags
        self.autoTagged = autoTagged
    }

    var totalFrames: Int {
        max(1, Int((duration * frameRate).rounded()))
    }

    var resolutionLabel: String {
        CapturePreset(width: width, height: height, fps: Int(frameRate.rounded())).resolutionLabel
    }

    var analysisPlaybackRate: Double {
        min(1, 30 / max(frameRate, 1))
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    var hasLocalVideo: Bool {
        syncStatus != .cloudOnly
    }

    var needsAutoTags: Bool {
        hasLocalVideo && (
            !tags.contains(where: { $0.category == .view })
            || !tags.contains(where: { $0.category == .club })
        )
    }

    init(from decoder: Decoder) throws {
        let payload = try Payload(from: decoder)
        id = payload.id
        title = payload.title
        createdAt = payload.createdAt
        duration = payload.duration
        frameRate = payload.frameRate
        width = payload.width
        height = payload.height
        fileName = payload.fileName
        thumbnailFileName = payload.thumbnailFileName
        annotations = payload.annotations
        cloudRecordName = payload.cloudRecordName
        syncStatus = payload.syncStatus
        tags = payload.tags ?? []
        autoTagged = payload.autoTagged ?? false
    }

    func encode(to encoder: Encoder) throws {
        try Payload(
            id: id,
            title: title,
            createdAt: createdAt,
            duration: duration,
            frameRate: frameRate,
            width: width,
            height: height,
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            annotations: annotations,
            cloudRecordName: cloudRecordName,
            syncStatus: syncStatus,
            tags: tags,
            autoTagged: autoTagged
        ).encode(to: encoder)
    }

    private struct Payload: Codable {
        var id: UUID
        var title: String
        var createdAt: Date
        var duration: Double
        var frameRate: Double
        var width: Int
        var height: Int
        var fileName: String
        var thumbnailFileName: String
        var annotations: [Annotation]
        var cloudRecordName: String?
        var syncStatus: SyncStatus
        var tags: [SwingTag]?
        var autoTagged: Bool?
    }
}
