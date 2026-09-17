import SwiftUI

/// Post-round summary: to-par hero, hole strip, strokes-gained-lite,
/// recap, club review prompt, and history entry.
struct RoundSummaryView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(GolfCloudSync.self) private var golfSync
    @Environment(\.dismiss) private var dismiss

    var selectedRoundID: UUID? = nil

    @State private var showEnd = false
    @State private var showScorecard = false
    @State private var recap = ""
    @State private var showClubs = false
    @State private var benchmark: BenchmarkLevel = .default

    var body: some View {
        ZStack {
            PinpointTheme.background.ignoresSafeArea()
            if let round = rounds.round(id: selectedRoundID) {
                ScrollView {
                    VStack(spacing: 16) {
                        hero(round: round)
                        Button { showScorecard = true } label: {
                            Label("Scorecard & hole stats", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity)
                        }.buttonStyle(SecondaryButtonStyle())
                        holeStrip(round: round)
                        NavigationLink { RoundShotReviewView(roundID: round.id, holeNumber: round.holeScores.first?.holeNumber ?? 1) } label: {
                            Label("\(round.holeScores.reduce(0) { $0 + $1.shots.count }) tracked shots · Review by hole", systemImage: "map").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle())
                        roundStrokesGainedCard(round: round)
                        statsCard(round: round)
                        RoundDetailStatsView(round: round)
                        analysisCard(round: round)
                        if round.status == .active && round.id == rounds.activeRound?.id { recapCard(round: round) }
                        else if !round.recap.isEmpty { Text(round.recap) }
                        Button {
                            showClubs = true
                        } label: {
                            Text("Edit My Bag")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        if round.status == .active && round.id == rounds.activeRound?.id {
                            Button {
                                showEnd = true
                            } label: {
                                Text("End round")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(16)
                }
                .contentMargins(.bottom, FloatingNavigation.clearance, for: .scrollContent)
                .sheet(isPresented: $showScorecard) { ScorecardView(selectedRoundID: round.id) }
                .navigationTitle("Round Recap")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { recap = round.recap }
                .sheet(isPresented: $showEnd) { EndRoundSheet(recap: recap) { dismiss() } }
                .sheet(isPresented: $showClubs) {
                    ClubBagView()
                        .preferredColorScheme(.light)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            } else {
                ContentUnavailableView("Round unavailable", systemImage: "flag.slash",
                    description: Text("Return to Rounds and refresh your history."))
            }
        }
        .task(id: selectedRoundID) {
            if selectedRoundID != nil { await golfSync.sync() }
        }
        .refreshable { await golfSync.sync() }
    }

    private func hero(round: GolfRound) -> some View {
        VStack(spacing: 6) {
            Text(round.historyLabel).font(.subheadline.weight(.semibold))
            Text(round.courseName)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 24) {
                VStack {
                    Text("To Par · Finished Holes")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(round.completedToParLabel)
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                }
                VStack {
                    Text("Score")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(round.totalGross)")
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                }
            }
            Text("Scored par \(round.completedHoles.reduce(0) { $0 + (round.hole($1.holeNumber)?.par ?? 4) }) · \(round.teeName) · \(round.durationLabel)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [PinpointTheme.primaryText, PinpointTheme.primaryText],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func holeStrip(round: GolfRound) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(round.playedHoleScores) { hs in
                        NavigationLink { RoundShotReviewView(roundID: round.id, holeNumber: hs.holeNumber) } label: {
                        VStack(spacing: 2) {
                            Text("\(hs.holeNumber)")
                                .font(.caption2)
                                .foregroundStyle(PinpointTheme.secondaryText)
                            Text(hs.hasScore ? "\(hs.grossScore)" : "–")
                                .frame(height: 34)
                                .background { if hs.hasScore { ScoreMark(score: hs.grossScore, par: round.hole(hs.holeNumber)?.par ?? 4, size: 30) } }
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(hs.hasScore
                                    ? PlayUI.scoreColor(score: hs.grossScore,
                                                        par: round.hole(hs.holeNumber)?.par ?? 4)
                                    : PinpointTheme.secondaryText)
                        }
                        .frame(width: 36)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statsCard(round: GolfRound) -> some View {
        let s = rounds.stats(for: [round])
        return PlayUI.card {
            Text("Round performance")
                .font(.headline)
            HStack(spacing: 10) {
                StatTile(title: "Fairways", value: s.fairwayPct.map { "\(Int($0))%" } ?? "–",
                         subtitle: "\(s.fairwaysHit)/\(s.fairwaysTotal)")
                StatTile(title: "GIR", value: s.girPct.map { "\(Int($0))%" } ?? "–",
                         subtitle: "\(s.girHit)/\(s.girTotal)")
                StatTile(title: "Putts", value: "\(s.totalPutts)")
            }
            if let avg = s.avgFirstPuttFt {
                Text("Avg 1st putt \(Int(avg)) ft")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
        }
    }

    private func roundStrokesGainedCard(round: GolfRound) -> some View {
        let core = Core11.compute(rounds: [round], level: benchmark)
        return PlayUI.card {
            HStack {
                Text("Strokes gained · this round").font(.headline)
                Spacer()
                Picker("Benchmark", selection: $benchmark) {
                    ForEach(BenchmarkLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }.pickerStyle(.menu)
            }
            Text("Vs \(benchmark.label). Shot positions and GPS origins count — explicit distances win ties.")
                .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
            if core.hasSG {
                HStack(alignment: .firstTextBaseline) {
                    Text(signed(core.sgTotal.perRound)).font(.system(size: 36, weight: .semibold)).monospacedDigit()
                    Text("total · \(core.sgTotal.shots) valued shots")
                        .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                }
                ForEach(ShotCategory.allCases) { category in
                    roundSGBar(category: category, value: core.sg(category).perRound)
                }
                HStack(spacing: 10) {
                    StatTile(title: "Driving dist", value: core.effectiveDrivingDistance.map { "\(Int($0.rounded())) yd" } ?? "–")
                    StatTile(title: "Damaging", value: pct(core.damaging.rawValue), subtitle: "\(core.damagingPenalties) pen · \(core.damagingRecoveries) rec")
                    StatTile(title: "GIR", value: pct(core.girOverall.rawValue), subtitle: "\(core.girOverall.made)/\(core.girOverall.opportunities)")
                }
                HStack(spacing: 10) {
                    StatTile(title: "Up & down", value: pct(core.upAndDown.rawValue), subtitle: "\(core.upAndDown.made)/\(core.upAndDown.opportunities)")
                    StatTile(title: "Three-putt", value: pct(core.threePutt.rawValue), subtitle: "\(core.threePutt.made)/\(core.threePutt.opportunities)")
                    StatTile(title: "Double+", value: pct(core.doublePlus.rawValue), subtitle: "\(core.doublePlus.made)/\(core.doublePlus.opportunities)")
                }
                DisclosureGroup("Strokes gained by hole") {
                    ForEach(holeSG(round: round), id: \.number) { row in
                        HStack {
                            Text("Hole \(row.number)").font(.subheadline)
                            Spacer()
                            Text("\(row.score)").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                            Text(signed(row.sg)).font(.subheadline.monospacedDigit())
                                .foregroundStyle(row.sg >= 0 ? Color.green : Color.red)
                        }
                    }
                }.font(.subheadline)
                let autopsies = DoubleAutopsy.autopsy(rounds: [round])
                if !autopsies.isEmpty {
                    DisclosureGroup("Where the doubles started (\(autopsies.count))") {
                        ForEach(autopsies) { item in
                            HStack {
                                Text("Hole \(item.holeNumber)").font(.subheadline)
                                Spacer()
                                Text(item.primary.label + (item.secondary.isEmpty ? "" : " · +" + item.secondary.map(\.label).joined(separator: ", ")))
                                    .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                            }
                        }
                    }.font(.subheadline)
                }
                Text("Baseline \(ExpectedStrokes.modelVersion).")
                    .font(.caption2).foregroundStyle(PinpointTheme.secondaryText)
            } else {
                Text("No valued shots in this round yet.").font(.subheadline.weight(.semibold))
                Text("Shots need a start position (GPS origin or distance) and a finish to value — \(core.sgTotal.shots) valued so far. Map shots on the hole view or add distances in the shot editor.")
                    .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
            }
        }
    }

    private func holeSG(round: GolfRound) -> [(number: Int, score: Int, sg: Double)] {
        round.playedHoleScores.compactMap { hole in
            guard hole.isComplete, hole.hasScore, let def = round.hole(hole.holeNumber) else { return nil }
            let valuation = ShotValuation.value(hole: hole, par: def.par, level: benchmark,
                                                pin: round.pinCoordinate(for: hole.holeNumber))
            guard !valuation.shots.isEmpty else { return nil }
            return (hole.holeNumber, hole.grossScore, valuation.totalSG)
        }.sorted { $0.number < $1.number }
    }

    private func roundSGBar(category: ShotCategory, value: Double?) -> some View {
        HStack {
            Text(category.shortLabel).font(.caption.bold().monospacedDigit()).frame(width: 36, alignment: .leading)
            if let value {
                Capsule().fill(value >= 0 ? Color.green : Color.red)
                    .frame(width: max(4, min(90, abs(value) * 22)), height: 8)
                Text(signed(value)).font(.subheadline.monospacedDigit())
            } else {
                Text("– low sample").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
            }
            Spacer()
        }
    }

    private func signed(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%+.1f", value)
    }

    private func pct(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func analysisCard(round: GolfRound) -> some View {
        let notes = round.holeScores.compactMap { hole -> (Int, String)? in
            let note = hole.analysisNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !note.isEmpty else { return nil }
            return (hole.holeNumber, note)
        }
        return Group {
            if !notes.isEmpty {
                PlayUI.card {
                    Text("AI hole notes")
                        .font(.headline)
                    ForEach(notes, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hole \(item.0)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PinpointTheme.accentText)
                            Text(item.1)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private func recapCard(round: GolfRound) -> some View {
        PlayUI.card {
            Text("Add Round Recap")
                .font(.headline)
                .foregroundStyle(PinpointTheme.accentText)
            TextField("Highlight or key takeaway from this round…", text: $recap, axis: .vertical)
                .lineLimit(3...)
                .padding(10)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

