import MapKit
import SwiftUI

/// Hole close-out confirm: satellite trail of mapped shots with numbered
/// pins, score summary, putt callouts, and advance actions — matching the
/// 18Birdies shot-details confirmation.
struct HoleConfirmView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var holeNumber: Int
    var layout: HoleLayout
    var pin: GeoPoint
    var tee: GeoPoint
    var onEditPin: () -> Void = {}
    var onEditScore: () -> Void = {}
    var onNext: () -> Void = {}
    var onMenu: () -> Void = {}

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedFeature: MapFeature?

    private var hole: HoleScore? {
        rounds.activeRound?.score(for: holeNumber)
    }

    private var mappedShots: [TrackedShot] {
        (hole?.shots ?? []).filter { $0.end != nil }.sorted { $0.number < $1.number }
    }

    /// Trail polyline: tee → each mapped shot end → pin.
    private var trail: [CLLocationCoordinate2D] {
        var pts = [tee.coordinate]
        pts += mappedShots.compactMap { $0.end?.coordinate }
        pts.append(pin.coordinate)
        return pts
    }

    private var score: Int { hole?.grossScore ?? 0 }
    private var shotCount: Int { hole?.shots.filter { !$0.isPutt }.count ?? 0 }
    private var puttCount: Int { hole?.putts ?? 0 }

    var body: some View {
        ZStack {
            MapReader { proxy in
                ZStack {
                    Map(position: $position, interactionModes: [.pan, .zoom], selection: $selectedFeature) {
                        MapPolyline(coordinates: trail)
                            .stroke(.white.opacity(0.96), lineWidth: 1.5)

                        // Mapped shots: blue numbered pins with lie/club tags.
                        // PROBE: Marker vs Annotation render test.
                        ForEach(mappedEnds, id: \.shot.id) { item in
                            Marker("\(item.shot.number)", monogram: Text("\(item.shot.number)"), coordinate: item.end.coordinate)
                                .tint(Color(red: 0.1, green: 0.4, blue: 1.0))
                        }
                        // Per-leg yardages, offset left of the trail.
                        ForEach(legAnnotations(), id: \.id) { leg in
                            MapKit.Annotation("", coordinate: leg.coordinate, anchor: .center) {
                                Text(leg.text)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.7), radius: 2)
                                    .offset(x: -64)
                            }
                        }
                        // Green putts callout with first-putt distance.
                        MapKit.Annotation("", coordinate: pin.coordinate, anchor: .center) {
                            puttsCallout(count: puttCount)
                                .offset(x: -44, y: -30)
                        }
                    }
                    .mapStyle(.imagery(elevation: .realistic))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mapControls {
                        MapCompass().mapControlVisibility(.hidden)
                    }
                }
            }

            VStack {
                HStack(alignment: .top) {
                    scorePill
                    Spacer()
                    Button("Edit Pin\nLocation") { onEditPin() }
                        .font(.system(size: 15, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(red: 0.1, green: 0.4, blue: 1.0))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(spacing: 10) {
                        Button(action: onMenu) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button(action: onEditPin) {
                            Image(systemName: "flag")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        onEditScore()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Edit Score")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: 170, minHeight: 60)
                        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        onNext()
                    } label: {
                        Text("Go to Next Hole")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color(red: 0.1, green: 0.4, blue: 1.0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            position = layout.cameraPosition(pin: pin)
        }
    }

    // MARK: - Score pill

    private var scorePill: some View {
        HStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(holeNumber)")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                VStack(alignment: .leading, spacing: 0) {
                    Text("Score")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("\(score)")
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.92))
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text("Shot")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.55))
                    Text("\(shotCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                }
                VStack(spacing: 0) {
                    Text("Putt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.55))
                    Text("\(puttCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Map annotations (position helpers keep the builder branch-free)

    /// Mapped shot endpoints, pre-filtered so map content stays branch-free.
    private var mappedEnds: [(shot: TrackedShot, end: GeoPoint)] {
        mappedShots.compactMap { shot in shot.end.map { (shot, $0) } }
    }

    private func shotPin(_ shot: TrackedShot) -> some View {
        HStack(alignment: .top, spacing: 3) {
            ZStack {
                TeePinShape()
                    .fill(Color(red: 0.1, green: 0.4, blue: 1.0))
                    .frame(width: 30, height: 38)
                Text("\(shot.number)")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .offset(y: -5)
            }
            Text("\(shot.lie.code), \(shot.club?.shortName ?? "?")")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(y: 4)
        }
    }

    private struct LegAnnotation: Identifiable {
        var id: Int
        var coordinate: CLLocationCoordinate2D
        var text: String
    }

    /// Per-leg yardage annotations at each trail segment's geo midpoint.
    private func legAnnotations() -> [LegAnnotation] {
        let pts = trail
        guard pts.count >= 2 else { return [] }
        var out: [LegAnnotation] = []
        for i in 0..<(pts.count - 1) {
            let a = GeoPoint(latitude: pts[i].latitude, longitude: pts[i].longitude)
            let b = GeoPoint(latitude: pts[i + 1].latitude, longitude: pts[i + 1].longitude)
            let yards = Int(a.yards(to: b).rounded())
            guard yards >= 10 else { continue }
            let mid = a.interpolated(to: b, t: 0.5)
            out.append(LegAnnotation(id: i, coordinate: mid.coordinate, text: "\(yards) Yds"))
        }
        return out
    }

    private func puttsCallout(count: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                TeePinShape()
                    .fill(Color(red: 0.13, green: 0.65, blue: 0.3))
                    .frame(width: 30, height: 38)
                VStack(spacing: 0) {
                    Text("Putts")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(count)")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .offset(y: -5)
            }
            if let feet = hole?.firstPuttFeet {
                VStack(spacing: 0) {
                    Text("1st Putt")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(Int(feet))Ft")
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 2)
            }
        }
    }
}
