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
                .profileToolbar()
        }
    }
}

private struct MeRoundsView: View {
    @State private var deleting: GolfRound?
    @State private var confirmingBulkDelete = false
    @Environment(RoundStore.self) private var store
    @Environment(GolfCloudSync.self) private var golfSync
    private var rounds: [GolfRound] {
        ((store.activeRound.map { [$0] } ?? []) + store.pastRounds.filter { $0.id != store.activeRound?.id })
            .sorted { $0.startedAt > $1.startedAt }
    }
    /// Backup duplicates from the old bug: rounds with "copy" in the course
    /// name. The active round is never included in bulk delete.
    private var duplicateCopies: [GolfRound] {
        rounds.filter { $0.id != store.activeRound?.id && $0.courseName.range(of: "copy", options: .caseInsensitive) != nil }
    }
    var body: some View {
        List {
                PinpointPageHeading(title: "Your rounds.", subtitle: "Scorecards, stats and the story of every round.")
                if rounds.isEmpty {
                    ContentUnavailableView("No rounds yet", systemImage: "flag", description: Text("Your rounds will appear here once you start playing."))
                }
                if let detail = store.cloudErrorDetail {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't reach your backend rounds — showing this device only.")
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        Button { Task { await golfSync.sync() } } label: {
                            Label(store.cloudSyncing ? "Syncing…" : "Retry sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                        }.buttonStyle(.plain).disabled(store.cloudSyncing)
                            .foregroundStyle(PinpointTheme.accentText)
                    }.foregroundStyle(PinpointTheme.primaryText).padding(18).pinpointCard()
                }
                if !duplicateCopies.isEmpty {
                    Button { confirmingBulkDelete = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Delete \(duplicateCopies.count) duplicate \(duplicateCopies.count == 1 ? "round" : "rounds")")
                                    .font(.subheadline.weight(.semibold))
                                Text("Rounds with \"copy\" in the name, left over from the old backup bug.")
                                    .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        }.foregroundStyle(PinpointTheme.primaryText).padding(18).pinpointCard()
                    }.buttonStyle(.plain)
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
        .confirmationDialog(
            "Delete \(duplicateCopies.count) duplicate \(duplicateCopies.count == 1 ? "round" : "rounds")?",
            isPresented: $confirmingBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(duplicateCopies.count) \(duplicateCopies.count == 1 ? "round" : "rounds")", role: .destructive) {
                for round in duplicateCopies { _ = store.deleteRound(round.id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("They'll be removed from this device and your synced devices. This can't be undone.")
        }
    }
}
