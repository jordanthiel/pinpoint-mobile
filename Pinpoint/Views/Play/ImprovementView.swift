import SwiftUI

struct ImprovementView: View {
    @Environment(RoundStore.self) private var rounds
    @State private var selected: PracticeFocus?
    private var sessions: [PracticeSession] { rounds.practiceSessions }
    private var evidence: GolfEvidence { GolfEvidence(rounds: Array(rounds.pastRounds.prefix(5)) + (rounds.activeRound.map { [$0] } ?? [])) }
    /// Practice priorities target scratch (the goal); the Insights tab offers
    /// peer-level views for where the golfer is right now.
    private var plan: PracticeRecommendation {
        evidence.practiceRecommendation(level: .default)
    }

    var embedded = false
    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack { content } }
        }
    }
    private var content: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PinpointPageHeading(title: "Practice with purpose.", subtitle: "A focused plan built from your recent rounds. Work on one thing, measure it, then take it to the course.")
                    HStack(spacing: 10) {
                        StatTile(title: "Sessions", value: "\(sessions.count)")
                        StatTile(title: "This week", value: "\(sessions.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }.count)")
                        StatTile(title: "Evidence", value: "\(evidence.completed.count)", subtitle: "scored holes")
                    }
                    if plan.primary == nil && evidence.focus.isEmpty {
                        PlayUI.card {
                            Label("Build your baseline", systemImage: "scope").font(.title2.bold())
                            Text("Track scores, putts, penalties and fairways to reveal your priorities. Start with a distance-control session while your golf profile grows.").foregroundStyle(PinpointTheme.secondaryText)
                            Button("Start a putting baseline") { start(baseline) }.buttonStyle(PrimaryButtonStyle())
                        }
                    } else if plan.primary != nil {
                        Text("YOUR FOCUS AREAS").font(.caption.bold()).foregroundStyle(PinpointTheme.secondaryText)
                        Text("Ranked by strokes lost vs scratch × recurrence × controllability × sample confidence.").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        Text(plan.takeaway).font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                        ForEach(Array([plan.primary, plan.secondary].compactMap { $0 }.enumerated()), id: \.element.category) { index, focus in
                            PlayUI.card {
                                HStack {
                                    Label("\(index + 1). \(focus.title)", systemImage: focus.category.icon).font(.title3.bold())
                                    Spacer()
                                    Text(focus.kind.rawValue.capitalized).font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                                }
                                Text(focus.cause).font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                                Text(focus.drill).font(.subheadline)
                                Text(focus.target).font(.subheadline.bold()).foregroundStyle(PinpointTheme.accentText)
                                Text("Transfer check: \(focus.transferMetric) — now \(focus.transferBaseline). Re-measure over the next 5 and 10 rounds.")
                                    .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                                let practiceFocus = PracticeFocus(id: focus.category.rawValue, title: focus.title, icon: focus.category.icon,
                                                                  evidence: focus.cause, opportunity: focus.priority,
                                                                  drill: focus.drill, target: focus.target)
                                let recent = sessions.filter { $0.focus == focus.title }.prefix(3)
                                if !recent.isEmpty {
                                    Text("Recent results: " + recent.map { "\($0.made)/\($0.attempts)" }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                                }
                                Button("Log a practice session") { start(practiceFocus) }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    } else {
                        Text("YOUR FOCUS AREAS").font(.caption.bold()).foregroundStyle(PinpointTheme.secondaryText)
                        Text("Ranked by recorded frequency and practice priority, not estimated strokes gained. Add shot distances to unlock strokes-gained priorities.").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        ForEach(Array(evidence.focus.enumerated()), id: \.element.id) { index, focus in
                            PlayUI.card {
                                HStack {
                                    Label("\(index + 1). \(focus.title)", systemImage: focus.icon).font(.title3.bold())
                                    Spacer()
                                }
                                Text(focus.evidence).font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                                Text(focus.drill).font(.subheadline)
                                Text(focus.target).font(.subheadline.bold()).foregroundStyle(PinpointTheme.accentText)
                                let recent = sessions.filter { $0.focus == focus.title }.prefix(3)
                                if !recent.isEmpty {
                                    Text("Recent results: " + recent.map { "\($0.made)/\($0.attempts)" }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                                }
                                Button("Log a practice session") { start(focus) }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    }
                    if !sessions.isEmpty {
                        Text("Practice journal").font(.title2.bold())
                        ForEach(sessions.prefix(20)) { session in
                            PlayUI.card {
                                HStack {
                                    Text(session.focus).font(.headline)
                                    Spacer()
                                    Text("\(session.made)/\(session.attempts)").font(.headline.monospacedDigit()).foregroundStyle(PinpointTheme.accentText)
                                }
                                Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                                if !session.note.isEmpty { Text(session.note).font(.subheadline) }
                            }
                        }
                    }
                }.padding(20)
            }.contentMargins(.bottom, FloatingNavigation.clearance, for: .scrollContent)
            .background(PinpointTheme.background)
                .navigationTitle(embedded ? "Me" : "Improve").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $selected) { focus in
                    PracticeSessionEditor(focus: focus) { session in
                        rounds.savePracticeSession(session)
                    }
                }
        }
    }
    private func start(_ focus: PracticeFocus) { selected = focus }
    private var baseline: PracticeFocus {
        PracticeFocus(id: "baseline", title: "Putting distance baseline", icon: "flag", evidence: "", opportunity: 0,
                      drill: "Roll 5 balls from each of 20, 30 and 40 feet. Count balls that finish inside a 3-foot circle. Repeat the same setup next session to compare your results.", target: "Goal: 12 of 15 inside 3 feet")
    }
}

/// Own the form state in the presented view so its first render uses this drill's defaults.
private struct PracticeSessionEditor: View {
    let focus: PracticeFocus
    let onSave: (PracticeSession) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var made = 0
    @State private var attempts: Int
    @State private var note = ""
    @State private var saveFailed = false

    init(focus: PracticeFocus, onSave: @escaping (PracticeSession) -> Bool) {
        self.focus = focus
        self.onSave = onSave
        _attempts = State(initialValue: focus.id == "tee" ? 10 : focus.id == "control" ? 20 : 15)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(focus.title) { Text(focus.drill); Text(focus.target).font(.headline) }
                Section("Your result") {
                    Stepper("Attempts: \(attempts)", value: $attempts, in: 1...100)
                    Stepper("On target: \(made)", value: $made, in: 0...attempts)
                    TextField("What felt different?", text: $note, axis: .vertical).lineLimit(3...6)
                }
                if saveFailed { Text("Couldn't save this session. Please try again.").foregroundStyle(.red) }
            }
            .onChange(of: attempts) { _, value in made = min(made, value) }
            .navigationTitle("Practice session").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(PracticeSession(focus: focus.title, made: made, attempts: attempts, note: note)) { dismiss() }
                        else { saveFailed = true }
                    }
                }
            }
        }
    }
}
