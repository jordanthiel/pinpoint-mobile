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
    var onConfirmPutt: (Double) -> Void
    var onSkip: () -> Void = {}

    @State private var camera: MapCameraPosition = .automatic
    @State private var droppedPin: GeoPoint?
    @State private var ball: GeoPoint?
    @State private var selectedFeature: MapFeature?
    @State private var isDragging = false

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

                        MapDragHandle(proxy: proxy, point: activePin, isDragging: $isDragging, onMove: { point in
                            droppedPin = point
                            if mode == .pin { onMovePin(point) }
                        }) {
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
                        }

                        if mode == .putt, let ball {
                            MapDragHandle(proxy: proxy, point: ball, isDragging: $isDragging, onMove: { point in
                                self.ball = point
                            }) {
                                VStack(spacing: 4) {
                                    Text("\(Int(puttFeet.rounded())) ft")
                                        .font(.title3.weight(.bold).monospacedDigit())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.black.opacity(0.75), in: Capsule())
                                        .foregroundStyle(.white)
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().stroke(.white, lineWidth: 3))
                                }
                                .offset(y: -18)
                            }
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

            VStack(spacing: 10) {
                Button {
                    switch mode {
                    case .pin:
                        onMovePin(activePin)
                        onSkip()
                    case .putt:
                        onConfirmPutt(puttFeet)
                    }
                } label: {
                    Label(
                        mode == .pin ? "Confirm Pin Location" : "Confirm 1st Putt",
                        systemImage: mode == .pin ? "flag.fill" : "circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Skip", action: onSkip)
                    .font(.headline)
                    .foregroundStyle(PinpointTheme.accent)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .background(PinpointTheme.background)
        }
        .background(PinpointTheme.background.ignoresSafeArea())
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
}
