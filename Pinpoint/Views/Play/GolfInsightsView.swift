import SwiftUI
import Charts

struct GolfInsightsView: View {
    @Environment(RoundStore.self) private var store
    @Environment(SwingLibraryStore.self) private var library
    @State private var scope = 5
    @State private var question = ""
    @State private var messages: [CoachMessage] = []
    @State private var busy = false
    @State private var replyTask: Task<Void, Never>?
    @State private var showHistory = false
    @State private var showAccount = false
    @State private var showBag = false
    @FocusState private var composing: Bool

    private var selected: [GolfRound] {
        let all = (store.pastRounds + (store.activeRound.map { [$0] } ?? [])).sorted { $0.startedAt > $1.startedAt }
        return scope == 0 ? all : Array(all.prefix(scope))
    }
    private var evidence: GolfEvidence { GolfEvidence(rounds: selected) }

    var onShowRounds: (() -> Void)? = nil
    var embedded = false
    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack { content } }
        }
    }
    private var content: some View {
        Group {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PinpointPageHeading(title: "Your game, understood.", subtitle: "Insights, progress and everything about your golf.")
                        Picker("Rounds to analyze", selection: $scope) {
                            Text("Last round").tag(1)
                            Text("Last 5").tag(5)
                            Text("All rounds").tag(0)
                        }.pickerStyle(.segmented).disabled(busy)
                        if let focus = evidence.focus.first {
                            PlayUI.card {
                                Label("YOUR NEXT OPPORTUNITY", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(PinpointTheme.accentText)
                                Text(focus.title).font(.title2.bold())
                                Text(focus.evidence).foregroundStyle(PinpointTheme.secondaryText)
                                Text("Explore the drill and track a session in Improve.").font(.caption)
                            }
                        } else {
                            PlayUI.card {
                                Label("YOUR INSIGHTS", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(PinpointTheme.accentText)
                                Text("Your next insight starts on the course.").font(.title2.bold())
                                Text("Save scores and shots to uncover your scoring patterns, strengths and where to improve.")
                                    .foregroundStyle(PinpointTheme.secondaryText)
                            }
                        }
                        personalCard
                        HStack(spacing: 10) {
                            StatTile(title: "Scored holes", value: "\(evidence.completed.count)")
                            StatTile(title: "Fairways", value: GolfEvidence.percentage(evidence.fairways), subtitle: "\(evidence.fairways.count) recorded")
                            StatTile(title: "Greens", value: GolfEvidence.percentage(evidence.greens), subtitle: "\(evidence.greens.count) inferred")
                        }
                        trendCard
                        if !evidence.completed.isEmpty {
                            PlayUI.card {
                                Text("Inside the numbers").font(.headline)
                                HStack(spacing: 10) {
                                    StatTile(title: "Three-putts", value: "\(evidence.threePutts)", subtitle: "\(evidence.putting.count) known holes")
                                    StatTile(title: "Penalties", value: "\(evidence.penalties)", subtitle: "recorded strokes")
                                }
                                DisclosureGroup("Scoring by hole type") { Text(evidence.scoringBreakdown).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) }
                                DisclosureGroup("Club distances & shot patterns") {
                                    Text(evidence.clubBreakdown.isEmpty ? "No measured club distances in this selection." : evidence.clubBreakdown).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(evidence.patternBreakdown).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            if !library.isSignedIn { Button("Sign in for OpenAI") { showAccount = true }.font(.caption) }
                            Label("Ask your golf coach", systemImage: "sparkles").font(.title2.bold())
                            Text("Answers use the rounds selected above. Questions and selected golf data are sent to OpenAI. Sign in to use the coach; recorded-data summaries also work offline.")
                                .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                            ForEach(["Where should I focus my practice?", "What does my putting data show?", "How far do I actually hit each club?"], id: \.self) { prompt in
                                Button { ask(prompt) } label: {
                                    HStack { Text(prompt); Spacer(); Image(systemName: "arrow.up.right") }
                                        .font(.subheadline).padding(14).background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain).disabled(busy)
                            }
                        }
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(message.isUser ? "You" : message.engine, systemImage: message.isUser ? "person.circle" : "sparkles")
                                    .font(.caption.bold()).foregroundStyle(PinpointTheme.accentText)
                                Text(message.text).textSelection(.enabled)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.isUser ? PinpointTheme.surfaceElevated : PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if busy { ProgressView("Reviewing your recorded game…").frame(maxWidth: .infinity) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .background(PinpointTheme.background)
            .navigationTitle("Me").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { if let onShowRounds { onShowRounds() } else { showHistory = true } } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Round history and bag") } }
            .sheet(isPresented: $showHistory) { PlayStatsView() }
            .sheet(isPresented: $showAccount) { AccountView() }
            .sheet(isPresented: $showBag) { ClubBagView() }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask about your game…", text: $question, axis: .vertical)
                        .lineLimit(1...4).focused($composing).padding(12)
                        .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
                    Button { ask(question) } label: {
                        Image(systemName: "arrow.up").font(.headline).frame(width: 46, height: 46)
                            .background(PinpointTheme.primaryText, in: Circle()).foregroundStyle(.white)
                    }.accessibilityLabel("Ask coach").disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 12)
                    .padding(.bottom, FloatingNavigation.clearance)
            }
            .onChange(of: scope) { _, _ in messages.removeAll() }
            .onDisappear { replyTask?.cancel(); busy = false }
        }
    }

    private var personalCard: some View {
        let handicap = HandicapEstimate(rounds: store.pastRounds)
        return PlayUI.card {
            Text("My game").font(.headline)
            NavigationLink { HandicapDetailView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Estimated handicap").font(.subheadline)
                        Text(handicap.value == nil ? "\(handicap.entries.count) of 3 eligible rounds" : "See counting rounds & calculation")
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    }
                    Spacer()
                    Text(handicap.displayValue).font(.system(size: 36, weight: .semibold)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption)
                }.padding(.vertical, 8)
            }.buttonStyle(.plain)
            Divider()
            Button { if let onShowRounds { onShowRounds() } else { showHistory = true } } label: {
                Label("My rounds & scorecards", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }.buttonStyle(.plain)
            Button { showBag = true } label: {
                Label("My bag & distances", systemImage: "figure.golf")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }.buttonStyle(.plain)
            Button { showAccount = true } label: {
                Label(library.isSignedIn ? "My account & sync" : "Sign in & sync my game", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }.buttonStyle(.plain)
        }
    }

    private var trendCard: some View {
        let points = selected.reversed().filter { !$0.completedHoles.isEmpty }
        return PlayUI.card {
            Text("Scoring trend").font(.headline)
            Text("Average strokes over par per completed hole").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
            if points.count >= 2 {
                Chart(points) { round in
                    let value = GolfEvidence(rounds: [round]).averageToPar ?? 0
                    LineMark(x: .value("Round", round.startedAt), y: .value("Over par / hole", value))
                        .foregroundStyle(PinpointTheme.accentText).symbol(.circle)
                }.frame(height: 150).chartYAxis { AxisMarks(position: .leading) }
            } else {
                Text("Score holes in at least two rounds to see your trend.")
                    .font(.subheadline).foregroundStyle(PinpointTheme.secondaryText).padding(.vertical, 16)
            }
        }
    }

    private func ask(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty else { return }
        composing = false
        question = ""
        let facts = evidence
        let history = messages.suffix(4).map { "\($0.isUser ? "User" : "Coach"): \($0.text)" }.joined(separator: "\n")
        messages.append(CoachMessage(text: text, isUser: true, engine: ""))
        busy = true
        replyTask = Task { @MainActor in
            let reply = await GolfCoach.answer(text, evidence: facts, history: history)
            guard !Task.isCancelled else { return }
            messages.append(CoachMessage(text: reply.text, isUser: false, engine: reply.engine))
            busy = false
        }
    }
}

private struct CoachMessage: Identifiable {
    let id = UUID()
    var text: String
    var isUser: Bool
    var engine: String
}
