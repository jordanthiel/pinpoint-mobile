import Foundation

struct CapturePreset: Identifiable, Hashable {
    let width: Int
    let height: Int
    let fps: Int

    var id: String { "\(width)x\(height)@\(fps)" }

    var resolutionLabel: String {
        switch (min(width, height), max(width, height)) {
        case (1080, 1920): return "1080p"
        case (720, 1280): return "720p"
        case (2160, 3840): return "4K"
        default: return "\(width)×\(height)"
        }
    }

    var shortLabel: String { "\(resolutionLabel) · \(fps) FPS" }

    var slowMotionFactor: Double {
        max(1, Double(fps) / 30)
    }

    var slowMotionDescription: String {
        if fps >= 120 {
            let factor = Int(slowMotionFactor.rounded())
            return "\(factor)× slower than real time when played at 30 FPS"
        }
        return "Standard speed capture"
    }
}

enum RecordStartDelay: Int, CaseIterable, Identifiable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .three: return "3s"
        case .five: return "5s"
        case .ten: return "10s"
        }
    }
}
