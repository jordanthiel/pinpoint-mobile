import SwiftUI

/// Post-round summary: to-par hero, hole strip, strokes-gained-lite,
/// recap, club review prompt, and history entry.
struct RoundSummaryView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var selectedRound: GolfRound? = nil

    @State private var showEnd = false
    @State private var showScorecard = false
    @State private var recap = ""
    @State private var showClubs = false

    var body: some View {
        ZStack {
            PinpointTheme.background.ignoresSafeArea()
            if let round = selectedRound ?? rounds.activeRound ?? rounds.pastRounds.first {
                ScrollView {
                    VStack(spacing: 16) {
                        hero(round: round)
                        Button { showScorecard = true } label: {
                            Label("Scorecard & hole stats", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity)
                        }.buttonStyle(SecondaryButtonStyle())
                        holeStrip(round: round)
                        NavigationLink { RoundShotReviewView(round: round, holeNumber: round.holeScores.first?.holeNumber ?? 1) } label: {
                            Label("Review shots hole by hole", systemImage: "map").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle())
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
                .sheet(isPresented: $showScorecard) { ScorecardView(selectedRound: round) }
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
            }
        }
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
                        NavigationLink { RoundShotReviewView(round: round, holeNumber: hs.holeNumber) } label: {
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

