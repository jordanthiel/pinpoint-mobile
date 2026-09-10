@preconcurrency import AVFoundation
import UIKit

@Observable
final class CameraService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    var isConfigured = false
    var isRunning = false
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var availablePresets: [CapturePreset] = []
    var selectedPreset: CapturePreset?
    var errorMessage: String?
    var cameraUnavailableReason: String?
    var torchAvailable = false
    var isTorchOn = false
    var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    var isUsingFrontCamera = false
    var canFlipCamera = false

    var isAutoMode = false
    var pauseAutoCapture = false
    var autoPhase: AutoSwingPhase = .watching
    var livePose: PoseSkeleton?
    var analysisVideoSize = CGSize(width: 1080, height: 1920)
    var autoFinishedURL: URL?

    private let sessionQueue = DispatchQueue(label: "com.pinpoint.camera.session")
    private let analysisQueue = DispatchQueue(label: "com.pinpoint.camera.analysis", qos: .userInitiated)
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let poseService = PoseDetectionService.shared
    private let detector = SwingShotDetector()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var recordingContinuation: CheckedContinuation<URL, Error>?
    private var outputURL: URL?
    private var lastPoseAnalysis: TimeInterval = 0
    private var isFinishingAuto = false
    private var autoOwnsRecording = false
    private var wantsRunning = false
    private var analysisOutputsInstalled = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    static let maxRecordingDuration: TimeInterval = 30

    var isCameraAvailable: Bool {
        cameraUnavailableReason == nil && authorizationStatus == .authorized && isConfigured && isRunning
    }

    var isSettingUp: Bool {
        authorizationStatus != .denied && authorizationStatus != .restricted && !isConfigured && cameraUnavailableReason == nil
    }

    func requestAccessAndConfigure() async {
        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        guard videoGranted else {
            await MainActor.run {
                cameraUnavailableReason = "Camera access is turned off. Enable it in Settings to record swings."
            }
            return
        }

        await configureSession()
    }

    func start() {
        wantsRunning = true
        sessionQueue.async { [weak self] in
            self?.startRunningIfNeeded()
        }
    }

    func stop() {
        wantsRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func flipCamera() {
        guard !isRecording else { return }
        sessionQueue.async { [weak self] in
            self?.performFlip()
        }
    }

    private func performFlip() {
        let nextPosition: AVCaptureDevice.Position = videoDevice?.position == .front ? .back : .front
        guard let device = Self.preferredCamera(for: nextPosition) else {
            DispatchQueue.main.async {
                self.errorMessage = "Couldn't find the other camera."
            }
            return
        }

        session.beginConfiguration()
        if let videoInput {
            session.removeInput(videoInput)
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                videoDevice = device
                videoInput = input
            } else {
                session.commitConfiguration()
                DispatchQueue.main.async {
                    self.errorMessage = "Couldn't switch cameras."
                }
                return
            }
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            return
        }
        session.commitConfiguration()

        let presets = Self.allPresets(for: nextPosition)
        let preferred = Self.closestPreset(to: selectedPreset, in: presets) ?? Self.preferredPreset(from: presets)
        if let preferred {
            applyPreset(preferred)
        }
        updateVideoRotation()
        startRunningIfNeeded()

        DispatchQueue.main.async {
            self.availablePresets = presets
            self.selectedPreset = preferred ?? presets.first
            self.torchAvailable = device.hasTorch
            self.isUsingFrontCamera = nextPosition == .front
            if !device.hasTorch {
                self.isTorchOn = false
            }
        }
    }

    func selectPreset(_ preset: CapturePreset) {
        selectedPreset = preset
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyPreset(preset)
            self.startRunningIfNeeded()
        }
    }

    func setAutoMode(_ enabled: Bool) {
        isAutoMode = enabled
        detector.reset()
        autoPhase = .watching
        autoFinishedURL = nil
        isFinishingAuto = false
        if !enabled {
            livePose = nil
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if enabled {
                self.installAnalysisOutputs()
            } else {
                self.removeAnalysisOutputs()
            }
        }
    }

    func resetAutoDetector() {
        detector.reset()
        autoPhase = .watching
        isFinishingAuto = false
        autoFinishedURL = nil
    }

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            self.applyTorch(on: device.torchMode != .on, level: 0.7)
        }
    }

    func setTorch(on: Bool, level: Float = 1.0) {
        sessionQueue.async { [weak self] in
            self?.applyTorch(on: on, level: level)
        }
    }

    private func applyTorch(on: Bool, level: Float) {
        guard let device = videoDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on {
                let clamped = min(max(level, 0.05), AVCaptureDevice.maxAvailableTorchLevel)
                try device.setTorchModeOn(level: clamped)
            } else {
                device.torchMode = .off
            }
            DispatchQueue.main.async {
                self.isTorchOn = on
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Couldn't toggle the light."
            }
        }
    }

    func startRecording() {
        autoOwnsRecording = false
        beginRecording()
    }

    private func beginRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.startRunningIfNeeded()
            guard self.session.isRunning else {
                DispatchQueue.main.async {
                    self.errorMessage = "The camera isn't running yet."
                }
                return
            }
            guard !self.movieOutput.isRecording else { return }

            self.updateVideoRotation()

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            self.outputURL = url

            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.notReady)
                    return
                }
                guard self.movieOutput.isRecording else {
                    continuation.resume(throwing: CameraError.notRecording)
                    return
                }
                self.recordingContinuation = continuation
                self.movieOutput.stopRecording()
            }
        }
    }

    private func configureSession() async {
        guard !isConfigured else {
            start()
            return
        }

        #if targetEnvironment(simulator)
        await MainActor.run {
            cameraUnavailableReason = "The iOS Simulator has no camera. Run Pinpoint on an iPhone to record slow-motion swings."
        }
        return
        #else
        wantsRunning = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                defer { continuation.resume() }
                guard let self else { return }

                self.session.beginConfiguration()
                self.session.sessionPreset = .inputPriority
                self.session.automaticallyConfiguresCaptureDeviceForWideColor = false

                guard let device = Self.preferredCamera() else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.cameraUnavailableReason = "No rear camera was found on this device."
                    }
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.videoDevice = device
                        self.videoInput = input
                    } else {
                        self.session.commitConfiguration()
                        DispatchQueue.main.async {
                            self.cameraUnavailableReason = "Couldn't connect to the camera."
                        }
                        return
                    }

                    if let audioDevice = AVCaptureDevice.default(for: .audio),
                       let audio = try? AVCaptureDeviceInput(device: audioDevice),
                       self.session.canAddInput(audio) {
                        self.session.addInput(audio)
                        self.audioInput = audio
                    }

                    if self.session.canAddOutput(self.movieOutput) {
                        self.session.addOutput(self.movieOutput)
                        self.movieOutput.movieFragmentInterval = .invalid
                    }

                    self.session.commitConfiguration()

                    let presets = Self.allPresets(for: .back)
                    let preferred = Self.preferredPreset(from: presets)
                    if let preferred {
                        self.applyPreset(preferred)
                    }

                    self.startRunningIfNeeded(allowFormatFallback: true)

                    let running = self.session.isRunning
                    let selected = preferred ?? presets.first
                    let canFlip = Self.preferredCamera(for: .front) != nil
                    DispatchQueue.main.async {
                        self.availablePresets = presets
                        self.selectedPreset = selected
                        self.torchAvailable = device.hasTorch
                        self.isConfigured = true
                        self.isRunning = running
                        self.isUsingFrontCamera = false
                        self.canFlipCamera = canFlip
                        if !running {
                            self.cameraUnavailableReason = "Couldn't start the camera session. Try closing other camera apps and reopen Record."
                        }
                    }
                } catch {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.cameraUnavailableReason = "Couldn't start the camera."
                    }
                }
            }
        }
        #endif
    }

    private func startRunningIfNeeded(allowFormatFallback: Bool = false) {
        guard wantsRunning else { return }
        if !session.isRunning {
            session.startRunning()
        }
        if allowFormatFallback, !session.isRunning, let device = videoDevice {
            let fallbacks = Self.presets(for: device).filter { $0.fps <= 60 }
            for preset in fallbacks {
                applyPreset(preset)
                session.startRunning()
                if session.isRunning {
                    DispatchQueue.main.async { self.selectedPreset = preset }
                    break
                }
            }
        }
        DispatchQueue.main.async {
            self.isRunning = self.session.isRunning
        }
    }

    private func installAnalysisOutputs() {
        session.beginConfiguration()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        if !session.outputs.contains(where: { $0 === videoDataOutput }), session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        audioDataOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        if !session.outputs.contains(where: { $0 === audioDataOutput }), session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        }
        session.commitConfiguration()
        updateVideoRotation()
        analysisOutputsInstalled = true
    }

    private func removeAnalysisOutputs() {
        guard analysisOutputsInstalled || session.outputs.contains(where: { $0 === videoDataOutput || $0 === audioDataOutput }) else {
            return
        }
        session.beginConfiguration()
        if session.outputs.contains(where: { $0 === videoDataOutput }) {
            session.removeOutput(videoDataOutput)
        }
        if session.outputs.contains(where: { $0 === audioDataOutput }) {
            session.removeOutput(audioDataOutput)
        }
        session.commitConfiguration()
        analysisOutputsInstalled = false
    }

    private func applyPreset(_ preset: CapturePreset) {
        let position = videoDevice?.position ?? .back
        guard let target = Self.bestDevice(for: preset, position: position) else { return }

        if videoDevice?.uniqueID != target.uniqueID {
            session.beginConfiguration()
            if let videoInput {
                session.removeInput(videoInput)
            }
            do {
                let input = try AVCaptureDeviceInput(device: target)
                if session.canAddInput(input) {
                    session.addInput(input)
                    videoDevice = target
                    videoInput = input
                }
            } catch {
                session.commitConfiguration()
                DispatchQueue.main.async {
                    self.errorMessage = "Couldn't switch cameras for \(preset.shortLabel)."
                }
                return
            }
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.torchAvailable = target.hasTorch
                if !target.hasTorch { self.isTorchOn = false }
            }
        }

        guard let device = videoDevice, let format = Self.format(on: device, matching: preset) else {
            DispatchQueue.main.async {
                self.errorMessage = "This camera can't use \(preset.shortLabel)."
            }
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.fps))
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate - 0.5 <= Double(preset.fps) && Double(preset.fps) <= $0.maxFrameRate + 0.5
            }) {
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            updateVideoRotation()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Couldn't apply \(preset.shortLabel)."
            }
        }
    }

    private func updateVideoRotation() {
        guard let device = videoDevice else { return }
        rotationObservation?.invalidate()
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        applyCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async {
                self?.applyCaptureRotation(angle)
            }
        }
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        let mirrored = videoDevice?.position == .front
        func configure(_ connection: AVCaptureConnection?) {
            guard let connection else { return }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
        configure(movieOutput.connection(with: .video))
        configure(videoDataOutput.connection(with: .video))
    }

    private func startTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recordingStartedAt = Date()
            self.recordingDuration = 0
            self.isRecording = true
            self.recordingTimer?.invalidate()
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let started = self.recordingStartedAt else { return }
                self.recordingDuration = Date().timeIntervalSince(started)
            }
        }
    }

    private func stopTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.recordingTimer?.invalidate()
            self?.recordingTimer = nil
            self?.isRecording = false
        }
    }

    private func handleAutoCommand(_ command: AutoSwingCommand) {
        switch command {
        case .startCapture:
            if !isRecording {
                autoOwnsRecording = true
                beginRecording()
            }
        case .finishCapture:
            guard autoOwnsRecording else { return }
            Task { await finishAutoCapture(discard: false) }
        case .cancelCapture:
            guard autoOwnsRecording else { return }
            Task { await finishAutoCapture(discard: true) }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.autoPhase = self.detector.phase
        }
    }

    private func finishAutoCapture(discard: Bool) async {
        guard !isFinishingAuto else { return }
        isFinishingAuto = true
        defer { isFinishingAuto = false }

        guard isRecording || movieOutput.isRecording else {
            detector.reset()
            DispatchQueue.main.async { self.autoPhase = .watching }
            return
        }

        do {
            let url = try await stopRecording()
            if discard {
                try? FileManager.default.removeItem(at: url)
                detector.reset()
                DispatchQueue.main.async { self.autoPhase = .watching }
            } else {
                DispatchQueue.main.async {
                    self.autoFinishedURL = url
                    self.autoPhase = .complete
                }
            }
        } catch {
            detector.reset()
            DispatchQueue.main.async { self.autoPhase = .watching }
        }
    }

    private static func preferredCamera() -> AVCaptureDevice? {
        preferredCamera(for: .back)
    }

    private static func preferredCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = cameras(for: position)
        if position == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? devices.first
        }
        return devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? devices.first
            ?? AVCaptureDevice.default(for: .video)
    }

    private static func cameras(for position: AVCaptureDevice.Position) -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInDualCamera,
                .builtInTelephotoCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: position
        ).devices
    }

    private static func backCameras() -> [AVCaptureDevice] {
        cameras(for: .back)
    }

    private static func allPresets() -> [CapturePreset] {
        allPresets(for: .back)
    }

    private static func allPresets(for position: AVCaptureDevice.Position) -> [CapturePreset] {
        var seen = Set<String>()
        var result: [CapturePreset] = []
        for device in cameras(for: position) {
            for preset in presets(for: device) where seen.insert(preset.id).inserted {
                result.append(preset)
            }
        }
        return result.sorted {
            if $0.fps != $1.fps { return $0.fps > $1.fps }
            if $0.width != $1.width { return $0.width > $1.width }
            return $0.height > $1.height
        }
    }

    private static func closestPreset(to current: CapturePreset?, in presets: [CapturePreset]) -> CapturePreset? {
        guard let current else { return preferredPreset(from: presets) }
        return presets.min { lhs, rhs in
            let left = abs(lhs.fps - current.fps) * 10_000 + abs(lhs.width - current.width)
            let right = abs(rhs.fps - current.fps) * 10_000 + abs(rhs.width - current.width)
            return left < right
        }
    }

    private static func bestDevice(for preset: CapturePreset, position: AVCaptureDevice.Position = .back) -> AVCaptureDevice? {
        let cameras = cameras(for: position)
        if position == .front {
            return cameras.first { format(on: $0, matching: preset) != nil } ?? cameras.first
        }
        let wide = cameras.first { $0.deviceType == .builtInWideAngleCamera }
        if let wide, format(on: wide, matching: preset) != nil {
            return wide
        }
        return cameras.first { format(on: $0, matching: preset) != nil } ?? preferredCamera(for: position)
    }

    private static func presets(for device: AVCaptureDevice) -> [CapturePreset] {
        var seen = Set<String>()
        var result: [CapturePreset] = []
        let candidateRates = [30, 60, 120, 240, 300]

        for format in device.formats {
            let dimensions = Self.normalizedDimensions(format)
            guard min(dimensions.width, dimensions.height) >= (device.position == .front ? 480 : 720) else { continue }

            for fps in candidateRates where Self.formatSupports(format, fps: fps) {
                let preset = CapturePreset(width: dimensions.width, height: dimensions.height, fps: fps)
                if seen.insert(preset.id).inserted {
                    result.append(preset)
                }
            }
        }

        return result.sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            return $0.fps > $1.fps
        }
    }

    private static func preferredPreset(from presets: [CapturePreset]) -> CapturePreset? {
        presets.first { $0.width == 1920 && $0.height == 1080 && $0.fps == 240 }
            ?? presets.first { $0.fps >= 240 }
            ?? presets.first { $0.fps >= 120 }
            ?? presets.first
    }

    private static func format(on device: AVCaptureDevice, matching preset: CapturePreset) -> AVCaptureDevice.Format? {
        let matches = device.formats.filter { format in
            let dimensions = Self.normalizedDimensions(format)
            guard dimensions.width == preset.width, dimensions.height == preset.height else {
                return false
            }
            return Self.formatSupports(format, fps: preset.fps)
        }

        return matches.max { lhs, rhs in
            Self.formatScore(lhs, fps: preset.fps) < Self.formatScore(rhs, fps: preset.fps)
        } ?? matches.first
    }

    private static func formatSupports(_ format: AVCaptureDevice.Format, fps: Int) -> Bool {
        let rate = Double(fps)
        return format.videoSupportedFrameRateRanges.contains { range in
            range.maxFrameRate + 1.5 >= rate && range.minFrameRate - 1.5 <= rate
        }
    }

    private static func formatScore(_ format: AVCaptureDevice.Format, fps: Int) -> Int {
        var score = 0
        if fps >= 120, format.isVideoBinned { score += 3 }
        if fps < 120, !format.isVideoBinned { score += 2 }
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        if abs(maxRate - Double(fps)) < 2 { score += 2 }
        return score
    }

    private static func normalizedDimensions(_ format: AVCaptureDevice.Format) -> (width: Int, height: Int) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        return (max(width, height), min(width, height))
    }

    static func currentVideoRotationAngle() -> CGFloat {
        let orientation = Self.interfaceOrientation()
        switch orientation {
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }

    private static func interfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.interfaceOrientation ?? .portrait
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        startTimer()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        stopTimer()
        if let error {
            recordingContinuation?.resume(throwing: error)
        } else {
                recordingContinuation?.resume(returning: outputFileURL)
        }
        recordingContinuation = nil
        autoOwnsRecording = false
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === audioDataOutput {
            guard isAutoMode, !pauseAutoCapture else { return }
            let rms = Self.audioRMS(sampleBuffer)
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if let command = detector.ingestAudio(rms: Double(rms), at: time) {
                handleAutoCommand(command)
            }
            return
        }

        guard output === videoDataOutput, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: width, height: height)
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        if isAutoMode, !pauseAutoCapture, time - lastPoseAnalysis >= 1.0 / 18.0 {
            lastPoseAnalysis = time
            poseService.detectIfIdle(pixelBuffer: pixelBuffer, orientation: .up, timestamp: time) { [weak self] skeleton in
                guard let self else { return }
                self.analysisQueue.async {
                    DispatchQueue.main.async {
                        self.livePose = skeleton
                        self.analysisVideoSize = size
                    }
                    if self.isAutoMode, !self.pauseAutoCapture, let command = self.detector.ingestPose(skeleton, at: time) {
                        self.handleAutoCommand(command)
                    } else {
                        DispatchQueue.main.async {
                            self.autoPhase = self.detector.phase
                        }
                    }
                }
            }
        }
    }

    private static func audioRMS(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }
        let length = CMBlockBufferGetDataLength(dataBuffer)
        guard length > 1 else { return 0 }

        var data = Data(count: length)
        let copied: OSStatus = data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return 1 }
            return CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: base)
        }
        guard copied == kCMBlockBufferNoErr else { return 0 }

        var asbd = AudioStreamBasicDescription()
        if let format = CMSampleBufferGetFormatDescription(sampleBuffer),
           let ptr = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
            asbd = ptr.pointee
        }

        return data.withUnsafeBytes { raw in
            if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                let samples = raw.bindMemory(to: Float.self)
                guard !samples.isEmpty else { return 0 }
                var sum: Float = 0
                for sample in samples { sum += sample * sample }
                return sqrt(sum / Float(samples.count))
            }

            let samples = raw.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }
            var sum: Float = 0
            for sample in samples {
                let normalized = Float(sample) / 32768
                sum += normalized * normalized
            }
            return sqrt(sum / Float(samples.count))
        }
    }
}

enum CameraError: LocalizedError {
    case notReady
    case notRecording

    var errorDescription: String? {
        switch self {
        case .notReady: return "The camera isn't ready yet."
        case .notRecording: return "Nothing is being recorded."
        }
    }
}
