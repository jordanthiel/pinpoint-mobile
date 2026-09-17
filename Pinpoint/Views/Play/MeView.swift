import SwiftUI

struct MeView: View {
    private enum Section: String, CaseIterable { case rounds = "Rounds", improve = "Improve", insights = "Insights" }
    @State private var section: Section = .insights
    @Environment(RoundStore.self) private var store
    @Environment(GolfCloudSync.self) private var golfSync
    private var hasLocalRounds: Bool {
        store.activeRound != nil || !store.pastRounds.isEmpty
    }

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
                if !store.cloudHistoryLoaded && !hasLocalRounds {
                    VStack(spacing: 16) {
                        if store.accountID == nil {
                            ContentUnavailableView("Sign in to see your rounds", systemImage: "person.crop.circle",
                                description: Text("Open your profile to sign in."))
                        } else if let error = store.cloudErrorDetail {
                            ContentUnavailableView("Couldn't load your rounds", systemImage: "wifi.exclamationmark",
                                description: Text(error))
                            Button("Try again") { Task { await golfSync.refreshHistory() } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            ProgressView("Loading your golf data…")
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Each section uses the latest cloud response held in memory.
                    switch section {
                    case .rounds: MeRoundsView()
                    case .improve: ImprovementView(embedded: true)
                    case .insights: GolfInsightsView(onShowRounds: { section = .rounds }, embedded: true)
                    }
                }
            }.background(PinpointTheme.background)
                .navigationTitle("Me").navigationBarTitleDisplayMode(.inline)
                .profileToolbar()
                .task(id: "\(section.rawValue):\(store.accountID?.uuidString ?? "guest")") {
                    await golfSync.refreshHistory()
                }
                .refreshable { await golfSync.refreshHistory() }
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
                if let report = store.cloudSkipReport {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Some backend shots didn't load (\(store.cloudSkippedRecords) records).")
                            .font(.subheadline.weight(.semibold))
                        Text(report)
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                            .textSelection(.enabled)
                    }.foregroundStyle(PinpointTheme.primaryText).padding(18).pinpointCard()
                }
                if store.accountID != nil && !store.cloudHistoryLoaded {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if store.cloudSyncing { ProgressView().controlSize(.small) }
                            Text(store.cloudSyncing ? "Updating from backend…" : "Showing this device — backend update pending.")
                                .font(.subheadline.weight(.semibold))
                        }
                        if let error = store.cloudErrorDetail {
                            Text(error).font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        }
                        if !store.cloudSyncing {
                            Button { Task { await golfSync.refreshHistory() } } label: {
                                Label("Retry sync", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.subheadline.weight(.semibold))
                            }.buttonStyle(.plain).foregroundStyle(PinpointTheme.accentText)
                        }
                    }.foregroundStyle(PinpointTheme.primaryText).padding(18).pinpointCard()
                }
                if rounds.isEmpty {
                    ContentUnavailableView("No rounds yet", systemImage: "flag", description: Text("Your rounds will appear here once you start playing."))
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
                    NavigationLink { RoundSummaryView(selectedRoundID: round.id) } label: {
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
                            HStack {
                                Text("\(round.holeScores.reduce(0) { $0 + $1.shots.count }) tracked shots")
                                Spacer()
                                let core = Core11.compute(rounds: [round], level: .default)
                                if core.hasSG, let sg = core.sgTotal.perRound {
                                    Text(String(format: "SG %+.1f vs scratch", sg))
                                } else {
                                    Text("SG — insufficient shot data")
                                }
                            }.font(.caption).foregroundStyle(PinpointTheme.secondaryText)
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
