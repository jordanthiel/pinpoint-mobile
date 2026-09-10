import SwiftUI

struct PoseOverlayView: View {
    let skeleton: PoseSkeleton?
    var videoSize: CGSize
    var gravity: VideoOverlayGravity = .fit
    var videoRect: CGRect = .zero
    var showAngles = false
    var visibleAngles: Set<PoseAngle> = Set(PoseAngle.allCases)

    private static let angleColor = Color(hex: "F5D76E")

    var body: some View {
        GeometryReader { geometry in
            let canvasRect = Self.overlayRect(
                videoRect: videoRect,
                imageSize: videoSize,
                in: geometry.size,
                gravity: gravity
            )
            Canvas { context, canvasSize in
                guard let skeleton else { return }
                let box = canvasRect

                for bone in PoseSkeleton.bones {
                    guard let a = skeleton[bone.0], let b = skeleton[bone.1],
                          a.confidence >= 0.18, b.confidence >= 0.18 else { continue }
                    var path = Path()
                    path.move(to: Self.displayPoint(a.displayPoint, in: box))
                    path.addLine(to: Self.displayPoint(b.displayPoint, in: box))
                    context.stroke(
                        path,
                        with: .color(PinpointTheme.accent.opacity(0.95)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }

                for joint in skeleton.joints.values where joint.confidence >= 0.18 {
                    let point = Self.displayPoint(joint.displayPoint, in: box)
                    let lowered = joint.name.lowercased()
                    let radius: CGFloat = lowered.contains("wrist") || lowered.contains("nose") ? 5 : 4
                    let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                    context.stroke(Path(ellipseIn: rect), with: .color(PinpointTheme.accent), lineWidth: 1.5)
                }

                if showAngles {
                    for reading in skeleton.angleReadings(visible: visibleAngles) {
                        guard let measured = reading.measured else { continue }
                        drawAngle(
                            measured,
                            number: reading.number,
                            in: box,
                            bounds: canvasSize,
                            context: &context
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func drawAngle(
        _ measured: MeasuredPoseAngle,
        number: Int,
        in box: CGRect,
        bounds: CGSize,
        context: inout GraphicsContext
    ) {
        let vertex = Self.displayPoint(measured.vertex, in: box)
        let start = Self.displayPoint(measured.start, in: box)
        let end = Self.displayPoint(measured.end, in: box)
        let color = Self.angleColor

        let angle1 = atan2(start.y - vertex.y, start.x - vertex.x)
        let angle2 = atan2(end.y - vertex.y, end.x - vertex.x)
        var delta = angle2 - angle1
        while delta <= -.pi { delta += 2 * .pi }
        while delta > .pi { delta -= 2 * .pi }

        let radius: CGFloat = 18
        var arc = Path()
        arc.addArc(
            center: vertex,
            radius: radius,
            startAngle: .radians(angle1),
            endAngle: .radians(angle1 + delta),
            clockwise: delta < 0
        )
        context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let bisector = angle1 + delta / 2
        let badge = Self.calloutPoint(from: vertex, along: bisector, bounds: bounds)

        var leader = Path()
        leader.move(to: CGPoint(x: vertex.x + 10 * cos(bisector), y: vertex.y + 10 * sin(bisector)))
        leader.addLine(to: badge)
        context.stroke(leader, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        let badgeRect = CGRect(x: badge.x - 9, y: badge.y - 9, width: 18, height: 18)
        context.fill(Path(ellipseIn: badgeRect), with: .color(color))
        context.stroke(Path(ellipseIn: badgeRect), with: .color(.black.opacity(0.35)), lineWidth: 0.5)
        let label = Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
        context.draw(label, at: badge)
    }

    private static func calloutPoint(from vertex: CGPoint, along angle: CGFloat, bounds: CGSize) -> CGPoint {
        let inset: CGFloat = 22
        let distances: [CGFloat] = [42, 64, 88, 118, 150]
        for distance in distances {
            let point = CGPoint(x: vertex.x + distance * cos(angle), y: vertex.y + distance * sin(angle))
            if Self.isInside(point, bounds: bounds, inset: inset) {
                return point
            }
        }
        let flipped = angle + .pi
        for distance in distances {
            let point = CGPoint(x: vertex.x + distance * cos(flipped), y: vertex.y + distance * sin(flipped))
            if Self.isInside(point, bounds: bounds, inset: inset) {
                return point
            }
        }
        return CGPoint(
            x: min(max(vertex.x, inset), max(bounds.width - inset, inset)),
            y: min(max(vertex.y, inset), max(bounds.height - inset, inset))
        )
    }

    private static func isInside(_ point: CGPoint, bounds: CGSize, inset: CGFloat) -> Bool {
        point.x >= inset && point.x <= bounds.width - inset
            && point.y >= inset && point.y <= bounds.height - inset
    }

    private static func overlayRect(
        videoRect: CGRect,
        imageSize: CGSize,
        in bounds: CGSize,
        gravity: VideoOverlayGravity
    ) -> CGRect {
        if videoRect.width > 1, videoRect.height > 1 {
            return videoRect
        }
        return fittedRect(imageSize: imageSize, in: bounds, gravity: gravity)
    }

    private static func displayPoint(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.minY + normalized.y * rect.height
        )
    }

    static func fittedRect(imageSize: CGSize, in bounds: CGSize, gravity: VideoOverlayGravity) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = bounds.width / bounds.height

        switch gravity {
        case .fit:
            if imageAspect > viewAspect {
                let height = bounds.width / imageAspect
                return CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
            }
            let width = bounds.height * imageAspect
            return CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
        case .fill:
            if imageAspect > viewAspect {
                let width = bounds.height * imageAspect
                return CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
            }
            let height = bounds.width / imageAspect
            return CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        }
    }
}

enum VideoOverlayGravity {
    case fit
    case fill
}
