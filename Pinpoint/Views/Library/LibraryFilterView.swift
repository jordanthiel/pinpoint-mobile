import Foundation
import SwiftUI

enum DateFilter: String, CaseIterable, Identifiable {
    case any
    case today
    case last7Days
    case last30Days
    case thisYear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any time"
        case .today: return "Today"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .thisYear: return "This year"
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .any:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= start
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= start
        case .thisYear:
            return calendar.component(.year, from: date) == calendar.component(.year, from: now)
        }
    }
}

struct LibraryFilter: Equatable {
    var date: DateFilter = .any
    var angles: Set<CameraAngle> = []
    var clubs: Set<ClubKind> = []
    var customTagIDs: Set<String> = []

    var isActive: Bool {
        date != .any || !angles.isEmpty || !clubs.isEmpty || !customTagIDs.isEmpty
    }

    var activeCount: Int {
        (date == .any ? 0 : 1) + angles.count + clubs.count + customTagIDs.count
    }

    func matches(_ swing: Swing) -> Bool {
        guard date.contains(swing.createdAt) else { return false }
        if !angles.isEmpty {
            guard let angle = swing.tags.cameraAngle, angles.contains(angle) else { return false }
        }
        if !clubs.isEmpty {
            guard let club = swing.tags.clubKind, clubs.contains(club) else { return false }
        }
        if !customTagIDs.isEmpty {
            let ids = Set(swing.tags.filter { $0.category == .custom }.map(\.id))
            guard !customTagIDs.isDisjoint(with: ids) else { return false }
        }
        return true
    }

    mutating func clear() {
        self = LibraryFilter()
    }
}

struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    var customTags: [SwingTag]
    var onEdit: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(filter.isActive ? "Filters · \(filter.activeCount)" : "Filters")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        filter.isActive ? PinpointTheme.accent : PinpointTheme.surfaceElevated,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)

                if filter.date != .any {
                    TagChip(title: filter.date.label, selected: true, compact: true) {
                        filter.date = .any
                    }
                }
                ForEach(CameraAngle.allCases.filter { filter.angles.contains($0) }) { angle in
                    TagChip(title: angle.label, selected: true, compact: true) {
                        filter.angles.remove(angle)
                    }
                }
                ForEach(ClubKind.allCases.filter { filter.clubs.contains($0) }) { club in
                    TagChip(title: club.label, selected: true, compact: true) {
                        filter.clubs.remove(club)
                    }
                }
                ForEach(customTags.filter { filter.customTagIDs.contains($0.id) }) { tag in
                    TagChip(title: tag.label, selected: true, compact: true) {
                        filter.customTagIDs.remove(tag.id)
                    }
                }

                if filter.isActive {
                    Button("Clear") {
                        filter.clear()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PinpointTheme.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

struct LibraryFilterSheet: View {
    @Binding var filter: LibraryFilter
    var customTags: [SwingTag]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ChipSection(
                        title: "Date",
                        items: DateFilter.allCases,
                        label: \.label,
                        minimumChipWidth: 150,
                        isSelected: { filter.date == $0 },
                        onTap: { filter.date = $0 }
                    )

                    ChipSection(
                        title: "Camera",
                        items: CameraAngle.allCases,
                        label: \.label,
                        systemImage: { $0.systemImage },
                        minimumChipWidth: 150,
                        isSelected: { filter.angles.contains($0) },
                        onTap: { toggle($0, in: &filter.angles) }
                    )

                    ChipSection(
                        title: "Club",
                        items: ClubKind.allCases,
                        label: \.label,
                        minimumChipWidth: 100,
                        isSelected: { filter.clubs.contains($0) },
                        onTap: { toggle($0, in: &filter.clubs) }
                    )

                    if !customTags.isEmpty {
                        ChipSection(
                            title: "Tags",
                            items: customTags,
                            label: \.label,
                            minimumChipWidth: 100,
                            isSelected: { filter.customTagIDs.contains($0.id) },
                            onTap: { tag in
                                if filter.customTagIDs.contains(tag.id) {
                                    filter.customTagIDs.remove(tag.id)
                                } else {
                                    filter.customTagIDs.insert(tag.id)
                                }
                            }
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PinpointTheme.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { filter.clear() }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}
