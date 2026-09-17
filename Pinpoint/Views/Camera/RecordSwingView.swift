import SwiftUI
import UIKit

struct RecordSwingView: View {
    @Environment(SwingLibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var onCaptured: ((Swing) -> Void)?

    @State private var camera = CameraService()
    @State private var showSettings = false
    @State private var isStopping = false
    @State private var isRollingOver = false
    @State private var saveError: String?
    @State private var isAutoMode = false
    @State private var countdownValue: Int?
    @State private var countdownTask: Task<Void, Never>?
    @AppStorage("pinpoint.capture.delay") private var startDelayRaw = RecordStartDelay.three.rawValue

    private var startDelay: RecordStartDelay {
        RecordStartDelay(rawValue: startDelayRaw) ?? .three
    }

    private var isCountingDown: Bool { countdownValue != nil }

    var body: some View {
        ZStack {
            PinpointTheme.background.ignoresSafeArea()

            if camera.isCameraAvailable {
                CameraPreviewView(session: camera.session, isFrontCamera: camera.isUsingFrontCamera)
                    .ignoresSafeArea()
                if isAutoMode {
                    PoseOverlayView(
                        skeleton: camera.livePose,
                        videoSize: camera.analysisVideoSize,
                        gravity: .fill
                    )
                    .ignoresSafeArea()
                }
            } else if camera.isSettingUp {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(PinpointTheme.accent)
                    Text("Starting camera…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                unavailableState
            }

            if let countdownValue {
                countdownOverlay(countdownValue)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if camera.isRecording {
                    recordingBadge
                        .padding(.bottom, 16)
                } else if isAutoMode {
                    autoStatusBadge
                        .padding(.bottom, 16)
                }
                bottomBar
            }
        }
        .statusBarHidden()
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            await camera.requestAccessAndConfigure()
        }
        .onChange(of: camera.recordingDuration) { _, duration in
            if camera.isRecording, !isStopping, !isRollingOver, !isAutoMode,
               duration >= CameraService.maxRecordingDuration {
                isRollingOver = true
                camera.rollOverToNewClip()
            }
        }
        .onChange(of: camera.completedSegmentURL) { _, url in
            guard let url else { return }
            camera.completedSegmentURL = nil
            Task { await saveSegment(url: url) }
        }
        .onChange(of: camera.isRecording) { _, recording in
            if recording { isRollingOver = false }
        }
        .onChange(of: camera.autoFinishedURL) { _, url in
            guard let url else { return }
            camera.autoFinishedURL = nil
            camera.pauseAutoCapture = true
            Task { await finishRecording(url: url) }
        }
        .onChange(of: isAutoMode) { _, enabled in
            camera.setAutoMode(enabled)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            cancelCountdown(restoreTorch: false)
            if camera.isRecording {
                Task { _ = try? await camera.stopRecording() }
            }
            camera.stop()
        }
        .sheet(isPresented: $showSettings) {
            CaptureSettingsSheet(
                presets: camera.availablePresets,
                selected: camera.selectedPreset,
                startDelay: Binding(
                    get: { startDelay },
                    set: { startDelayRaw = $0.rawValue }
                ),
                onSelect: { camera.selectPreset($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .alert("Couldn't save swing", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .alert("Camera", isPresented: Binding(
            get: { camera.errorMessage != nil },
            set: { if !$0 { camera.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(camera.errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
            }

            Spacer()

            if let preset = camera.selectedPreset, !camera.isRecording, !isCountingDown {
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text(settingsLabel(for: preset))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                }
            }

            Spacer()

            Button {
                isAutoMode.toggle()
            } label: {
                Text("AUTO")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isAutoMode ? PinpointTheme.accent : .black.opacity(0.45), in: Capsule())
            }
            .disabled(camera.isRecording || isCountingDown || !camera.isCameraAvailable)
            .accessibilityLabel(isAutoMode ? "Turn off auto capture" : "Turn on auto capture")

            if camera.torchAvailable {
                Button {
                    camera.toggleTorch()
                } label: {
                    Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(camera.isTorchOn ? PinpointTheme.accent : .white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .disabled(isCountingDown)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var recordingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text(isAutoMode ? camera.autoPhase.statusText : Self.timerText(camera.recordingDuration))
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
            if isAutoMode {
                Text(Self.timerText(camera.recordingDuration))
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var autoStatusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: camera.livePose?.isPersonDetected == true ? "figure.golf" : "person.slash")
            Text(camera.autoPhase.statusText)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if isAutoMode, !camera.isRecording, !isCountingDown {
                Text("Stand in frame at address. Pinpoint starts recording when you settle, then stops after impact from your pose and the hit sound.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(alignment: .center) {
                Color.clear.frame(width: 52, height: 52)
                Spacer()
                recordButton
                Spacer()
                flipButton
            }
            .padding(.horizontal, 28)
        }
        .padding(.bottom, 36)
    }

    private var recordButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                if camera.isRecording || isCountingDown {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .disabled(!camera.isCameraAvailable || isStopping || isRollingOver)
        .opacity(camera.isCameraAvailable ? 1 : 0.4)
        .accessibilityLabel(recordAccessibilityLabel)
    }

    private var flipButton: some View {
        Button {
            camera.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.45), in: Circle())
        }
        .disabled(!camera.isCameraAvailable || camera.isRecording || isCountingDown || !camera.canFlipCamera)
        .opacity(camera.isRecording || isCountingDown || !camera.canFlipCamera ? 0.35 : 1)
        .accessibilityLabel(camera.isUsingFrontCamera ? "Switch to rear camera" : "Switch to front camera")
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(PinpointTheme.accent)
            Text(camera.cameraUnavailableReason ?? "Camera unavailable")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func countdownOverlay(_ value: Int) -> some View {
        Text(value == 0 ? "START" : "\(value)")
            .font(.system(size: value == 0 ? 64 : 96, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 12, y: 2)
            .transition(.scale.combined(with: .opacity))
            .id(value)
            .animation(.easeInOut(duration: 0.15), value: value)
    }

    private var recordAccessibilityLabel: String {
        if camera.isRecording { return "Stop recording" }
        if isCountingDown { return "Cancel countdown" }
        return "Start recording"
    }

    private func settingsLabel(for preset: CapturePreset) -> String {
        if startDelay == .off {
            return preset.shortLabel
        }
        return "\(preset.shortLabel) · \(startDelay.label)"
    }

    private func toggleRecording() async {
        guard !isRollingOver else { return }
        if camera.isRecording {
            isStopping = true
            defer { isStopping = false }
            do {
                let url = try await camera.stopRecording()
                await finishRecording(url: url)
            } catch {
                saveError = error.localizedDescription
            }
        } else if isCountingDown {
            cancelCountdown(restoreTorch: true)
        } else if isAutoMode || startDelay == .off {
            camera.startRecording()
        } else {
            await beginCountdownAndRecord()
        }
    }

    private func beginCountdownAndRecord() async {
        let delay = startDelay.rawValue
        guard delay > 0 else {
            camera.startRecording()
            return
        }

        let torchWasOn = camera.isTorchOn
        camera.setTorch(on: false)

        countdownTask?.cancel()
        countdownTask = Task {
            for remaining in stride(from: delay, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        countdownValue = remaining
                    }
                }
                if remaining <= 3 {
                    await flashTorch(duration: 0.16)
                    try? await Task.sleep(nanoseconds: 840_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.12)) {
                    countdownValue = 0
                }
            }
            await flashTorch(duration: 0.28)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                countdownValue = nil
                if torchWasOn {
                    camera.setTorch(on: true, level: 0.7)
                }
                camera.startRecording()
            }
        }
        await countdownTask?.value
    }

    private func flashTorch(duration: TimeInterval) async {
        guard camera.torchAvailable else { return }
        camera.setTorch(on: true, level: 1)
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        camera.setTorch(on: false)
    }

    private func cancelCountdown(restoreTorch: Bool) {
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = nil
        if restoreTorch {
            camera.setTorch(on: false)
        }
    }

    private func finishRecording(url: URL) async {
        guard let swing = await importSwing(from: url) else { return }
        camera.stop()
        onCaptured?(swing)
    }

    /// Saves a rolled-over segment as its own swing while the next clip keeps
    /// recording in the background.
    private func saveSegment(url: URL) async {
        _ = await importSwing(from: url)
    }

    private func importSwing(from url: URL) async -> Swing? {
        guard let preset = camera.selectedPreset else { return nil }
        do {
            let swing = try await library.importRecording(
                from: url,
                preset: preset,
                title: Self.defaultTitle()
            )
            if library.isSignedIn {
                Task { await library.upload(swing) }
            }
            return swing
        } catch {
            saveError = error.localizedDescription
            return nil
        }
    }

    private static func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Swing · \(formatter.string(from: Date()))"
    }

    private static func timerText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}

struct CaptureSettingsSheet: View {
    let presets: [CapturePreset]
    let selected: CapturePreset?
    @Binding var startDelay: RecordStartDelay
    let onSelect: (CapturePreset) -> Void

    @State private var chosenFPS: Int?

    private var allFrameRates: [Int] {
        Array(Set(presets.map(\.fps))).sorted(by: >)
    }

    private var activeFPS: Int {
        chosenFPS ?? selected?.fps ?? allFrameRates.first ?? 30
    }

    private var resolutionsForActiveFPS: [CapturePreset] {
        var seen = Set<String>()
        var result: [CapturePreset] = []
        for preset in presets where preset.fps == activeFPS {
            let key = "\(preset.width)x\(preset.height)"
            if seen.insert(key).inserted {
                result.append(preset)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Start delay") {
                        chipGrid(RecordStartDelay.allCases.map(\.label)) { label in
                            if let match = RecordStartDelay.allCases.first(where: { $0.label == label }) {
                                startDelay = match
                            }
                        } isSelected: { label in
                            label == startDelay.label
                        }
                    }

                    section("Frame rate") {
                        chipGrid(allFrameRates.map { "\($0) FPS" }) { label in
                            let fps = Int(label.replacingOccurrences(of: " FPS", with: "")) ?? 30
                            chosenFPS = fps
                            selectBestPreset(fps: fps)
                        } isSelected: { label in
                            label == "\(activeFPS) FPS"
                        }
                    }

                    section("Resolution") {
                        chipGrid(resolutionsForActiveFPS.map(\.resolutionLabel)) { label in
                            guard let match = resolutionsForActiveFPS.first(where: { $0.resolutionLabel == label }) else { return }
                            onSelect(match)
                        } isSelected: { label in
                            selected?.fps == activeFPS && selected?.resolutionLabel == label
                        }
                    }
                }
                .padding(20)
            }
            .background(PinpointTheme.background)
            .navigationTitle("Record settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                chosenFPS = selected?.fps
            }
        }
    }

    private func selectBestPreset(fps: Int) {
        let atRate = presets.filter { $0.fps == fps }
        let candidate = atRate.first {
            $0.width == (selected?.width ?? $0.width) &&
            $0.height == (selected?.height ?? $0.height)
        } ?? atRate.first
        if let candidate { onSelect(candidate) }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(PinpointTheme.secondaryText)
            content()
        }
    }

    private func chipGrid(_ items: [String], onTap: @escaping (String) -> Void, isSelected: @escaping (String) -> Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected(item) ? PinpointTheme.accent : PinpointTheme.surfaceElevated,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(PinpointTheme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(PinpointTheme.surfaceElevated.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
