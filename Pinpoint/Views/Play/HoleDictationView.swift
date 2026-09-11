import AVFoundation
import Speech
import SwiftUI

/// End-of-hole dictation: speak (or type) what happened, preview the AI
/// structure, then apply it as real shots on the hole.
struct HoleDictationView: View {
    @Environment(RoundStore.self) private var rounds
    @Environment(\.dismiss) private var dismiss

    var holeNumber: Int

    @State private var transcript = ""
    @State private var isRecording = false
    @State private var result = HoleDictationResult(shots: [], puttsMentioned: nil, scoreCall: nil,
                                                   leftoverNote: "", confidence: 0, warnings: [])
    @State private var appliedCount: Int?
    @State private var speechDenied = false

    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer() }
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var audioEngine: AVAudioEngine?

    var body: some View {
        NavigationStack {
            ZStack {
                PinpointTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hole \(holeNumber) — AI recap")
                            .font(.title3.weight(.bold))
                        Text("Dictate the hole the way you’d tell a playing partner. Pinpoint turns clubs, contact, shape, and lie into structured shots, and parks leftover color in a note for later analysis.")
                            .font(.subheadline)
                            .foregroundStyle(PinpointTheme.secondaryText)
                        Button {
                            transcript = HoleDictationParser.examplePrompt
                            result = HoleDictationParser.parse(transcript)
                        } label: {
                            Label("Try an example hole", systemImage: "text.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PinpointTheme.accent)

                        recordRow

                        TextEditor(text: $transcript)
                            .frame(minHeight: 110)
                            .padding(10)
                            .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PinpointTheme.hairline, lineWidth: 1))
                            .onChange(of: transcript) { _, new in
                                result = HoleDictationParser.parse(new)
                            }

                        parsePreview

                        Button {
                            let n = rounds.applyDictation(result, to: holeNumber)
                            rounds.updateHole(holeNumber) {
                                $0.dictateTranscript = transcript
                            }
                            appliedCount = n
                        } label: {
                            Label(applyLabel, systemImage: "sparkles")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(result.isEmpty)

                        if let appliedCount {
                            Text("Applied \(appliedCount) entr\(appliedCount == 1 ? "y" : "ies") to Hole \(holeNumber). Review them in the shot trail.")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("AI Hole Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear { stopRecording() }
        }
    }

    private var applyLabel: String {
        var bits: [String] = []
        if !result.shots.isEmpty { bits.append("\(result.shots.count) shot\(result.shots.count == 1 ? "" : "s")") }
        if let p = result.puttsMentioned { bits.append("\(p) putt\(p == 1 ? "" : "s")") }
        if bits.isEmpty { return "Structure & Apply" }
        return "Apply \(bits.joined(separator: " + "))"
    }

    private var recordRow: some View {
        HStack(spacing: 12) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Label(isRecording ? "Stop" : "Dictate",
                      systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(isRecording ? .red : PinpointTheme.accent,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            if isRecording {
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PinpointTheme.accent)
                            .frame(width: 4, height: CGFloat(8 + (i * 5) % 14))
                    }
                }
            } else if speechDenied {
                Text("Speech access off — typing works the same.")
                    .font(.caption)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            Spacer()
        }
    }

    private var parsePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI structure")
                    .font(.headline)
                Spacer()
                if result.confidence > 0 {
                    Text("\(Int(result.confidence * 100))% confident")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PinpointTheme.accent)
                }
            }
            if result.isEmpty {
                Text("Speak or type. Structured fields fill in; anything extra becomes a note for later analysis.")
                    .font(.subheadline)
                    .foregroundStyle(PinpointTheme.secondaryText)
            }
            ForEach(Array(result.shots.enumerated()), id: \.offset) { i, shot in
                HStack(spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 26, height: 26)
                        .background(PinpointTheme.accent.opacity(0.2), in: Circle())
                        .foregroundStyle(PinpointTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shot.club?.displayName ?? "Unknown club")
                            .font(.subheadline.weight(.semibold))
                        Text(previewMeta(shot))
                            .font(.caption)
                            .foregroundStyle(PinpointTheme.secondaryText)
                    }
                    Spacer()
                }
                .padding(10)
                .background(PinpointTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let p = result.puttsMentioned {
                Label("\(p) putt\(p == 1 ? "" : "s")", systemImage: "flag")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if let call = result.scoreCall {
                Label("Called \(call)", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PinpointTheme.accent)
            }
            if !result.leftoverNote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved to notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PinpointTheme.accent)
                    Text(result.leftoverNote)
                        .font(.subheadline)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PinpointTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ForEach(result.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func previewMeta(_ shot: HoleDictationResult.ParsedShot) -> String {
        var bits: [String] = []
        if let l = shot.lie { bits.append(l.label) }
        if let c = shot.contact { bits.append(c.label) }
        if let s = shot.shape { bits.append(s.label) }
        if let q = shot.quality { bits.append(q.label) }
        if let f = shot.leftFeet { bits.append("to \(Int(f)) ft") }
        if !shot.note.isEmpty { bits.append(shot.note) }
        return bits.isEmpty ? "No extra detail" : bits.joined(separator: " · ")
    }

    // MARK: - Speech

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    speechDenied = true
                    return
                }
                guard let recognizer, recognizer.isAvailable else {
                    speechDenied = true
                    return
                }
                beginRecognition()
            }
        }
    }

    private func beginRecognition() {
        let engine = AVAudioEngine()
        audioEngine = engine
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            speechDenied = true
            return
        }
        isRecording = true
        recognitionTask = recognizer?.recognitionTask(with: request) { res, _ in
            if let text = res?.bestTranscription.formattedString {
                transcript = text
                result = HoleDictationParser.parse(text)
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        audioEngine = nil
    }
}
