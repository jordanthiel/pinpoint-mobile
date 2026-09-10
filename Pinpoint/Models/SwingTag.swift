import Foundation

enum SwingTagCategory: String, Codable, CaseIterable, Identifiable {
    case view
    case club
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .view: return "Camera"
        case .club: return "Club"
        case .custom: return "Tags"
        }
    }
}

enum SwingTagSource: String, Codable {
    case user
    case automatic
}

enum CameraAngle: String, Codable, CaseIterable, Identifiable {
    case faceOn
    case downTheLine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .faceOn: return "Face-on"
        case .downTheLine: return "DTL"
        }
    }

    var detail: String {
        switch self {
        case .faceOn: return "Facing the golfer"
        case .downTheLine: return "Down the line"
        }
    }

    var systemImage: String {
        switch self {
        case .faceOn: return "person.fill"
        case .downTheLine: return "figure.golf"
        }
    }

    var tagID: String { "view.\(rawValue)" }

    func makeTag(source: SwingTagSource) -> SwingTag {
        SwingTag(id: tagID, label: label, category: .view, source: source)
    }
}

enum ClubKind: String, Codable, CaseIterable, Identifiable {
    case driver
    case wood
    case hybrid
    case iron
    case wedge
    case putter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driver: return "Driver"
        case .wood: return "Wood"
        case .hybrid: return "Hybrid"
        case .iron: return "Iron"
        case .wedge: return "Wedge"
        case .putter: return "Putter"
        }
    }

    var tagID: String { "club.\(rawValue)" }

    func makeTag(source: SwingTagSource) -> SwingTag {
        SwingTag(id: tagID, label: label, category: .club, source: source)
    }
}

struct SwingTag: Identifiable, Codable, Hashable, Equatable {
    var id: String
    var label: String
    var category: SwingTagCategory
    var source: SwingTagSource

    var isAutomatic: Bool { source == .automatic }

    var cameraAngle: CameraAngle? {
        guard category == .view else { return nil }
        return CameraAngle.allCases.first { $0.tagID == id }
    }

    var clubKind: ClubKind? {
        guard category == .club else { return nil }
        return ClubKind.allCases.first { $0.tagID == id }
    }

    static func custom(_ raw: String, source: SwingTagSource = .user) -> SwingTag? {
        let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        let slug = label
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
        return SwingTag(id: "custom.\(slug)", label: label, category: .custom, source: source)
    }
}

extension Array where Element == SwingTag {
    var cameraAngle: CameraAngle? { compactMap(\.cameraAngle).first }
    var clubKind: ClubKind? { compactMap(\.clubKind).first }

    var ordered: [SwingTag] {
        sorted { lhs, rhs in
            if lhs.category != rhs.category {
                return categoryRank(lhs.category) < categoryRank(rhs.category)
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    mutating func set(_ tag: SwingTag) {
        removeAll { existing in
            if existing.id == tag.id { return true }
            if existing.category == tag.category, existing.category != .custom { return true }
            return false
        }
        if !contains(where: { $0.id == tag.id }) {
            append(tag)
        } else if let index = firstIndex(where: { $0.id == tag.id }) {
            self[index] = tag
        }
    }

    mutating func toggle(_ tag: SwingTag) {
        if contains(where: { $0.id == tag.id }) {
            removeAll { $0.id == tag.id }
        } else {
            set(tag)
        }
    }

    mutating func removeTag(id: String) {
        removeAll { $0.id == id }
    }

    func applyingAutoTags(_ suggestions: [SwingTag]) -> [SwingTag] {
        var result = self
        for tag in suggestions {
            let hasCategory = result.contains { $0.category == tag.category && $0.category != .custom }
            let hasID = result.contains { $0.id == tag.id }
            if tag.category == .custom {
                if !hasID { result.append(tag) }
            } else if !hasCategory {
                result.set(tag)
            }
        }
        return result
    }

    private func categoryRank(_ category: SwingTagCategory) -> Int {
        switch category {
        case .view: return 0
        case .club: return 1
        case .custom: return 2
        }
    }
}
