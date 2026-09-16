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
    var onEditPutt: () -> Void = {}

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedShot: UUID?
    @State private var editingShot: TrackedShot?
    @State private var reviewingSwing: SwingCandidate?
    @State private var addingShot = false
    @State private var puttMarkerID = UUID()
    @State private var flagMarkerID = UUID()
    @State private var suggestions: [TrackedShot] = []
    @State private var showEndRound = false
    @State private var showFairway = false
    @State private var moveError = false
    @State private var dragDistance: Double?

    private var hole: HoleScore? {
        rounds.activeRound?.score(for: holeNumber)
    }

    private var mappedShots: [TrackedShot] {
        ((hole?.shots ?? []).filter { !$0.isPutt } + suggestions).sorted { $0.number < $1.number }
    }

    /// Trail polyline: tee → each mapped shot end → pin.
    private var trail: [CLLocationCoordinate2D] {
        var pts = mappedEnds.map { $0.end.coordinate }
        if pts.isEmpty { pts = [tee.coordinate] }
        if let firstPutt = hole?.firstPuttPosition { pts.append(firstPutt.coordinate) }
        pts.append(pin.coordinate)
        return pts
    }

    private var score: Int { hole?.grossScore ?? 0 }
    private var shotCount: Int { mappedShots.count }
    private var puttCount: Int { hole?.putts ?? 0 }

    var body: some View {
        ZStack {
            ShotOverviewMap(layout: layout, markers: overviewMarkers, legs: mappedLegs, pin: pin, locationTrail: rounds.locationTrail(holeNumber), onDragDistance: { dragDistance = $0 }, onMove: moveShot) { id in
                if id == flagMarkerID { onEditPin() }
                else if id == puttMarkerID { onEditPutt() }
                else if let shot = mappedShots.first(where: { $0.id == id }) { editingShot = shot }
                else { reviewingSwing = rounds.activeRound?.swingCandidates?.first(where: { $0.id == id }) }
            }.ignoresSafeArea()

            VStack {
                if let round = rounds.activeRound, (round.hole(holeNumber)?.par ?? 3) > 3 {
                    Button { showFairway = true } label: {
                        let result = round.fairwayHit(for: holeNumber, reviewing: mappedShots)
                        Text("Fairway · \(result.map { $0 ? "Hit" : "Missed" } ?? "Unknown")\(hole?.recordedFairwayHit == nil && result != nil ? " · Auto" : "")")
                            .font(.caption.weight(.semibold)).padding(10)
                            .foregroundStyle(.white).background(.black.opacity(0.8), in: Capsule())
                    }.buttonStyle(.plain)
                }

                if let dragDistance {
                    HStack {
                        Text("Distance to Pin")
                        Spacer()
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text("\(Int(dragDistance.rounded())) Yds").font(.title2.bold().monospacedDigit())
                    }.font(.headline).foregroundStyle(.white).padding(18)
                        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 12).padding(.top, 8).allowsHitTesting(false)
                } else {
                HStack(alignment: .top) {
                    scorePill
                    Spacer()
                    Button("Edit Pin\nLocation") { onEditPin() }
                        .font(.system(size: 15, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PinpointTheme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                }

                Text("Drag a numbered shot to move it · tap for details")
                    .font(.caption.weight(.semibold)).padding(8)
                    .background(.black.opacity(0.8), in: Capsule()).foregroundStyle(.white)
                    .allowsHitTesting(false)
                if !suggestions.isEmpty {
                    Text("\(suggestions.count) suggested shots · saved when you continue")
                        .font(.caption.weight(.semibold)).padding(8)
                        .background(.black.opacity(0.8), in: Capsule()).foregroundStyle(.white)
                }
                if let expected = hole?.expectedShotCount, mappedShots.count != expected {
                    Text("Score implies \(expected) shots + \(puttCount) putts. \(mappedShots.count) shots on map — add/remove shots or edit score.")
                        .font(.caption.weight(.semibold)).padding(10)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }
                if mappedShots.isEmpty {
                    Text("No shots logged yet. Add a shot or review detected swings.")
                        .font(.caption.weight(.semibold)).padding(10)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }
                Spacer()
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(spacing: 10) {
                        Button { addingShot = true } label: {
                            Label("Add shot", systemImage: "plus").font(.caption.bold())
                                .foregroundStyle(.white).padding(12)
                                .background(.black.opacity(0.9), in: Capsule())
                        }.buttonStyle(.plain)
                        Menu {
                            Button("Add shot") { addingShot = true }
                            Button("End round") { if saveReviewedShots() { showEndRound = true } }
                            Button("Edit first putt", action: onEditPutt)
                            Button("Save & return to hole map") { if saveReviewedShots() { onMenu() } }
                        } label: {
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
                        if saveReviewedShots() { onNext() }
                    } label: {
                        Text(rounds.activeRound?.nextHole(after: holeNumber) == nil ? "Save Shots & Scorecard" : "Save Shots & Next Hole")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(PinpointTheme.primaryText, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog("Fairway result", isPresented: $showFairway, titleVisibility: .visible) {
            Button("Hit fairway") { rounds.updateHole(holeNumber) { $0.recordedFairwayHit = true } }
            Button("Missed fairway") { rounds.updateHole(holeNumber) { $0.recordedFairwayHit = false } }
            Button("Use shot location automatically") { rounds.updateHole(holeNumber) { $0.recordedFairwayHit = nil } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Uses the tee shot’s finish (shot 2’s location) and mapped fairway boundaries. Map data © OpenStreetMap contributors, ODbL.")
        }
        .sheet(isPresented: $showEndRound) { EndRoundSheet(onEnded: onMenu) }
        .alert("Shot position not saved", isPresented: $moveError) {
            Button("OK", role: .cancel) { }
        } message: { Text(rounds.lastError ?? "Try moving the shot again.") }
        .onAppear { position = layout.cameraPosition(pin: pin); updateSuggestions() }
        .onChange(of: hole) { _, _ in updateSuggestions() }
        .onChange(of: selectedShot) { _, id in
            if let id {
                if let shot = mappedShots.first(where: { $0.id == id }) { editingShot = shot }
                else { reviewingSwing = rounds.activeRound?.swingCandidates?.first(where: { $0.id == id }) }
            }
            selectedShot = nil
        }
        .sheet(item: $editingShot) { shot in
            ShotEditorView(holeNumber: holeNumber, holeYardage: rounds.activeRound?.hole(holeNumber)?.yardage ?? 0,
                existing: suggestions.contains(where: { $0.id == shot.id }) ? nil : shot,
                suggested: suggestions.first(where: { $0.id == shot.id }),
                prefillStart: mappedEnds.first(where: { $0.shot.id == shot.id })?.end ?? tee,
                prefillEnd: endpoint(after: shot.id),
                onDeleteSuggestion: suggestions.contains(where: { $0.id == shot.id }) ? {
                    rounds.updateHole(holeNumber) { $0.dismissedShotSuggestions = ($0.dismissedShotSuggestions ?? 0) + 1 }
                } : nil)
        }
        .sheet(item: $reviewingSwing) { SwingReviewSheet(event: $0) }
        .sheet(isPresented: $addingShot) {
            ShotEditorView(holeNumber: holeNumber, holeYardage: rounds.activeRound?.hole(holeNumber)?.yardage ?? 0, prefillStart: tee)
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
                    Text(suggestions.isEmpty ? "Saved shots" : "Shots")
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
        mappedShots.enumerated().compactMap { index, shot in
            // Swing locations, not landing positions: the previous shot's end is the next origin.
            let origin = shot.start ?? (index == 0 ? tee : mappedShots[index - 1].end)
                ?? layout.point(afterTravelling: Double(index) / Double(max(1, mappedShots.count)) * layout.project(pin).length, toward: pin)
            return (shot, origin)
        }
    }

    private func endpoint(after id: UUID) -> GeoPoint? {
        guard let index = mappedEnds.firstIndex(where: { $0.shot.id == id }) else { return nil }
        let next = index + 1 < mappedEnds.count ? mappedEnds[index + 1].end : nil
        return mappedEnds[index].shot.mappedEndpoint(nextStart: next, firstPutt: hole?.firstPuttPosition,
                                                      pin: pin, putts: hole?.recordedPutts)
    }

    private var mappedLegs: [ShotOverviewLeg] {
        var legs: [ShotOverviewLeg] = []
        for (index, item) in mappedEnds.enumerated() {
            guard let end = endpoint(after: item.shot.id) else { continue }
            let next = index + 1 < mappedEnds.count ? mappedEnds[index + 1] : nil
            let estimated = item.shot.start == nil || suggestions.contains { $0.id == item.shot.id }
                || next.map { next in next.shot.start == nil || suggestions.contains { $0.id == next.shot.id } } == true
            legs.append(ShotOverviewLeg(startID: item.shot.id,
                endID: next?.shot.id ?? (hole?.firstPuttPosition != nil ? puttMarkerID : nil),
                start: item.end, end: end, estimated: estimated))
        }
        if let firstPutt = hole?.firstPuttPosition, puttCount > 0 {
            legs.append(ShotOverviewLeg(startID: puttMarkerID, endID: flagMarkerID, start: firstPutt,
                                        end: pin, estimated: false, isPutt: true))
        }
        return legs
    }

    private func moveShot(_ id: UUID, _ point: GeoPoint) {
        guard let shot = mappedShots.first(where: { $0.id == id }) else { return }
        if !rounds.moveShot(holeNumber, shot: shot, to: point) { moveError = true }
    }

    /// Stable identities and vacant stroke numbers prevent edits from shuffling estimates.
    private func updateSuggestions() {
        suggestions = rounds.suggestedMappedShots(holeNumber, retaining: suggestions)
    }

    private func saveReviewedShots() -> Bool {
        guard rounds.confirmMappedShots(holeNumber, suggestions: suggestions) else { moveError = true; return false }
        updateSuggestions()
        return true
    }

    private func suggestedClub(for shot: TrackedShot) -> GolfClub? {
        guard let start = mappedEnds.first(where: { $0.shot.id == shot.id })?.end,
              let end = endpoint(after: shot.id) else { return nil }
        return CaddieEngine.suggestedShotClub(for: start.yards(to: end), bag: rounds.clubBag)
    }

    private var overviewMarkers: [ShotOverviewMarker] {
        var result = mappedEnds.map { item in
            ShotOverviewMarker(id: item.shot.id, point: item.end, number: String(item.shot.number),
                title: "\(item.shot.lie.code), \(item.shot.club?.shortName ?? suggestedClub(for: item.shot)?.shortName ?? "?")", color: UIColor(PinpointTheme.accent), movable: true)
        }
        result.append(ShotOverviewMarker(id: flagMarkerID, point: pin, number: "⚑", title: "Pin", color: .systemYellow))
        if puttCount > 0, let firstPutt = hole?.firstPuttPosition {
            result.append(ShotOverviewMarker(id: puttMarkerID, point: firstPutt, number: String(puttCount),
                title: "Putts" + (hole?.firstPuttFeet.map { " · 1st putt \(Int($0.rounded())) ft" } ?? ""), color: .systemGreen))
        }
        result += (rounds.activeRound?.swingCandidates ?? []).filter { $0.hole == holeNumber && $0.state == .pending }.compactMap { event in
            guard let lat = event.latitude, let lon = event.longitude else { return nil }
            return ShotOverviewMarker(id: event.id, point: GeoPoint(latitude: lat, longitude: lon), number: "?", title: "Review swing", color: .systemOrange)
        }
        return result
    }

    private func shotPin(_ shot: TrackedShot) -> some View {
        HStack(alignment: .top, spacing: 3) {
            ZStack {
                TeePinShape()
                    .fill(PinpointTheme.accent)
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
            out.append(LegAnnotation(id: i, coordinate: mid.coordinate, text: "\(suggestions.isEmpty ? "" : "~")\(yards) Yds"))
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
