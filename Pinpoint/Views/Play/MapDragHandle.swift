import MapKit
import SwiftUI

/// Named space so a handle drag can convert a finger point back to GPS.
enum MapDragSpace {
    static let name = "pinpoint.map"
}

/// Draggable map overlay. The parent should turn off map pan while `isDragging`.
///
/// When `requiresHold` is true, a quick drag on the handle pans the map; a
/// press-and-hold then drag moves this point instead.
struct MapDragHandle<Content: View>: View {
    var proxy: MapProxy
    var point: GeoPoint
    @Binding var isDragging: Bool
    var requiresHold: Bool = false
    var onMove: (GeoPoint) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let screen = proxy.convert(point.coordinate, to: .local) {
            content()
                .position(screen)
                .modifier(HandleDragModifier(
                    proxy: proxy,
                    isDragging: $isDragging,
                    requiresHold: requiresHold,
                    onMove: onMove
                ))
        }
    }
}

private struct HandleDragModifier: ViewModifier {
    var proxy: MapProxy
    @Binding var isDragging: Bool
    var requiresHold: Bool
    var onMove: (GeoPoint) -> Void

    func body(content: Content) -> some View {
        if requiresHold {
            content.simultaneousGesture(holdThenDrag)
        } else {
            content.highPriorityGesture(immediateDrag)
        }
    }

    private var immediateDrag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(MapDragSpace.name))
            .onChanged { value in
                isDragging = true
                move(to: value.location)
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private var holdThenDrag: some Gesture {
        LongPressGesture(minimumDuration: 0.32, maximumDistance: 16)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(MapDragSpace.name)))
            .onChanged { value in
                switch value {
                case .first(true):
                    if !isDragging { isDragging = true }
                case .second(_, let drag):
                    if !isDragging { isDragging = true }
                    if let drag { move(to: drag.location) }
                default:
                    break
                }
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private func move(to location: CGPoint) {
        if let coord = proxy.convert(location, from: .named(MapDragSpace.name)) {
            onMove(GeoPoint(latitude: coord.latitude, longitude: coord.longitude))
        }
    }
}
