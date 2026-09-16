import AVFoundation
import Observation

/// Records locally first. OpenAI receives audio only when the golfer stops and transcribes.
/// A failed upload survives dismissal/relaunch and can be retried without re-recording.
@MainActor @Observable
final class VoiceCapture {
    var transcript = ""
    var isRecording = false
    var isStarting = false
    var isFinishing = false
    var error: String?
    var elapsed: TimeInterval = 0
    var level: Float = 0
    var pendingAudio: URL?
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var generation = UUID()
    private static let pendingKey = "pinpoint.voice.pendingAudio"

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.pendingKey), FileManager.default.fileExists(atPath: path) {
            pendingAudio = URL(fileURLWithPath: path)
        }
    }

    func start() async {
        guard !isRecording, !isStarting, !isFinishing, pendingAudio == nil else { return }
        isStarting = true
        error = nil
        let token = UUID()
        generation = token
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard generation == token else { return }
        isStarting = false
        guard microphone else { error = "Allow microphone access in Settings, or type your recap below."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pinpoint/Voice", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(UUID().uuidString).m4a")
            let audio = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            audio.isMeteringEnabled = true
            guard audio.prepareToRecord(), audio.record() else { throw GolfAIError.server("Couldn't start recording. Please try again.") }
            recorder = audio
            pendingAudio = file
            UserDefaults.standard.set(file.path, forKey: Self.pendingKey)
            elapsed = 0
            isRecording = true
            meterTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, let audio = self.recorder else { return }
                    guard audio.isRecording else {
                        self.endRecording()
                        self.error = "Recording was interrupted. Retry transcription to recover the captured audio."
                        return
                    }
                    self.elapsed = audio.currentTime
                    audio.updateMeters()
                    self.level = max(0, min(1, (audio.averagePower(forChannel: 0) + 50) / 50))
                    if self.elapsed >= 600 { self.finish(); return }
                }
            }
        } catch {
            endRecording()
            self.error = error.localizedDescription
        }
    }

    private func endRecording() {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func finish() { endRecording(); retryTranscription() }

    func retryTranscription() {
        guard !isRecording, !isFinishing, let file = pendingAudio else { return }
        isFinishing = true
        error = nil
        let token = UUID()
        generation = token
        transcriptionTask = Task { @MainActor in
            do {
                let text = try await OpenAIGolfService.transcribe(file: file).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled, generation == token else { return }
                guard !text.isEmpty else { throw GolfAIError.server("No speech was detected. Retry or discard this recording and record again.") }
                transcript = [transcript.trimmingCharacters(in: .whitespacesAndNewlines), text].filter { !$0.isEmpty }.joined(separator: " ")
                discardRecording()
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                self.error = error.localizedDescription
            }
            isFinishing = false
        }
    }

    func discardRecording() {
        if let pendingAudio { try? FileManager.default.removeItem(at: pendingAudio) }
        pendingAudio = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    func stop() {
        generation = UUID()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isStarting = false
        isFinishing = false
        endRecording()
        // Keep pending audio for an explicit retry, even after the sheet closes.
    }
}
