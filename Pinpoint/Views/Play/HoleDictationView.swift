import SwiftUI

struct HoleDictationView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(SwingLibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    var holeNumber: Int
    var initialTranscript: String = ""
    @State private var loadedInitialTranscript = false
    @State private var voice = VoiceCapture()
    @State private var drafts: [RecapDraft] = []
    @State private var busy = false
    @State private var usedAI = false
    @State private var parseTask: Task<Void, Never>?
    @State private var reviewedText = ""
    @State private var parseError: String?
    @State private var saveFailed = false
    @State private var showAccount = false
    @State private var confirmDiscard = false

    private var canSave: Bool {
        Set(drafts.filter(\.selected).map(\.holeNumber)).count == drafts.filter(\.selected).count &&
        !busy && !voice.isFinishing && !voice.isRecording && reviewedText == voice.transcript && drafts.contains { $0.selected } &&
        drafts.filter(\.selected).allSatisfy { draft in
            rounds.activeRound?.score(for: draft.holeNumber) != nil &&
            (draft.score == nil || (1...30).contains(draft.score!)) &&
            (draft.putts == nil || (0...15).contains(draft.putts!)) &&
            (draft.penalties == nil || (0...15).contains(draft.penalties!)) &&
            (draft.score == nil || (draft.putts ?? 0) + (draft.penalties ?? 0) <= draft.score!) &&
            draft.result.shots.allSatisfy { shot in
                (shot.distanceYards == nil || (0...500).contains(shot.distanceYards!)) &&
                (shot.leftFeet == nil || (0...1500).contains(shot.leftFeet!)) &&
                (shot.observations.carryYards == nil || (0...500).contains(shot.observations.carryYards!)) &&
                (shot.observations.startingDistanceFeet == nil || (0...3000).contains(shot.observations.startingDistanceFeet!))
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your round. In your words.").font(.largeTitle.bold())
                        Text("Tell the story of one hole or catch up on several. Say “hole 3” or “next hole” when you move on. Review everything before saving.")
                            .foregroundStyle(PinpointTheme.secondaryText)
                    }
                    Button {
                        if voice.isRecording { voice.finish() }
                        else { Task { await voice.start() } }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 30)).frame(width: 76, height: 76)
                                .background(voice.isRecording ? Color.red : PinpointTheme.accent, in: Circle())
                            Text(voice.isRecording ? "Recording · tap to transcribe" : voice.isFinishing ? "Transcribing with OpenAI…" : voice.isStarting ? "Connecting microphone…" : "Tap to talk").font(.headline)
                            Text("Starting on hole \(holeNumber)").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        }.frame(maxWidth: .infinity).padding(24)
                            .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain).disabled(voice.isStarting || voice.isFinishing || busy || (voice.pendingAudio != nil && !voice.isRecording))
                    Text("Audio is sent to OpenAI when you stop. Up to 10 minutes per recording; failed uploads stay on this device for retry.")
                        .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    if voice.isRecording {
                        HStack {
                            Text(String(format: "%d:%02d", Int(voice.elapsed) / 60, Int(voice.elapsed) % 60)).monospacedDigit()
                            ProgressView(value: Double(voice.level)).tint(PinpointTheme.accent)
                        }
                    }
                    if voice.pendingAudio != nil && !voice.isRecording && !voice.isFinishing {
                        HStack {
                            Button("Retry transcription") { voice.retryTranscription() }
                            Spacer()
                            Button("Discard audio", role: .destructive) { confirmDiscard = true }
                        }.font(.subheadline.bold())
                    }
                    if !library.isSignedIn { Button("Sign in for OpenAI") { showAccount = true }.font(.caption) }
                    if let error = voice.error { Label(error, systemImage: "info.circle").font(.subheadline).foregroundStyle(.orange) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECAP").font(.caption.weight(.bold)).foregroundStyle(PinpointTheme.secondaryText)
                        TextEditor(text: $voice.transcript)
                            .scrollContentBackground(.hidden).frame(minHeight: 140).padding(12)
                            .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Your spoken or typed recap")
                            .disabled(voice.isRecording || voice.isFinishing || busy)
                        if voice.transcript.isEmpty {
                            Text("“Hole one, scored five with two putts. Driver missed right. Hole two, par with one putt.”")
                                .font(.subheadline).foregroundStyle(PinpointTheme.secondaryText)
                        }
                    }
                    Button(action: structure) {
                        HStack {
                            if busy { ProgressView() } else { Image(systemName: "sparkles") }
                            Text(busy ? "Organizing your recap…" : "Review structured recap")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || voice.isRecording || voice.isFinishing || voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let parseError {
                        Text(parseError).font(.subheadline).foregroundStyle(.orange)
                        Button("Use basic offline parsing") { structure(useAI: false) }
                            .disabled(busy || voice.isRecording || voice.isFinishing)
                        Text("Offline parsing is less flexible. Your transcript is kept so you can retry AI later.")
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    }
                    if !drafts.isEmpty {
                        Text(usedAI ? "Interpreted by OpenAI · confirm before saving" : "Extracted with local rules · check each hole")
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        ForEach($drafts) { $draft in
                            draftCard($draft)
                        }
                        Text("Saving replaces earlier voice shots on these holes and updates the fields shown. Other shots are kept. Blank fields remain unrecorded or keep their existing value.")
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                        Button {
                            if rounds.applyRecaps(drafts) { dismiss() }
                            else { saveFailed = true }
                        } label: {
                            Text("Save \(drafts.filter(\.selected).count) holes").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle()).disabled(!canSave)
                        if saveFailed { Text("Couldn't save the recap. Your draft is still here; please try again.").font(.subheadline).foregroundStyle(.orange) }
                        if !canSave && reviewedText == voice.transcript {
                            Text("Select each hole only once and check your numbers: score 1–30, putts and penalties 0–15, and putts plus penalties no greater than score. Carry must be 0–500 yards.").font(.caption).foregroundStyle(.orange)
                        }
                        if reviewedText != voice.transcript {
                            Text("Your recap changed. Review it again before saving.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }.padding(20)
            }
            .background(PinpointTheme.background).navigationTitle("Voice recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showAccount) { AccountView() }
            .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard audio", role: .destructive) { voice.discardRecording() }
            }
            .onAppear {
                if !loadedInitialTranscript {
                    loadedInitialTranscript = true
                    if !initialTranscript.isEmpty { voice.transcript = initialTranscript }
                }
            }
            .onDisappear { voice.stop(); parseTask?.cancel() }
        }
    }

    private func draftCard(_ binding: Binding<RecapDraft>) -> some View {
        let draft = binding.wrappedValue
        let validHole = rounds.activeRound?.score(for: draft.holeNumber) != nil
        return PlayUI.card {
            Toggle("Hole \(draft.holeNumber)", isOn: binding.selected).font(.title3.bold()).disabled(!validHole)
            if !validHole { Text("This hole isn't in your active round.").foregroundStyle(.orange) }
            Picker("Hole", selection: binding.holeNumber) {
                ForEach(rounds.activeRound?.holesSnapshot ?? [], id: \.number) { hole in
                    Text("Hole \(hole.number)").tag(hole.number)
                }
            }
            ForEach(draft.result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            HStack {
                numberField("Score", value: binding.score)
                numberField("Putts", value: binding.putts)
                numberField("Penalties", value: binding.penalties)
            }
            Picker("Fairway", selection: binding.fairway) {
                Text("Not stated").tag(Optional<Bool>.none)
                Text("Hit").tag(Optional(true))
                Text("Missed").tag(Optional(false))
            }.pickerStyle(.segmented)
            if let existing = rounds.activeRound?.score(for: draft.holeNumber), existing.shots.contains(where: { $0.source != .dictation }) {
                Text("This hole already has \(existing.shots.filter { $0.source != .dictation }.count) other shots. Remove overlapping shots from this recap before saving.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(Array(draft.result.shots.enumerated()), id: \.offset) { index, shot in
                DisclosureGroup {
                    if let quote = shot.sourceQuote {
                        Text("“\(quote)”").font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    }
                    Picker("Club", selection: binding.result.shots[index].club) {
                        Text("Not stated").tag(Optional<GolfClub>.none)
                        ForEach(GolfClub.allCases) { Text($0.displayName).tag(Optional($0)) }
                    }
                    Picker("Lie", selection: binding.result.shots[index].lie) {
                        Text("Not stated").tag(Optional<Lie>.none)
                        ForEach(Lie.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    Picker("Contact", selection: binding.result.shots[index].contact) {
                        Text("Not stated").tag(Optional<Contact>.none)
                        ForEach(Contact.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    Picker("Shape", selection: binding.result.shots[index].shape) {
                        Text("Not stated").tag(Optional<ShotShape>.none)
                        ForEach(ShotShape.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    Picker("Quality", selection: binding.result.shots[index].quality) {
                        Text("Not stated").tag(Optional<ShotQuality>.none)
                        ForEach(ShotQuality.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    Picker("Finish location", selection: binding.result.shots[index].observations.finish) {
                        Text("Not stated").tag(Optional<ShotFinish>.none)
                        ForEach(ShotFinish.allCases) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Miss direction", selection: binding.result.shots[index].observations.lateralMiss) {
                        Text("Not stated").tag(Optional<LateralMiss>.none)
                        ForEach(LateralMiss.allCases) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Miss distance", selection: binding.result.shots[index].observations.depthMiss) {
                        Text("Not stated").tag(Optional<DepthMiss>.none)
                        ForEach(DepthMiss.allCases) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Putt break", selection: binding.result.shots[index].observations.puttBreak) {
                        Text("Not stated").tag(Optional<PuttBreak>.none)
                        ForEach(PuttBreak.allCases) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Putt miss side", selection: binding.result.shots[index].observations.puttMissSide) {
                        Text("Not stated").tag(Optional<PuttMissSide>.none)
                        ForEach(PuttMissSide.allCases) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Holed", selection: binding.result.shots[index].observations.holed) {
                        Text("Not stated").tag(Optional<Bool>.none)
                        Text("Yes").tag(Optional(true))
                        Text("No").tag(Optional(false))
                    }
                    HStack {
                        Text("Carry (yd)")
                        TextField("Not stated", value: binding.result.shots[index].observations.carryYards, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Started from hole (ft)")
                        TextField("Not stated", value: binding.result.shots[index].observations.startingDistanceFeet, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Shot distance (yd)")
                        TextField("Not stated", value: binding.result.shots[index].distanceYards, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Finished from hole (ft)")
                        TextField("Not stated", value: binding.result.shots[index].leftFeet, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    TextField("Shot note", text: binding.result.shots[index].note, axis: .vertical)
                    Button("Remove this shot", role: .destructive) { binding.wrappedValue.result.shots.remove(at: index) }
                } label: {
                    HStack {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(PinpointTheme.accentText)
                        Text(shot.club?.displayName ?? "Club not stated").font(.subheadline.weight(.medium))
                        Spacer()
                        Text([shot.contact?.label, shot.shape?.label, shot.distanceYards.map { "\($0.formatted(.number.precision(.fractionLength(0)))) yd" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(PinpointTheme.secondaryText)
                    }
                }
            }
            DisclosureGroup("Original words & details") {
                Text(draft.transcript).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(draft.result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }.font(.subheadline)
        }
    }

    private func numberField(_ label: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(PinpointTheme.secondaryText)
            TextField("—", value: value, format: .number).keyboardType(.numberPad)
                .font(.title2.bold()).padding(12).background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(label)
        }
    }

    private func structure() { structure(useAI: true) }

    private func structure(useAI: Bool) {
        guard let round = rounds.activeRound else { return }
        busy = true
        parseError = nil
        saveFailed = false
        drafts = []
        let text = voice.transcript
        parseTask = Task { @MainActor in
            do {
                let result: [RecapDraft]
                if useAI { result = try await RoundRecapParser.aiDrafts(text, round: round, currentHole: holeNumber) }
                else { result = RoundRecapParser.localDrafts(text, round: round, currentHole: holeNumber) }
                guard !Task.isCancelled else { return }
                drafts = result
                usedAI = useAI
                reviewedText = text
                if result.isEmpty { parseError = "No hole details were identified. Add more detail to your transcript and review again." }
            } catch {
                guard !Task.isCancelled else { return }
                parseError = error.localizedDescription
            }
            busy = false
        }
    }
}
