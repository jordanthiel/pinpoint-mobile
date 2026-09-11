import MapKit
import SwiftUI

/// Named space so a handle drag can convert a finger point back to GPS.
enum MapDragSpace {
    static let name = "pinpoint.map"
}

/// Draggable map overlay. The parent should turn off map pan while `isDragging`.
struct MapDragHandle<Content: View>: View {
    var proxy: MapProxy
    var point: GeoPoint
    @Binding var isDragging: Bool
    var onMove: (GeoPoint) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let screen = proxy.convert(point.coordinate, to: .local) {
            content()
                .position(screen)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(MapDragSpace.name))
                        .onChanged { value in
                            isDragging = true
                            if let coord = proxy.convert(value.location, from: .named(MapDragSpace.name)) {
                                onMove(GeoPoint(latitude: coord.latitude, longitude: coord.longitude))
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
        }
    }
}
