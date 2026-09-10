import CoreGraphics
import Foundation

enum AnnotationKind: String, Codable, CaseIterable, Identifiable {
    case pen
    case line
    case arrow
    case circle
    case angle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "Draw"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .circle: return "Circle"
        case .angle: return "Angle"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .circle: return "circle"
        case .angle: return "angle"
        }
    }
}

struct Annotation: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var kind: AnnotationKind
    var points: [CGPoint]
    var colorHex: String
    var lineWidth: Double

    init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        points: [CGPoint],
        colorHex: String,
        lineWidth: Double = 3
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.colorHex = colorHex
        self.lineWidth = lineWidth
    }
}

enum AnnotationTool: Equatable {
    case none
    case draw(AnnotationKind)
}
