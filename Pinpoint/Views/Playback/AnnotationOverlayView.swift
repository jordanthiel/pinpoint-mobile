import SwiftUI

struct AnnotationOverlayView: View {
    @Binding var annotations: [Annotation]
    @Binding var tool: AnnotationTool
    var colorHex: String
    var isEditing: Bool

    @State private var selectedID: UUID?
    @State private var inProgress: Annotation?
    @State private var anglePoints: [CGPoint] = []
    @State private var handleOrigin: [CGPoint]?
    @State private var moveOrigin: [CGPoint]?

    private let handleHitSize: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Canvas { context, canvasSize in
                    for annotation in annotations {
                        let selected = annotation.id == selectedID && isEditing
                        draw(annotation, in: &context, size: canvasSize, selected: selected)
                    }
                    if let inProgress {
                        draw(inProgress, in: &context, size: canvasSize, selected: false)
                    }
                }
                .allowsHitTesting(false)

                if isEditing, case .draw = tool {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drawGesture(size: size))
                } else if isEditing {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(selectMoveGesture(size: size))

                    if let annotation = selectedAnnotation {
                        ForEach(Array(handlePoints(for: annotation).enumerated()), id: \.offset) { index, point in
                            handleView
                                .position(denormalize(point, size: size))
                                .highPriorityGesture(handleGesture(index: index, size: size))
                        }
                    }
                }
            }
            .coordinateSpace(name: "annot")
        }
        .allowsHitTesting(isEditing)
        .onChange(of: tool) { _, newTool in
            inProgress = nil
            anglePoints = []
            handleOrigin = nil
            moveOrigin = nil
            if case .draw = newTool {
                selectedID = nil
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                selectedID = nil
                inProgress = nil
                anglePoints = []
            }
        }
        .onChange(of: annotations) { _, newValue in
            if let selectedID, !newValue.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
        .onChange(of: colorHex) { _, hex in
            guard isEditing, let selectedID,
                  let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
            annotations[index].colorHex = hex
        }
    }

    private var selectedAnnotation: Annotation? {
        annotations.first { $0.id == selectedID }
    }

    private var handleView: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .stroke(PinpointTheme.accent, lineWidth: 2)
            }
            .frame(width: handleHitSize, height: handleHitSize)
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private func handlePoints(for annotation: Annotation) -> [CGPoint] {
        switch annotation.kind {
        case .pen:
            guard let first = annotation.points.first else { return [] }
            guard let last = annotation.points.last, annotation.points.count > 1 else { return [first] }
            return [first, last]
        default:
            return annotation.points
        }
    }

    private func handleGesture(index: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("annot"))
            .onChanged { value in
                guard let selectedID,
                      let annotationIndex = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
                if handleOrigin == nil {
                    handleOrigin = annotations[annotationIndex].points
                }
                guard let origin = handleOrigin else { return }
                let handles = handlePoints(for: Annotation(
                    id: selectedID,
                    kind: annotations[annotationIndex].kind,
                    points: origin,
                    colorHex: annotations[annotationIndex].colorHex,
                    lineWidth: annotations[annotationIndex].lineWidth
                ))
                guard index < handles.count else { return }

                let start = denormalize(handles[index], size: size)
                let current = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                let normalized = normalize(current, in: size)
                let kind = annotations[annotationIndex].kind

                if kind == .circle, index == 0 {
                    let delta = CGPoint(x: normalized.x - origin[0].x, y: normalized.y - origin[0].y)
                    annotations[annotationIndex].points = origin.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
                } else if kind == .pen {
                    let originHandle = handles[index]
                    let delta = CGPoint(x: normalized.x - originHandle.x, y: normalized.y - originHandle.y)
                    annotations[annotationIndex].points = origin.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
                } else {
                    var points = origin
                    points[index] = normalized
                    annotations[annotationIndex].points = points
                }
            }
            .onEnded { _ in
                handleOrigin = nil
            }
    }

    private func selectMoveGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("annot"))
            .onChanged { value in
                if moveOrigin == nil {
                    let start = normalize(value.startLocation, in: size)
                    if let hit = hitAnnotation(at: start, size: size) {
                        selectedID = hit.id
                        moveOrigin = hit.points
                    } else {
                        selectedID = nil
                        moveOrigin = []
                    }
                }
                guard let selectedID, let origin = moveOrigin, !origin.isEmpty,
                      let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                annotations[index].points = origin.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance < 8 {
                    selectedID = hitAnnotation(at: normalize(value.startLocation, in: size), size: size)?.id
                }
                moveOrigin = nil
            }
    }

    private func hitAnnotation(at point: CGPoint, size: CGSize) -> Annotation? {
        let threshold: CGFloat = 22
        return annotations.reversed().first { annotation in
            hitTest(annotation, at: point, size: size, threshold: threshold)
        }
    }

    private func hitTest(_ annotation: Annotation, at point: CGPoint, size: CGSize, threshold: CGFloat) -> Bool {
        let pixels = annotation.points.map { denormalize($0, size: size) }
        let location = denormalize(point, size: size)
        switch annotation.kind {
        case .pen, .line, .arrow, .angle:
            return distance(from: location, to: pixels) <= threshold
        case .circle:
            guard pixels.count >= 2 else { return false }
            let radius = hypot(pixels[1].x - pixels[0].x, pixels[1].y - pixels[0].y)
            let dist = hypot(location.x - pixels[0].x, location.y - pixels[0].y)
            return abs(dist - radius) <= threshold || dist <= radius
        }
    }

    private func distance(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard polyline.count >= 2 else {
            guard let only = polyline.first else { return .greatestFiniteMagnitude }
            return hypot(point.x - only.x, point.y - only.y)
        }
        var best = CGFloat.greatestFiniteMagnitude
        for index in 0..<(polyline.count - 1) {
            best = min(best, distance(from: point, segmentStart: polyline[index], segmentEnd: polyline[index + 1]))
        }
        return best
    }

    private func distance(from point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint) -> CGFloat {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return hypot(point.x - segmentStart.x, point.y - segmentStart.y) }
        let t = min(max(((point.x - segmentStart.x) * dx + (point.y - segmentStart.y) * dy) / length, 0), 1)
        let projection = CGPoint(x: segmentStart.x + t * dx, y: segmentStart.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("annot"))
            .onChanged { value in
                guard case .draw(let kind) = tool else { return }
                let point = normalize(value.location, in: size)
                if kind == .angle {
                    return
                }
                if var current = inProgress {
                    switch kind {
                    case .pen:
                        if current.points.last != point {
                            current.points.append(point)
                        }
                    case .line, .arrow, .circle:
                        if current.points.isEmpty {
                            current.points = [point, point]
                        } else if current.points.count == 1 {
                            current.points.append(point)
                        } else {
                            current.points[1] = point
                        }
                    case .angle:
                        break
                    }
                    inProgress = current
                } else {
                    inProgress = Annotation(kind: kind, points: [point], colorHex: colorHex)
                }
            }
            .onEnded { value in
                guard case .draw(let kind) = tool else { return }
                if kind == .angle {
                    let point = normalize(value.startLocation, in: size)
                    anglePoints.append(point)
                    inProgress = Annotation(kind: .angle, points: anglePoints, colorHex: colorHex)
                    if anglePoints.count >= 3 {
                        finish(Annotation(kind: .angle, points: anglePoints, colorHex: colorHex))
                        inProgress = nil
                        anglePoints = []
                    }
                    return
                }
                if let finished = inProgress, finished.points.count >= 2 {
                    finish(finished)
                }
                inProgress = nil
            }
    }

    private func finish(_ annotation: Annotation) {
        annotations.append(annotation)
        selectedID = annotation.id
    }

    private func normalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x / max(size.width, 1), 0), 1),
            y: min(max(point.y / max(size.height, 1), 0), 1)
        )
    }

    private func denormalize(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext, size: CGSize, selected: Bool) {
        let points = annotation.points.map { denormalize($0, size: size) }
        let color = Color(hex: annotation.colorHex)
        let width = annotation.lineWidth

        if selected {
            drawShape(annotation, points: points, color: .white.opacity(0.85), width: width + 4, in: &context)
        }
        drawShape(annotation, points: points, color: color, width: width, in: &context)
    }

    private func drawShape(
        _ annotation: Annotation,
        points: [CGPoint],
        color: Color,
        width: Double,
        in context: inout GraphicsContext
    ) {
        switch annotation.kind {
        case .pen:
            guard points.count > 1 else { return }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

        case .line:
            guard points.count >= 2 else { return }
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))

        case .arrow:
            guard points.count >= 2 else { return }
            drawArrow(from: points[0], to: points[1], color: color, width: width, in: &context)

        case .circle:
            guard points.count >= 2 else { return }
            let center = points[0]
            let radius = hypot(points[1].x - center.x, points[1].y - center.y)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width)

        case .angle:
            guard points.count >= 3 else {
                if points.count == 2 {
                    var path = Path()
                    path.move(to: points[0])
                    path.addLine(to: points[1])
                    context.stroke(path, with: .color(color), lineWidth: width)
                }
                return
            }
            drawAngle(points: points, color: color, width: width, in: &context)
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: Color, width: Double, in context: inout GraphicsContext) {
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))

        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 16
        var headPath = Path()
        headPath.move(to: end)
        headPath.addLine(to: CGPoint(
            x: end.x - head * cos(angle - .pi / 6),
            y: end.y - head * sin(angle - .pi / 6)
        ))
        headPath.move(to: end)
        headPath.addLine(to: CGPoint(
            x: end.x - head * cos(angle + .pi / 6),
            y: end.y - head * sin(angle + .pi / 6)
        ))
        context.stroke(headPath, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func drawAngle(points: [CGPoint], color: Color, width: Double, in context: inout GraphicsContext) {
        let a = points[0]
        let vertex = points[1]
        let c = points[2]

        var path = Path()
        path.move(to: a)
        path.addLine(to: vertex)
        path.addLine(to: c)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

        let angle1 = atan2(a.y - vertex.y, a.x - vertex.x)
        let angle2 = atan2(c.y - vertex.y, c.x - vertex.x)
        var delta = angle2 - angle1
        while delta <= -.pi { delta += 2 * .pi }
        while delta > .pi { delta -= 2 * .pi }

        let radius: CGFloat = 28
        var arc = Path()
        arc.addArc(center: vertex, radius: radius, startAngle: .radians(angle1), endAngle: .radians(angle1 + delta), clockwise: delta < 0)
        context.stroke(arc, with: .color(color), lineWidth: max(1.5, width - 1))

        let degrees = abs(delta) * 180 / .pi
        let mid = angle1 + delta / 2
        let labelPoint = CGPoint(x: vertex.x + 40 * cos(mid), y: vertex.y + 40 * sin(mid))
        let text = Text("\(Int(degrees.rounded()))°")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(color)
        context.draw(text, at: labelPoint)
    }
}
