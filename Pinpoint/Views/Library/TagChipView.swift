import SwiftUI

struct TagChip: View {
    let title: String
    var systemImage: String?
    var selected: Bool
    var compact: Bool = false
    var expands: Bool = false
    var showsSparkle: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: compact ? 3 : 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .lineLimit(1)
            if showsSparkle {
                Image(systemName: "sparkle")
            }
        }
        .font(compact ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: expands ? .infinity : nil)
        .padding(.horizontal, compact ? 7 : 12)
        .padding(.vertical, compact ? 4 : 10)
        .background(
            selected ? PinpointTheme.accent : (compact ? Color.white.opacity(0.12) : PinpointTheme.surfaceElevated),
            in: Capsule()
        )

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct ChipSection<Item: Identifiable & Hashable>: View {
    let title: String
    let items: [Item]
    let label: (Item) -> String
    var systemImage: ((Item) -> String)? = nil
    var minimumChipWidth: CGFloat = 110
    let isSelected: (Item) -> Bool
    let onTap: (Item) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumChipWidth), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(PinpointTheme.secondaryText)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    TagChip(
                        title: label(item),
                        systemImage: systemImage?(item),
                        selected: isSelected(item),
                        expands: true,
                        action: { onTap(item) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlowChipGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        ChipWrapLayout(spacing: 8) {
            ForEach(items) { item in
                content(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChipWrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }

        let height = subviews.isEmpty ? 0 : y + rowHeight
        let width = maxWidth.isFinite ? maxWidth : usedWidth
        return (CGSize(width: width, height: height), frames)
    }
}
