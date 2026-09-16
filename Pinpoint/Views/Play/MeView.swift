import SwiftUI

struct MeView: View {
    private enum Section: String, CaseIterable { case rounds = "Rounds", improve = "Improve", insights = "Insights" }
    @State private var section: Section = .insights

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(Section.allCases, id: \.self) { item in
                        Button { section = item } label: {
                            Text(item.rawValue).font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(section == item ? .white : PinpointTheme.primaryText)
                                .background(section == item ? PinpointTheme.primaryText : PinpointTheme.surface, in: Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }.padding(.horizontal, 20).padding(.vertical, 12)
                // Only the selected section runs analytics or keeps its scroll content alive.
                switch section {
                case .rounds: MeRoundsView()
                case .improve: ImprovementView(embedded: true)
                case .insights: GolfInsightsView(onShowRounds: { section = .rounds }, embedded: true)
                }
            }.background(PinpointTheme.background)
                .navigationTitle("Me").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MeRoundsView: View {
    @State private var deleting: GolfRound?
    @Environment(RoundStore.self) private var store
    private var rounds: [GolfRound] {
        ((store.activeRound.map { [$0] } ?? []) + store.pastRounds.filter { $0.id != store.activeRound?.id })
            .sorted { $0.startedAt > $1.startedAt }
    }
    var body: some View {
        List {
                PinpointPageHeading(title: "Your rounds.", subtitle: "Scorecards, stats and the story of every round.")
                if rounds.isEmpty {
                    ContentUnavailableView("No rounds yet", systemImage: "flag", description: Text("Your rounds will appear here once you start playing."))
                }
                ForEach(rounds) { round in
                    NavigationLink { RoundSummaryView(selectedRound: round) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(round.courseName).font(.headline)
                                Spacer()
                            }
                            Text(round.startedAt.formatted(date: .abbreviated, time: .omitted) + " · " + round.historyLabel)
                                .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                            HStack {
                                Text("\(round.completedHoles.count) holes scored")
                                Spacer()
                                Text(round.holeScores.contains(where: \.hasScore) ? "\(round.totalGross) strokes · \(round.completedToParLabel)" : "Not scored yet")
                                    .fontWeight(.semibold)
                            }.font(.subheadline)
                        }.foregroundStyle(PinpointTheme.primaryText).padding(18).pinpointCard()
                    }.buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { deleting = round }
                        }
                }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .contentMargins(.bottom, FloatingNavigation.clearance, for: .scrollContent)
        .confirmationDialog("Delete this round?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete round", role: .destructive) {
                if let round = deleting { _ = store.deleteRound(round.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("The round and its scores and shots will be deleted from your synced devices.") }
    }
}
