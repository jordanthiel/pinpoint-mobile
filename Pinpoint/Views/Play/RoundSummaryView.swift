import SwiftUI

/// Post-round summary: to-par hero, hole strip, strokes-gained-lite,
/// recap, club review prompt, and history entry.
struct RoundSummaryView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    @State private var recap = ""
    @State private var showClubs = false

    var body: some View {
        ZStack {
            PinpointTheme.background.ignoresSafeArea()
            if let round = rounds.activeRound ?? rounds.pastRounds.first {
                ScrollView {
                    VStack(spacing: 16) {
                        hero(round: round)
                        holeStrip(round: round)
                        statsCard(round: round)
                        analysisCard(round: round)
                        recapCard(round: round)
                        Button {
                            showClubs = true
                        } label: {
                            Text("Edit My Bag")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        if round.status == .active {
                            Button {
                                rounds.setRecap(recap)
                                rounds.finishRound()
                                dismiss()
                            } label: {
                                Text("Exit & Save Round")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(16)
                }
                .navigationTitle("Round Recap")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { recap = round.recap }
                .sheet(isPresented: $showClubs) {
                    ClubBagView()
                        .preferredColorScheme(.dark)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func hero(round: GolfRound) -> some View {
        VStack(spacing: 6) {
            Text(round.courseName)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 24) {
                VStack {
                    Text("To Par")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(round.toParLabel)
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                }
                VStack {
                    Text("Gross/Net")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(round.totalGross)/\(round.totalGross)")
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                }
            }
            Text("Par \(round.totalPar) · \(round.teeName) · \(round.durationLabel)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.16),
                                    Color(red: 0.14, green: 0.10, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func holeStrip(round: GolfRound) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(round.holeScores) { hs in
                        VStack(spacing: 2) {
                            Text("\(hs.holeNumber)")
                                .font(.caption2)
                                .foregroundStyle(PinpointTheme.secondaryText)
                            Text(hs.hasScore ? "\(hs.grossScore)" : "–")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(hs.hasScore
                                    ? PlayUI.scoreColor(score: hs.grossScore,
                                                        par: round.hole(hs.holeNumber)?.par ?? 4)
                                    : PinpointTheme.secondaryText)
                        }
                        .frame(width: 36)
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
            Text("Strokes Gained Stats")
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
                                .foregroundStyle(PinpointTheme.accent)
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
                .foregroundStyle(PinpointTheme.accent)
            TextField("Highlight or key takeaway from this round…", text: $recap, axis: .vertical)
                .lineLimit(3...)
                .padding(10)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

