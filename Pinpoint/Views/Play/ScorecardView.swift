import SwiftUI

/// Scorecard with Scores / Stats tabs, mirroring the reference layout:
/// hole columns, par/handicap rows, gross + net, per-hole dots.
struct ScorecardView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var selectedRoundID: UUID? = nil
    @State private var tab: CardTab = .scores
    @State private var showSummary = false
    @State private var editingHole: HoleScore?
    @State private var reviewingHole: HoleScore?

    enum CardTab: String, CaseIterable, Identifiable {
        case scores = "Scores"
        case stats = "Stats"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                if let round = rounds.round(id: selectedRoundID) {
                    VStack(spacing: 0) {
                        header(round: round)
                        Picker("Card", selection: $tab) {
                            ForEach(CardTab.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(12)
                        ScrollView([.horizontal, .vertical]) {
                            if tab == .scores {
                                scoresGrid(round: round)
                            } else {
                                statsGrid(round: round)
                            }
                        }
                        footer(round: round)
                    }
                } else {
                    Text("No rounds yet.")
                        .foregroundStyle(PinpointTheme.secondaryText)
                }
            }
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $editingHole) { hole in
                HoleScoreEntryView(holeNumber: hole.holeNumber,
                    onFinished: { editingHole = nil }, onSkip: { editingHole = nil },
                    advancesOnSave: false)
                    .preferredColorScheme(.light)
                    .presentationDetents([.large])
            }
            .fullScreenCover(item: $reviewingHole) { hole in
                if selectedRoundID == nil, rounds.activeRound != nil {
                    PostScoreFlow(holeNumber: hole.holeNumber, initialStep: .shots) { reviewingHole = nil }
                } else if let round = rounds.round(id: selectedRoundID) {
                    NavigationStack {
                        RoundShotReviewView(roundID: round.id, holeNumber: hole.holeNumber)
                            .toolbar { ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { reviewingHole = nil }
                            } }
                    }
                }
            }
            .navigationDestination(isPresented: $showSummary) {
                RoundSummaryView(selectedRoundID: selectedRoundID)
            }
        }
    }

    private func header(round: GolfRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(round.startedAt.formatted(date: .numeric, time: .omitted)) · Duration: \(round.durationLabel)")
                .font(.caption)
                .foregroundStyle(PinpointTheme.secondaryText)
            Text("\(round.holeScores.filter(\.hasScore).count) of \(round.holeScores.count) holes scored\(selectedRoundID == nil && round.status == .active ? " · Tap a score to edit" : "")")
                .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(round.courseName)
                        .font(.title3.weight(.bold))
                    if let tee = round.handicapTee ?? (round.courseID == SampleCourses.georgetown.id ? SampleCourses.georgetown.tee(named: round.teeName) : nil) {
                        Text("\(round.teeName) · \(String(format: "%.1f", tee.rating))/\(tee.slope) (Rating/Slope)")
                            .font(.subheadline)
                            .foregroundStyle(PinpointTheme.accentText)
                    } else {
                        Text("\(round.teeName) · \(round.roundType.label)")
                            .font(.subheadline)
                            .foregroundStyle(PinpointTheme.secondaryText)
                    }
                }
                Spacer()
                VStack {
                    Text("Strokes")
                        .font(.caption2)
                        .foregroundStyle(PinpointTheme.secondaryText)
                    Text("\(round.totalGross)")
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                .padding(10)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
    }

    // MARK: - Scores grid

    private func scoresGrid(round: GolfRound) -> some View {
        let holes = round.holeScores
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                gridHead("Hole")
                ForEach(holes) { hs in gridHead("\(hs.holeNumber)") }
                gridHead("Total")
            }
            .background(PinpointTheme.surfaceElevated)
            GridRow {
                Text("Par").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    .padding(8)
                ForEach(holes) { hs in
                    Text("\(round.hole(hs.holeNumber)?.par ?? 4)")
                        .font(.subheadline.monospacedDigit())
                        .frame(minWidth: 44)
                        .padding(.vertical, 8)
                }
                Text("\(round.totalPar)").font(.subheadline.weight(.bold)).frame(minWidth: 52)
            }
            GridRow {
                Text("Hcp").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    .padding(8)
                ForEach(holes) { hs in
                    Text("\(round.hole(hs.holeNumber)?.handicap ?? 0)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PinpointTheme.secondaryText)
                        .frame(minWidth: 44)
                        .padding(.vertical, 4)
                }
                Text("").frame(minWidth: 52)
            }
            Divider()
            GridRow {
                Text("Gross").font(.caption.weight(.bold)).padding(8)
                ForEach(holes) { hs in
                    Button {
                        if selectedRoundID == nil && round.status == .active { editingHole = hs }
                    } label: {
                    ZStack {
                        if hs.hasScore {
                            let par = round.hole(hs.holeNumber)?.par ?? 4
                            ScoreMark(score: hs.grossScore, par: par)
                                .foregroundStyle(PlayUI.scoreColor(score: hs.grossScore, par: par))
                        }
                        Text(hs.hasScore ? "\(hs.grossScore)" : "–")
                            .font(.headline.monospacedDigit())
                    }
                    .frame(minWidth: 44)
                    .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedRoundID != nil || round.status != .active)
                    .accessibilityLabel("Hole \(hs.holeNumber), \(hs.hasScore ? "score \(hs.grossScore)" : "not scored"), edit score")
                }
                Text("\(round.totalGross)")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 52)
            }
            GridRow {
                Text("Shots").font(.caption.weight(.bold)).padding(8)
                ForEach(holes) { hs in
                    Button {
                        reviewingHole = hs
                    } label: {
                        let count = hs.shots.filter { !$0.isPutt }.count
                        Text(count == 0 ? (selectedRoundID == nil && round.status == .active ? "Add" : "—") : "\(count)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(PinpointTheme.accentText)
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Hole \(hs.holeNumber), \(hs.shots.filter { !$0.isPutt }.count) saved shots, review or add shots")
                }
                Text("\(holes.reduce(0) { $0 + $1.shots.filter { !$0.isPutt }.count })")
                    .font(.subheadline.weight(.bold)).frame(minWidth: 52)
            }
            GridRow {
                Text("Putts").font(.caption).foregroundStyle(PinpointTheme.secondaryText).padding(8)
                ForEach(holes) { hs in
                    Text(hs.hasKnownPutts ? "\(hs.putts)" : "–")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(PinpointTheme.secondaryText)
                        .frame(minWidth: 44)
                }
                Text("\(holes.reduce(0) { $0 + $1.putts })")
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 52)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Stats grid

    private func statsGrid(round: GolfRound) -> some View {
        let holes = round.holeScores
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                gridHead("Stat")
                ForEach(holes) { hs in gridHead("\(hs.holeNumber)") }
                gridHead("Total")
            }
            .background(PinpointTheme.surfaceElevated)
            statRow(title: "Fairway", holes: holes) { hs in
                guard let fw = round.fairwayHit(for: hs.holeNumber) else { return "–" }
                return fw ? "✓" : "✗"
            } total: {
                let s = rounds.stats(for: [round])
                return s.fairwayPct.map { "\(Int($0))%" } ?? "–"
            }
            statRow(title: "GIR", holes: holes) { hs in
                guard let def = round.hole(hs.holeNumber),
                      let gir = hs.greenInRegulation(par: def.par) else { return "–" }
                return gir ? "✓" : "✗"
            } total: {
                let s = rounds.stats(for: [round])
                return s.girPct.map { "\(Int($0))%" } ?? "–"
            }
            statRow(title: "Putts", holes: holes) { hs in hs.hasKnownPutts ? "\(hs.putts)" : "–" } total: {
                "\(holes.reduce(0) { $0 + $1.putts })"
            }
            statRow(title: "Pen.", holes: holes) { hs in hs.hasScore ? "\(hs.penaltyStrokes)" : "–" } total: {
                "\(holes.reduce(0) { $0 + $1.penaltyStrokes })"
            }
        }
        .padding(.horizontal, 8)
    }

    private func statRow(title: String, holes: [HoleScore],
                         value: @escaping (HoleScore) -> String, total: @escaping () -> String) -> some View {
        GridRow {
            Text(title).font(.caption).foregroundStyle(PinpointTheme.secondaryText).padding(8)
            ForEach(holes) { hs in
                Text(value(hs))
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 44)
                    .padding(.vertical, 8)
            }
            Text(total()).font(.subheadline.weight(.bold)).frame(minWidth: 52)
        }
    }

    private func gridHead(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(PinpointTheme.secondaryText)
            .frame(minWidth: 44)
            .padding(.vertical, 8)
    }

    private func footer(round: GolfRound) -> some View {
        HStack(spacing: 10) {
            if selectedRoundID == nil && round.status == .active {
                Button {
                    dismiss()
                } label: {
                    Text("Back to GPS")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    showSummary = true
                } label: {
                    Text("Finish Round")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }
}
