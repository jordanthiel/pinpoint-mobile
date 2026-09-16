import SwiftUI
import MapKit

struct SwingReviewSheet: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss
    var event: SwingCandidate
    @State private var club: GolfClub?
    @State private var hole = 1
    @State private var point: GeoPoint?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(event.locationSource == "estimated" ? "Estimated position" : "\(event.locationSource.capitalized) GPS position").font(.headline)
                    Text("Possible swing at \(event.timestamp.formatted(date: .omitted, time: .shortened)). Practice swings can also trigger detection. Move the map to correct the spot, then confirm or dismiss.").font(.subheadline).foregroundStyle(.secondary)
                    if point != nil { ShotPositionPicker(point: $point) }
                    Picker("Hole", selection: $hole) {
                        ForEach(rounds.activeRound?.holeScores ?? []) { Text("Hole \($0.holeNumber)").tag($0.holeNumber) }
                    }
                    Picker("Club", selection: $club) {
                        Text("Choose club").tag(Optional<GolfClub>.none)
                        ForEach(GolfClub.allCases) { Text($0.displayName).tag(Optional($0)) }
                    }
                    Button("Confirm shot") {
                        if rounds.reviewSwing(event.id, holeNumber: hole, club: club, point: point, dismiss: false) { dismiss() }
                        else { error = rounds.lastError ?? "Couldn't save this shot. Try again." }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(club == nil || point == nil)
                    Button("Dismiss / Practice swing", role: .destructive) {
                        if rounds.reviewSwing(event.id, holeNumber: hole, club: nil, point: nil, dismiss: true) { dismiss() }
                        else { error = rounds.lastError ?? "Couldn't dismiss this swing." }
                    }
                    if let error { Text(error).foregroundStyle(.orange) }
                }.padding()
            }.navigationTitle("Review swing")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .onAppear {
                    hole = event.hole
                    if let lat = event.latitude, let lon = event.longitude { point = GeoPoint(latitude: lat, longitude: lon) }
                    else { point = rounds.activeRound?.playLayout(for: event.hole)?.tee }
                }
        }
    }
}

/// Pan beneath the crosshair to correct a recorded swing position.
struct ShotPositionPicker: View {
    @Binding var point: GeoPoint?
    @State private var position: MapCameraPosition = .automatic
    var body: some View {
        VStack(alignment: .leading) {
            Map(position: $position, interactionModes: [.pan, .zoom]) {}
                .mapStyle(.imagery)
                .overlay { Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(.white, PinpointTheme.accent).allowsHitTesting(false) }
                .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                .onMapCameraChange(frequency: .onEnd) { context in
                    point = GeoPoint(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                }
                .onAppear {
                    if let point { position = .region(MKCoordinateRegion(center: point.coordinate, latitudinalMeters: 180, longitudinalMeters: 180)) }
                }
            Text("Drag the map to position the shot under the crosshair.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
