import MapKit
import SwiftUI

/// Satellite green: drop the pin or mark the first-putt ball, with live feet.
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

    private var activePin: GeoPoint { droppedPin ?? pin }

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera, interactionModes: [.pan, .zoom]) {
                    if !layout.greenOutline.isEmpty {
                        MapPolygon(coordinates: layout.greenOutline.map(\.coordinate))
                            .foregroundStyle(Color.green.opacity(0.22))
                            .stroke(.white.opacity(0.5), lineWidth: 1)
                    }

                    if mode == .putt, let ball {
                        MapPolyline(coordinates: [ball.coordinate, activePin.coordinate])
                            .stroke(.white, lineWidth: 2)
                    }

                    Annotation("Pin", coordinate: activePin.coordinate, anchor: .bottom) {
                        VStack(spacing: 0) {
                            Image(systemName: "flag.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow)
                            Circle().fill(.black).frame(width: 12, height: 6)
                        }
                    }

                    if mode == .putt, let ball {
                        Annotation("Ball", coordinate: ball.coordinate, anchor: .center) {
                            VStack(spacing: 4) {
                                Text("\(Int(puttFeet.rounded())) Ft")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.6), in: Capsule())
                                ZStack {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 22, height: 22)
                                    Circle()
                                        .stroke(.white, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                            }
                        }
                    }
                }
                .mapStyle(.imagery(elevation: .realistic))
                .gesture(
                    SpatialTapGesture().onEnded { event in
                        guard let coord = proxy.convert(event.location, from: .local) else { return }
                        let point = GeoPoint(latitude: coord.latitude, longitude: coord.longitude)
                        switch mode {
                        case .pin:
                            droppedPin = point
                            onMovePin(point)
                        case .putt:
                            ball = point
                        }
                    }
                )
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
