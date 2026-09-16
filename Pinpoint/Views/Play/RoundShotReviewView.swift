import SwiftUI
import MapKit

/// Read-only review of a specific saved round, independent of the round being played.
struct RoundShotReviewView: View {
    let round: GolfRound
    @State var holeNumber: Int
    @State private var selectedShot: UUID?
    @State private var mapShot: TrackedShot?
    private var hole: HoleScore? { round.score(for: holeNumber) }
    private var shots: [TrackedShot] { (hole?.shots ?? []).sorted { $0.number < $1.number } }
    private var numbers: [Int] { round.holeScores.map(\.holeNumber).sorted() }
    private func distance(for shot: TrackedShot) -> Double? {
        if let hole, let layout = round.playLayout(for: holeNumber), let pin = round.pinCoordinate(for: holeNumber),
           let leg = hole.recordedShotLegs(tee: layout.tee, pin: pin).first(where: { $0.id == shot.id }) {
            return leg.start.yards(to: leg.end)
        }
        return shot.mappedDistanceYards ?? shot.traveledYards
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(holeNumber == numbers.first).accessibilityLabel("Previous hole")
                    Picker("Hole", selection: $holeNumber) { ForEach(numbers, id: \.self) { Text("Hole \($0)").tag($0) } }
                        .frame(maxWidth: .infinity)
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(holeNumber == numbers.last).accessibilityLabel("Next hole")
                }
                if let hole {
                    Text("Par \(round.hole(holeNumber)?.par ?? 0) · \(hole.hasScore ? "Score \(hole.grossScore)" : "No final score") · \(hole.hasKnownPutts ? "\(hole.putts) putts" : "Putts unknown")")
                        .font(.headline)
                    if let layout = round.playLayout(for: holeNumber), let pin = round.pinCoordinate(for: holeNumber) {
                        shotMap(hole: hole, layout: layout, pin: pin)
                    }
                    Text("\(shots.filter { !$0.isPutt }.count) saved shots · \(hole.penaltyStrokes) penalty strokes")
                        .font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                    if let feet = hole.firstPuttFeet { Text("First putt: \(Int(feet.rounded())) ft").font(.subheadline) }
                    if shots.isEmpty {
                        ContentUnavailableView("No shots recorded", systemImage: "mappin.slash", description: Text("The scorecard is preserved even when individual shots were not logged."))
                    }
                    ForEach(shots) { shot in
                        Button { selectedShot = selectedShot == shot.id ? nil : shot.id } label: { shotCard(shot) }.buttonStyle(.plain)
                    }
                    if let note = hole.analysisNote, !note.isEmpty { Text(note).font(.subheadline) }
                    if !hole.dictateTranscript.isEmpty {
                        DisclosureGroup("Voice recap transcript") { Text(hole.dictateTranscript).font(.subheadline) }
                    }
                }
            }.padding(20).padding(.bottom, FloatingNavigation.clearance)
        }.background(PinpointTheme.background).navigationTitle("Hole-by-hole shots").navigationBarTitleDisplayMode(.inline)
            .onChange(of: holeNumber) { _, _ in selectedShot = nil }
            .sheet(item: $mapShot) { shot in
                NavigationStack {
                    ScrollView { shotCard(shot).padding(20) }
                        .navigationTitle("Shot \(shot.number)").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { mapShot = nil } } }
                }.presentationDetents([.medium, .large])
            }
    }
    private func shotMap(hole: HoleScore, layout: HoleLayout, pin: GeoPoint) -> some View {
        Map(initialPosition: layout.cameraPosition(pin: pin)) {
            ForEach(hole.recordedShotLegs(tee: layout.tee, pin: pin)) { leg in
                MapPolyline(coordinates: [leg.start.coordinate, leg.end.coordinate]).stroke(.white, lineWidth: 2)
            }
            MapKit.Annotation("Pin", coordinate: pin.coordinate) { Image(systemName: "flag.fill").foregroundStyle(.white).shadow(radius: 2) }
            ForEach(shots) { shot in
                if let start = shot.start {
                    MapKit.Annotation("Shot \(shot.number)", coordinate: start.coordinate) {
                        Button { selectedShot = shot.id; mapShot = shot } label: {
                            Text("\(shot.number)").font(.headline).foregroundStyle(.white).frame(width: 32, height: 32)
                                .background(selectedShot == shot.id ? Color.black : PinpointTheme.accent, in: Circle())
                        }.accessibilityLabel("Review shot \(shot.number)")
                    }
                }
            }
        }.mapStyle(.imagery(elevation: .flat)).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 18)).id(holeNumber)
    }
    private func shotCard(_ shot: TrackedShot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(shot.isPutt ? "Putt" : "Shot") \(shot.number) · \(shot.club?.displayName ?? "Club unknown")").font(.headline)
                Spacer()
                Image(systemName: selectedShot == shot.id ? "chevron.up" : "chevron.down").font(.caption)
            }
            if let distance = distance(for: shot) { Text("Distance: \(Int((shot.isPutt ? distance * 3 : distance).rounded())) \(shot.isPutt ? "ft" : "yd")") }
            else { Text("Distance not recorded").foregroundStyle(PinpointTheme.secondaryText) }
            if selectedShot == shot.id {
                Text("Lie: \(shot.lie.label)\(shot.lieWasInferred == true ? " (estimated)" : "")")
                if let carry = shot.carryYards { Text("Carry: \(Int(carry.rounded())) yd") }
                if let contact = shot.contact { Text("Contact: \(contact.label)") }
                if let shape = shot.shape { Text("Shape: \(shape.label)") }
                if let finish = shot.observations?.finish { Text("Finish: \(finish.rawValue)") }
                if let miss = shot.observations?.lateralMiss { Text("Miss direction: \(miss.rawValue)") }
                if let depth = shot.observations?.depthMiss { Text("Depth: \(depth.rawValue)") }
                if let puttBreak = shot.observations?.puttBreak { Text("Putt break: \(puttBreak.rawValue)") }
                if let miss = shot.observations?.puttMissSide { Text("Putt miss: \(miss.rawValue)") }
                if let remaining = shot.remainingFeet { Text("Remaining: \(Int(remaining.rounded())) ft") }
                if let penalties = hole?.penaltiesByShot?[shot.number], penalties > 0 { Text("Penalty strokes: \(penalties)") }
                if !shot.note.isEmpty { Text(shot.note).foregroundStyle(PinpointTheme.secondaryText) }
                if shot.start == nil { Text("Location not recorded").foregroundStyle(PinpointTheme.secondaryText) }
            }
        }.font(.subheadline).foregroundStyle(PinpointTheme.primaryText).padding(18).pinpointCard()
    }
    private func move(_ delta: Int) {
        guard let index = numbers.firstIndex(of: holeNumber), numbers.indices.contains(index + delta) else { return }
        holeNumber = numbers[index + delta]
    }
}

struct RoundDetailStatsView: View {
    let round: GolfRound
    var body: some View {
        let evidence = GolfEvidence(rounds: [round])
        PlayUI.card {
            Text("Inside this round").font(.headline)
            HStack {
                StatTile(title: "Penalties", value: "\(evidence.penalties)")
                StatTile(title: "Three-putts", value: "\(evidence.threePutts)", subtitle: "\(evidence.putting.count) known holes")
                StatTile(title: "Shots logged", value: "\(round.holeScores.reduce(0) { $0 + $1.shots.filter { !$0.isPutt }.count })")
            }
            Text("Scoring by hole type").font(.subheadline.bold())
            Text(evidence.scoringBreakdown).font(.subheadline)
            if !evidence.clubBreakdown.isEmpty {
                Text("Club distances").font(.subheadline.bold())
                Text(evidence.clubBreakdown).font(.subheadline)
            }
            if !evidence.patternBreakdown.isEmpty {
                Text("Shot patterns").font(.subheadline.bold())
                Text(evidence.patternBreakdown).font(.subheadline)
            }
        }
    }
}
