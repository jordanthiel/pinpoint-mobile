import MapKit
import SwiftUI

/// Full-screen green placement. Native annotations remain aligned during pan and zoom.
struct GreenView: View {
    enum Mode { case pin, putt }
    var holeNumber: Int
    var mode: Mode
    var layout: HoleLayout
    var pin: GeoPoint
    var firstPuttFeet: Double?
    var onMovePin: (GeoPoint) -> Void
    var onConfirmPin: (GeoPoint) -> Void = { _ in }
    var onConfirmPutt: (Double) -> Void
    var onSkip: () -> Void = {}
    var firstPuttPosition: GeoPoint?
    var onConfirmPuttPosition: ((GeoPoint) -> Void)?
    @State private var selectedPoint: GeoPoint?
    @State private var resetPoint: GeoPoint?
    @State private var mapRevision = 0
    private var initialPoint: GeoPoint {
        resetPoint ?? (mode == .pin ? pin : firstPuttPosition ?? approachPoint(yards: (firstPuttFeet ?? 18) / 3))
    }
    private func approachPoint(yards: Double) -> GeoPoint {
        let radians = layout.greenApproachHeading * .pi / 180
        return pin.offset(eastYards: -sin(radians) * yards, northYards: -cos(radians) * yards)
    }
    private var placement: GeoPoint { selectedPoint ?? initialPoint }
    private var puttFeet: Double { placement.yards(to: pin) * 3 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PositioningMap(initialPoint: initialPoint, distance: 80, heading: layout.greenApproachHeading,
                               referencePin: mode == .putt ? pin : nil) { selectedPoint = $0 }
                    .id(mapRevision)
                    .overlay {
                        PlacementMarker(symbol: mode == .pin ? "flag.fill" : "mappin", color: mode == .pin ? .white : .red)
                    }
                VStack(spacing: 8) {
                    Text(mode == .pin ? "Move the map to position the flag" : "Move the map to position your first putt")
                    Button("Reset to Green") {
                        let center = mode == .pin ? layout.greenCenter : approachPoint(yards: 6)
                        resetPoint = center; selectedPoint = center; mapRevision += 1
                    }.foregroundStyle(.white).underline()
                    if mode == .putt { Text("\(Int(puttFeet.rounded())) ft to pin").font(.headline.monospacedDigit()) }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(10).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)).padding(.top, 8)
            }
            VStack(spacing: 14) {
                Button {
                    if mode == .pin { onMovePin(placement); onConfirmPin(placement) }
                    else if let onConfirmPuttPosition { onConfirmPuttPosition(placement) }
                    else { onConfirmPutt(puttFeet) }
                } label: {
                    Label(mode == .pin ? "Confirm Pin Location" : "Confirm 1st Putt", systemImage: mode == .pin ? "flag.fill" : "mappin")
                        .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 56)
                        .background(PinpointTheme.primaryText, in: Capsule())
                }.buttonStyle(.plain)
                Button("Skip", action: onSkip).font(.headline).foregroundStyle(PinpointTheme.accentText).padding(.bottom, 12)
            }.padding(.horizontal, 20).padding(.top, 20).background(.white)
        }.background(Color.white.ignoresSafeArea())
    }
}
