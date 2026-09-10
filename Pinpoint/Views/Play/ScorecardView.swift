import SwiftUI

/// Scorecard with Scores / Stats tabs, mirroring the reference layout:
/// hole columns, par/handicap rows, gross + net, per-hole dots.
struct ScorecardView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    @State private var tab: CardTab = .scores
    @State private var showSummary = false

    enum CardTab: String, CaseIterable, Identifiable {
        case scores = "Scores"
        case stats = "Stats"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                if let round = rounds.activeRound ?? rounds.pastRounds.first {
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
            .navigationDestination(isPresented: $showSummary) {
                RoundSummaryView()
            }
        }
    }

    private func header(round: GolfRound) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName)
                    .font(.title3.weight(.bold))
                Text("\(round.teeName) · \(round.roundType.label)")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            Spacer()
            VStack {
                Text("Gross/Net")
                    .font(.caption2)
                    .foregroundStyle(PinpointTheme.secondaryText)
                Text("\(round.totalGross)/\(round.totalGross)")
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            .padding(10)
            .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    ZStack {
                        if hs.hasScore {
                            let par = round.hole(hs.holeNumber)?.par ?? 4
                            Circle()
                                .stroke(PlayUI.scoreColor(score: hs.grossScore, par: par), lineWidth: 1.5)
                                .frame(width: 34, height: 34)
                                .opacity(hs.grossScore == par ? 0 : 1)
                        }
                        Text(hs.hasScore ? "\(hs.grossScore)" : "–")
                            .font(.headline.monospacedDigit())
                    }
                    .frame(minWidth: 44)
                    .padding(.vertical, 8)
                }
                Text("\(round.totalGross)")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 52)
            }
            GridRow {
                Text("Putts").font(.caption).foregroundStyle(PinpointTheme.secondaryText).padding(8)
                ForEach(holes) { hs in
                    Text(hs.hasScore ? "\(hs.putts)" : "–")
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
                guard let def = round.hole(hs.holeNumber),
                      let fw = hs.fairwayHit(par: def.par) else { return "–" }
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
            statRow(title: "Putts", holes: holes) { hs in hs.hasScore ? "\(hs.putts)" : "–" } total: {
                "\(holes.reduce(0) { $0 + $1.putts })"
            }
            statRow(title: "Pen.", holes: holes) { hs in hs.hasScore ? "\(hs.penaltyStrokes)" : "–" } total: {
                "\(holes.reduce(0) { $0 + $1.penaltyStrokes })"
            }
        }
        .padding(.horizontal, 8)
    }

    private func statRow(title: String, holes: [HoleScore],
                         value: (HoleScore) -> String, total: () -> String) -> some View {
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
            if round.status == .active {
                Button {
                    showSummary = true
                } label: {
                    Text("Finish Round")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }
}
