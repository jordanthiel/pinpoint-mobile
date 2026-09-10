import SwiftUI

struct PoseAngleReadoutView: View {
    let skeleton: PoseSkeleton?
    let visibleAngles: Set<PoseAngle>
    var onDismiss: (() -> Void)? = nil

    private var readings: [PoseAngleReading] {
        (skeleton ?? PoseSkeleton(joints: [:], timestamp: 0)).angleReadings(visible: visibleAngles)
    }

    var body: some View {
        if !visibleAngles.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PinpointTheme.secondaryText)
                    Text("Angles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PinpointTheme.secondaryText)
                        .textCase(.uppercase)
                    Spacer(minLength: 8)
                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hide angles")
                    }
                }

                ForEach(readings) { reading in
                    HStack(spacing: 8) {
                        Text("\(reading.number)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(Color(hex: "F5D76E"), in: Circle())

                        Text(reading.angle.shortTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(reading.degreesText)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(reading.measured == nil ? PinpointTheme.secondaryText : Color(hex: "F5D76E"))
                            .monospacedDigit()
                    }
                }
            }
            .padding(12)
            .frame(width: 168)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PinpointTheme.hairline, lineWidth: 1)
            }
        }
    }
}

struct MovablePoseAngleReadoutView: View {
    let skeleton: PoseSkeleton?
    let visibleAngles: Set<PoseAngle>
    var onDismiss: () -> Void

    @State private var origin: CGPoint?
    @State private var dragStart: CGPoint?
    @State private var panelHeight: CGFloat = 220
    @State private var containerSize: CGSize = .zero

    private let panelWidth: CGFloat = 168
    private let horizontalInset: CGFloat = 56
    private let verticalInset: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        containerSize = geo.size
                        if origin == nil {
                            origin = defaultOrigin(in: geo.size)
                        }
                    }
                    .onChange(of: geo.size) { _, size in
                        containerSize = size
                        if let origin {
                            self.origin = clamp(origin, in: size)
                        }
                    }
            }
            .allowsHitTesting(false)

            let current = origin ?? defaultOrigin(in: containerSize)
            PoseAngleReadoutView(
                skeleton: skeleton,
                visibleAngles: visibleAngles,
                onDismiss: onDismiss
            )
            .background(
                GeometryReader { panel in
                    Color.clear.preference(key: AnglePanelHeightKey.self, value: panel.size.height)
                }
            )
            .offset(x: current.x, y: current.y)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let size = containerSize
                        if dragStart == nil {
                            dragStart = origin ?? defaultOrigin(in: size)
                        }
                        let start = dragStart ?? defaultOrigin(in: size)
                        origin = clamp(
                            CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                            in: size
                        )
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
        }
        .onPreferenceChange(AnglePanelHeightKey.self) { height in
            if height > 0 {
                panelHeight = height
            }
        }
    }

    private func defaultOrigin(in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(verticalInset, size.width - horizontalInset - panelWidth),
            y: verticalInset
        )
    }

    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 8), max(8, size.width - panelWidth - 8)),
            y: min(max(point.y, 8), max(8, size.height - panelHeight - 8))
        )
    }
}

private struct AnglePanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
