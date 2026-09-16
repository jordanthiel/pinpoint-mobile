import SwiftUI

struct ShotLocationEditor: View {
    @Environment(\.dismiss) private var dismiss
    var initialPoint: GeoPoint
    var locationTrail = GolfLocationTrail()
    var endpoint: GeoPoint?
    var onSave: (GeoPoint) -> Void
    @State private var draft: GeoPoint?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PositioningMap(initialPoint: initialPoint, distance: 250, locationTrail: locationTrail) { draft = $0 }
                    .overlay { PlacementMarker(symbol: "mappin", color: PinpointTheme.accent) }
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            Text("Move the map to position the shot")
                            if let endpoint {
                                Text("\(Int((draft ?? initialPoint).yards(to: endpoint).rounded())) yds")
                                    .font(.title2.bold().monospacedDigit())
                            }
                        }.padding(12).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white).padding().allowsHitTesting(false)
                    }
                Button("Use This Location") { onSave(draft ?? initialPoint); dismiss() }
                    .buttonStyle(PrimaryButtonStyle()).padding()
            }
            .navigationTitle("Move Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
