@preconcurrency import AVFoundation
import Observation

@Observable
final class VideoPlaybackController {
    let player = AVPlayer()

    var currentFrame: Int = 0
    var totalFrames: Int = 1
    var frameRate: Double = 30
    var duration: Double = 0
    var currentTime: Double = 0
    var isPlaying = false
    var playbackRate: Float = 0.125
    var isReady = false
    var isScrubbing = false
    var videoSize: CGSize = .zero

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var isSeekInFlight = false
    private var pendingScrubFrame: Int?
    private var finishScrubExactly = false

    var currentFrameLabel: String {
        let frame = min(max(currentFrame + 1, 1), max(totalFrames, 1))
        return "Frame \(frame) / \(max(totalFrames, 1))"
    }

    var currentTimeLabel: String {
        Self.timestamp(currentTime)
    }

    var durationLabel: String {
        Self.timestamp(duration)
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func load(url: URL, recordedFrameRate: Double, durationHint: Double) async {
        tearDownObservers()
        isReady = false
        videoSize = .zero
        frameRate = max(recordedFrameRate, 1)
        duration = durationHint
        totalFrames = max(1, Int((duration * frameRate).rounded()))
        playbackRate = Float(min(1, 30 / frameRate))
        currentFrame = 0
        currentTime = 0

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false

        do {
            let loadedDuration = try await asset.load(.duration).seconds
            if loadedDuration.isFinite, loadedDuration > 0 {
                duration = loadedDuration
            }
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let rate = try await track.load(.nominalFrameRate)
                if rate > 1 {
                    frameRate = Double(rate)
                }
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let rendered = size.applying(transform)
                videoSize = CGSize(width: abs(rendered.width), height: abs(rendered.height))
            }
            totalFrames = max(1, Int((duration * frameRate).rounded()))
            playbackRate = Float(min(1, 30 / frameRate))
        } catch {
            // Keep metadata hints from the library if the asset can't be inspected.
        }

        addObservers(for: item)
        isReady = true
    }

    func play() {
        guard isReady else { return }
        isScrubbing = false
        pendingScrubFrame = nil
        finishScrubExactly = false
        if currentTime >= duration - 0.01 {
            seek(toFrame: 0, playAfter: true)
            return
        }
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        if !isScrubbing {
            snapToNearestFrame()
        }
    }

    func beginScrub() {
        guard isReady else { return }
        player.pause()
        isPlaying = false
        isScrubbing = true
        finishScrubExactly = false
    }

    func scrub(toFrame frame: Int) {
        let clamped = min(max(frame, 0), max(totalFrames - 1, 0))
        currentFrame = clamped
        currentTime = Double(clamped) / frameRate
        pendingScrubFrame = clamped
        isScrubbing = true
        chaseSeek(exact: false)
    }

    func endScrub() {
        finishScrubExactly = true
        pendingScrubFrame = currentFrame
        chaseSeek(exact: true)
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func seek(toFrame frame: Int, playAfter: Bool = false) {
        let clamped = min(max(frame, 0), max(totalFrames - 1, 0))
        currentFrame = clamped
        currentTime = Double(clamped) / frameRate
        pendingScrubFrame = clamped
        finishScrubExactly = true
        isScrubbing = true
        chaseSeek(exact: true, playAfter: playAfter)
    }

    func step(by delta: Int) {
        pause()
        seek(toFrame: currentFrame + delta)
    }

    func seek(toProgress progress: Double) {
        let frame = Int((progress * Double(max(totalFrames - 1, 0))).rounded())
        seek(toFrame: frame)
    }

    private func snapToNearestFrame() {
        let frame = Int((currentTime * frameRate).rounded())
        seek(toFrame: frame)
    }

    private func chaseSeek(exact: Bool, playAfter: Bool = false) {
        guard !isSeekInFlight else { return }
        guard let frame = pendingScrubFrame else {
            isScrubbing = false
            return
        }
        pendingScrubFrame = nil
        isSeekInFlight = true
        let time = CMTime(seconds: Double(frame) / max(frameRate, 1), preferredTimescale: 60000)
        let slack = exact ? CMTime.zero : CMTime(seconds: 1.0 / 20.0, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: slack, toleranceAfter: slack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSeekInFlight = false
                if self.pendingScrubFrame != nil {
                    self.chaseSeek(exact: self.finishScrubExactly, playAfter: playAfter)
                    return
                }
                if self.finishScrubExactly, !exact {
                    self.pendingScrubFrame = self.currentFrame
                    self.chaseSeek(exact: true, playAfter: playAfter)
                    return
                }
                self.finishScrubExactly = false
                self.isScrubbing = false
                if playAfter {
                    self.player.rate = self.playbackRate
                    self.isPlaying = true
                }
            }
        }
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: 1 / min(max(frameRate, 24), 30), preferredTimescale: 60000)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = min(max(seconds, 0), self.duration)
            self.currentFrame = min(max(Int((self.currentTime * self.frameRate).rounded()), 0), max(self.totalFrames - 1, 0))
            self.isPlaying = self.player.rate != 0
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.currentFrame = max((self?.totalFrames ?? 1) - 1, 0)
        }
    }

    private func tearDownObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let remainder = clamped.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", minutes, remainder)
    }
}
