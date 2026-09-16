import SwiftUI

/// Score entry with optional putting details and explicit save/skip actions.
/// Saving preserves mapped shots, penalties, and fairway details.
struct HoleScoreEntryView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var holeNumber: Int
    var onFinished: () -> Void = {}
    var onSkip: () -> Void = {}
    var isLastHole = false
    var advancesOnSave = true
    var saveButtonTitle: String?

    @State private var score: Int = 0
    @State private var penalties = 0
    @State private var penaltyAssignments: [Int: Int] = [:]
    @State private var showPenalties = false
    @State private var puttsEdited = false
    @State private var initialized = false
    @State private var putts: Int = 2
    @State private var trackPutts = true
    @State private var saveError: String?
    @State private var showExtendedScores = false

    private var holeDef: GolfHole? {
        rounds.activeRound?.hole(holeNumber)
    }

    private var hole: HoleScore? {
        rounds.activeRound?.score(for: holeNumber)
    }

    private var par: Int { holeDef?.par ?? 4 }

    private var scoreValues: [Int] {
        let values = showExtendedScores ? Array(1...12) : Array(1...9)
        return score == 0 || values.contains(score) ? values : (values + [score]).sorted()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        scoreSection

                        Divider()

                        puttsSection
                        if score > 0 {
                            Divider()
                            Button { showPenalties.toggle() } label: {
                                Label(penalties > 0 ? "Penalties (\(penalties))" : "Penalties", systemImage: "exclamationmark.circle")
                            }.font(.headline).foregroundStyle(PinpointTheme.accentText)
                            if showPenalties { penaltiesSection.id("penalty-strokes") }
                        }


                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .onChange(of: showPenalties) { _, showing in
                    if showing { withAnimation { reader.scrollTo("penalty-strokes", anchor: .bottom) } }
                }
                }
            }
            .navigationTitle("Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { bottomRow }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: score) { _, value in
                if !puttsEdited {
                    putts = HoleScore.suggestedPutts(score: value, par: par, penalties: penalties,
                        nonPuttingShots: hole?.shots.filter { !$0.isPutt }.count ?? 0)
                } else { putts = min(putts, max(0, value - penalties)) }
                reconcilePenalties()
            }
            .onChange(of: putts) { _, _ in reconcilePenalties() }
            .onChange(of: trackPutts) { _, _ in reconcilePenalties() }
            .alert("Score not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "Please try again.") }
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Score")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
                Button(showExtendedScores ? "Less" : "Others") {
                    showExtendedScores.toggle()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PinpointTheme.accentText)
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(scoreValues, id: \.self) { value in
                    scoreTile(value)
                }
            }
            if showExtendedScores || score > 12 {
                Stepper(score == 0 ? "Choose score" : "Score: \(score)", value: $score, in: 0...99)

            }
        }
    }

    private func scoreTile(_ value: Int) -> some View {
        Button {
            score = value
        } label: {
            ZStack {
                if value == par {
                    VStack(spacing: 0) {
                        Text("\(value)")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.black)
                        Text("Par")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                } else {
                    scoreGlyph(value)
                    Text("\(value)")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                score == value ? PinpointTheme.accentMuted : PinpointTheme.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Score \(value)\(value == par ? ", par" : "")")
        .accessibilityAddTraits(score == value ? .isSelected : [])
    }

    /// Golf scoring glyphs: circles under par, squares over par, doubled for
    /// eagle-or-better / double-bogey-or-worse.
    private func scoreGlyph(_ value: Int) -> some View {
        Group {
            if value < par - 1 {
                doubleCircle
            } else if value == par - 1 {
                singleCircle
            } else if value == par + 1 {
                singleSquare
            } else {
                doubleSquare
            }
        }
    }

    private var glyphStroke: some ShapeStyle {
        Color.black.opacity(0.35)
    }

    private var singleCircle: some View {
        Circle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 46, height: 46)
    }

    private var doubleCircle: some View {
        ZStack {
            Circle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 48, height: 48)
            Circle().stroke(glyphStroke, lineWidth: 1).frame(width: 42, height: 42)
        }
    }

    private var singleSquare: some View {
        Rectangle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 44, height: 44)
    }

    private var doubleSquare: some View {
        ZStack {
            Rectangle().stroke(glyphStroke, lineWidth: 1.5).frame(width: 46, height: 46)
            Rectangle().stroke(glyphStroke, lineWidth: 1).frame(width: 40, height: 40)
        }
    }

    private var puttsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Track putts", isOn: $trackPutts)
                .font(.headline)
            if trackPutts {
                HStack(spacing: 10) {
                    ForEach(0...4, id: \.self) { value in
                        Button {
                            puttsEdited = true
                            putts = value
                        } label: {
                            Text("\(value)")
                                .font(.title2)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(putts == value ? PinpointTheme.accentMuted : PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(value > score)
                        .accessibilityLabel("\(value) putts")
                        .accessibilityAddTraits(putts == value ? .isSelected : [])
                    }
                }
                if score > 0 {
                    Text("\(physicalShots) shots · \(putts) putts" + (penalties > 0 ? " · \(penalties) penalty strokes" : ""))
                        .font(.subheadline.weight(.semibold))
                }
                Stepper("Putts: \(putts)", value: Binding(get: { putts }, set: { puttsEdited = true; putts = $0 }), in: 0...score)
                if !puttsEdited && score > 0 {
                    Text("Suggested from your score · tap to change").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Save just your score. Add putting details later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.black)
    }

    private var physicalShots: Int { max(0, score - (trackPutts ? putts : 0) - penalties) }

    private var penaltiesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which Strokes Resulted In Penalties?").font(.headline)
            ForEach(Array(1...max(1, physicalShots)), id: \.self) { stroke in
                HStack {
                    Text("Stroke \(stroke)").font(.headline)
                    Spacer()
                    Button { changePenalty(stroke, by: -1) } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44).background(Color.gray.opacity(0.08), in: Circle())
                    }.disabled((penaltyAssignments[stroke] ?? 0) == 0)
                    Text("\(penaltyAssignments[stroke] ?? 0)").font(.title.monospacedDigit()).frame(minWidth: 36)
                    Button { changePenalty(stroke, by: 1) } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44).background(Color.gray.opacity(0.08), in: Circle())
                    }.disabled(!canAddPenalty(to: stroke))
                }.buttonStyle(.plain)
            }
            if penalties > penaltyAssignments.values.reduce(0, +) {
                Text("\(penalties - penaltyAssignments.values.reduce(0, +)) existing penalties need a stroke. Use + to assign them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Your score includes penalties. Increase the score or adjust putts if there are too few strokes to assign a penalty.")
                .font(.caption).foregroundStyle(.secondary)
        }.foregroundStyle(.black)
    }

    private func canAddPenalty(to stroke: Int) -> Bool {
        let unassigned = penalties - penaltyAssignments.values.reduce(0, +)
        let remaining = physicalShots - (unassigned > 0 ? 0 : 1)
        return stroke <= remaining && (penaltyAssignments.keys.max() ?? 0) <= remaining
    }

    private func changePenalty(_ stroke: Int, by delta: Int) {
        if delta > 0 {
            guard canAddPenalty(to: stroke) else { return }
            if penalties == penaltyAssignments.values.reduce(0, +) { penalties += 1 }
            penaltyAssignments[stroke, default: 0] += 1
        } else if let count = penaltyAssignments[stroke], count > 0 {
            penaltyAssignments[stroke] = count - 1
            penalties -= 1
        }
        penaltyAssignments = penaltyAssignments.filter { $0.value > 0 }
    }

    private func reconcilePenalties() {
        penalties = min(penalties, max(0, score - (trackPutts ? putts : 0) - 1))
        var remaining = penalties
        penaltyAssignments = penaltyAssignments.keys.sorted().reduce(into: [:]) { result, stroke in
            guard stroke <= physicalShots else { return }
            let count = min(remaining, penaltyAssignments[stroke] ?? 0)
            if count > 0 { result[stroke] = count; remaining -= count }
        }
    }

    private var bottomRow: some View {
        VStack(spacing: 8) {
            Button(saveButtonTitle ?? (!advancesOnSave ? "Save Changes" : (isLastHole ? "Save & View Scorecard" : "Save & Next Hole"))) {
                if rounds.saveScoreEntry(holeNumber, score: score, putts: trackPutts ? putts : nil, penalties: penalties, penaltiesByShot: penaltyAssignments) {
                    onFinished()
                } else {
                    saveError = rounds.lastError
                }
            }
            .disabled(score == 0)
            .opacity(score == 0 ? 0.45 : 1)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(PinpointTheme.primaryText, in: Capsule())
            .buttonStyle(.plain)
            Button(!advancesOnSave ? "Cancel" : (hole?.hasScore == true ? "Continue without changes" : "Skip Hole — Score Later"), action: onSkip)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .foregroundStyle(PinpointTheme.accentText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(.white)
    }

    private func prefill() {
        guard !initialized else { return }; initialized = true
        guard let hole, holeDef != nil else {
            score = 0
            putts = 2
            return
        }
        trackPutts = hole.hasKnownPutts || !hole.hasScore
        if let recorded = hole.recordedScore {
            score = recorded
        } else if hole.isComplete && hole.hasScore {
            score = hole.grossScore
        } else {
            score = 0
        }
        if let recorded = hole.recordedPutts {
            putts = recorded
        } else if hole.hasScore {
            putts = hole.putts
        } else {
            putts = 2
        }
        penalties = hole.penaltyStrokes
        penaltyAssignments = hole.penaltiesByShot ?? [:]
        puttsEdited = hole.hasKnownPutts
        putts = min(putts, max(0, score - penalties))
        showExtendedScores = score > 9
    }

}
