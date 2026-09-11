import SwiftUI

/// Review-later hub: rounds history, club distances, scoring trends.
struct PlayStatsView: View {
    @Environment(RoundStore.self) private var rounds
    @State private var showClubs = false

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        overviewCard
                        clubsCard
                        historyCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("My Golf")
            .sheet(isPresented: $showClubs) {
                ClubBagView()
                    .preferredColorScheme(.dark)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var overviewCard: some View {
        let s = rounds.allRoundsStats
        return PlayUI.card {
            Text("Course & Round Stats")
                .font(.headline)
            if s.holesPlayed == 0 {
                Text("Track a round and your averages, fairways, greens and putts will live here.")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            } else {
                HStack(spacing: 10) {
                    StatTile(title: "Avg / hole", value: s.averageScore.map { String(format: "%.1f", $0) } ?? "–")
                    StatTile(title: "Fairways", value: s.fairwayPct.map { "\(Int($0))%" } ?? "–")
                    StatTile(title: "GIR", value: s.girPct.map { "\(Int($0))%" } ?? "–")
                }
                HStack(spacing: 10) {
                    StatTile(title: "Putts", value: "\(s.totalPutts)")
                    StatTile(title: "Avg 1st putt", value: s.avgFirstPuttFt.map { "\(Int($0)) ft" } ?? "–")
                    StatTile(title: "Holes", value: "\(s.holesPlayed)")
                }
            }
        }
    }

    private var clubsCard: some View {
        let bag = rounds.clubBag.displayClubs.filter { !$0.club.isPutter }
        return PlayUI.card {
            HStack {
                Text("My Bag")
                    .font(.headline)
                Spacer()
                Button("Edit distances") { showClubs = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PinpointTheme.accent)
            }
            Text("The GPS map picks a club from these carries as you drag.")
                .font(.caption)
                .foregroundStyle(PinpointTheme.secondaryText)
            if bag.isEmpty {
                Text("Add clubs to your bag to see recommendations on the map.")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(bag.prefix(3))) { entry in
                        StatTile(title: entry.shortLabel,
                                 value: "\(Int(entry.carryYards.rounded()))",
                                 subtitle: "Yds")
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        PlayUI.card {
            Text("Rounds Played")
                .font(.headline)
            if rounds.pastRounds.isEmpty && rounds.activeRound == nil {
                Text("No finished rounds yet.")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            if let active = rounds.activeRound {
                NavigationLink {
                    ActiveRoundView()
                } label: {
                    historyRow(title: active.courseName,
                               subtitle: "In progress · Hole \(active.currentHoleNumber)",
                               trailing: "\(active.totalGross)")
                }
                .buttonStyle(.plain)
            }
            ForEach(rounds.pastRounds) { round in
                NavigationLink {
                    RoundSummaryView()
                } label: {
                    historyRow(title: round.courseName,
                               subtitle: "\(round.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(round.holeScores.count) holes",
                               trailing: "\(round.totalGross)")
                }
                .buttonStyle(.plain)
                Divider().background(PinpointTheme.hairline)
            }
        }
    }

    private func historyRow(title: String, subtitle: String, trailing: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            Spacer()
            Text(trailing)
                .font(.headline.monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(PinpointTheme.secondaryText)
        }
        .padding(.vertical, 6)
    }
}
