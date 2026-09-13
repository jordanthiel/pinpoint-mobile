import MapKit
import SwiftUI

/// Satellite green: drag the pin (or first-putt ball) — the map stays put.
struct GreenView: View {
    enum Mode {
        case pin
        case putt
    }

    var holeNumber: Int
    var mode: Mode
    var layout: HoleLayout
    var pin: GeoPoint
    var firstPuttFeet: Double?
    var onMovePin: (GeoPoint) -> Void
    var onConfirmPin: (GeoPoint) -> Void = { _ in }
    var onConfirmPutt: (Double) -> Void
    var onSkip: () -> Void = {}

    @State private var camera: MapCameraPosition = .automatic
    @State private var droppedPin: GeoPoint?
    @State private var ball: GeoPoint?
    @State private var selectedFeature: MapFeature?
    @State private var isDragging = false
    @State private var mapSize: CGSize = .zero

    private var activePin: GeoPoint { droppedPin ?? pin }
    private var mapModes: MapInteractionModes { isDragging ? [] : [.pan, .zoom] }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                MapReader { proxy in
                    ZStack {
                        Map(position: $camera, interactionModes: mapModes, selection: $selectedFeature) {
                            if !layout.greenOutline.isEmpty {
                                MapPolygon(coordinates: layout.smoothedGreenOutline.map(\.coordinate))
                                    .foregroundStyle(Color.green.opacity(0.22))
                                    .stroke(Color.white.opacity(0.7), lineWidth: 2.5)
                            }

                            if mode == .putt, let ball {
                                MapPolyline(coordinates: [ball.coordinate, activePin.coordinate])
                                    .stroke(.white, lineWidth: 2)
                            }
                        }
                        .mapStyle(.imagery(elevation: .realistic))
                        .background {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { mapSize = geo.size }
                                    .onChange(of: geo.size) { _, size in mapSize = size }
                            }
                        }

                        // mapSize arrival re-runs the body, giving the drag
                        // handles valid geometry after layout.
                        // Branch-free draggable flag: an if-let on proxy.convert
                        // never paints in map overlays, so the spot comes from
                        // a helper and visibility rides on opacity.
                        let pinSpot = markerSpot(for: activePin.coordinate, proxy: proxy)
                        VStack(spacing: 4) {
                            Text(mode == .pin ? "Drag the flag" : "Pin")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.75), in: Capsule())
                                .foregroundStyle(.white)
                            Image(systemName: "flag.fill")
                                .font(.title.weight(.bold))
                                .foregroundStyle(.yellow)
                                .padding(14)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .offset(y: -22)
                        .frame(width: 120, height: 120)
                        .contentShape(Rectangle())
                        .position(pinSpot.point)
                        .opacity(pinSpot.visible ? 1 : 0)
                        .allowsHitTesting(pinSpot.visible)
                        .highPriorityGesture(markerDrag(proxy: proxy, isDragging: $isDragging) { point in
                            droppedPin = point
                            if mode == .pin { onMovePin(point) }
                        })

                        if mode == .putt, ball != nil {
                            let ballSpot = markerSpot(for: ball!.coordinate, proxy: proxy)
                            HStack(alignment: .center, spacing: 10) {
                                VStack(spacing: 0) {
                                    Text("\(Int(puttFeet.rounded()))")
                                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                                    Text("Ft")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.7), radius: 3)
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().stroke(.white, lineWidth: 3))
                                        .shadow(color: .black.opacity(0.4), radius: 3)
                                    Ellipse()
                                        .fill(.black)
                                        .frame(width: 26, height: 7)
                                        .offset(y: -1)
                                }
                            }
                            .offset(x: -34, y: -20)
                            .frame(width: 140, height: 100)
                            .contentShape(Rectangle())
                            .position(ballSpot.point)
                            .opacity(ballSpot.visible ? 1 : 0)
                            .allowsHitTesting(ballSpot.visible)
                            .highPriorityGesture(markerDrag(proxy: proxy, isDragging: $isDragging) { point in
                                self.ball = point
                            })
                        }
                    }
                    .coordinateSpace(name: MapDragSpace.name)
                }

                Text(mode == .pin
                     ? "Pinch to zoom, then drag the flag onto the hole"
                     : "Drag the ball to your first-putt spot")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(.top, 16)
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 14) {
                Button {
                    switch mode {
                    case .pin:
                        onMovePin(activePin)
                        onConfirmPin(activePin)
                    case .putt:
                        onConfirmPutt(puttFeet)
                    }
                } label: {
                    Label(
                        mode == .pin ? "Confirm Pin Location" : "Confirm 1st Putt",
                        systemImage: mode == .pin ? "flag.fill" : "mappin"
                    )
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color(red: 0.1, green: 0.4, blue: 1.0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("Skip", action: onSkip)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.4, blue: 1.0))
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(Color.white)
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            camera = layout.greenCameraPosition(pin: pin)
            droppedPin = pin
            if mode == .putt {
                ball = pin.offset(eastYards: 0, northYards: -9)
            }
        }
    }

    private var puttFeet: Double {
        guard let ball else { return firstPuttFeet ?? 12 }
        return max(1, ball.yards(to: activePin) * 3)
    }

    /// Projected overlay anchor, computed in a helper so the builder stays
    /// branch-free (an if-let on proxy.convert never paints in map overlays).
    private func markerSpot(for coordinate: CLLocationCoordinate2D, proxy: MapProxy) -> (point: CGPoint, visible: Bool) {
        let hidden = (CGPoint(x: mapSize.width / 2, y: mapSize.height / 2), false)
        guard mapSize.width > 80, mapSize.height > 80,
              let p = proxy.convert(coordinate, to: .local),
              p.y > -60, p.y < mapSize.height + 60,
              p.x > -60, p.x < mapSize.width + 60
        else { return hidden }
        return (p, true)
    }

    /// Direct drag of a map marker: the finger point converts back to GPS and
    /// only the marker moves — the camera is never touched.
    private func markerDrag(proxy: MapProxy, isDragging: Binding<Bool>,
                            onMove: @escaping (GeoPoint) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(MapDragSpace.name))
            .onChanged { value in
                isDragging.wrappedValue = true
                if let coord = proxy.convert(value.location, from: .named(MapDragSpace.name)) {
                    onMove(GeoPoint(latitude: coord.latitude, longitude: coord.longitude))
                }
            }
            .onEnded { _ in isDragging.wrappedValue = false }
    }
}
