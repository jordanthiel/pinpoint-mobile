import AVFoundation
import CoreGraphics

@Observable
final class PlaybackPoseController {
    var isEnabled = false
    var skeleton: PoseSkeleton?

    private var generator: AVAssetImageGenerator?
    private let pose = PoseDetectionService.shared
    private let workQueue = DispatchQueue(label: "com.pinpoint.playback-pose", qos: .userInteractive)
    private let lock = NSLock()

    private var cache: [Int: PoseSkeleton?] = [:]
    private var latest: (frame: Int, time: Double)?
    private var displayedFrame = -1
    private var running = false
    private var frameRate = 30.0

    func prepare(url: URL, frameRate: Double) {
        self.frameRate = max(frameRate, 1)
        lock.lock()
        cache.removeAll()
        latest = nil
        displayedFrame = -1
        lock.unlock()
        skeleton = nil

        workQueue.async { [weak self] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            self?.generator = generator
            self?.kickIfNeeded()
        }
    }

    func update(frame: Int, time: Double, frameRate: Double? = nil) {
        guard isEnabled else { return }
        if let frameRate {
            self.frameRate = max(frameRate, 1)
        }

        lock.lock()
        displayedFrame = frame
        if let cached = cache[frame] {
            lock.unlock()
            skeleton = cached
            enqueueIfNeeded(frame: frame, time: time, skipIfCached: true)
            return
        }
        lock.unlock()

        enqueueIfNeeded(frame: frame, time: time, skipIfCached: false)
    }

    func setEnabled(_ enabled: Bool, frame: Int, time: Double, frameRate: Double? = nil) {
        isEnabled = enabled
        if enabled {
            update(frame: frame, time: time, frameRate: frameRate)
        } else {
            lock.lock()
            latest = nil
            displayedFrame = -1
            lock.unlock()
            skeleton = nil
        }
    }

    private func enqueueIfNeeded(frame: Int, time: Double, skipIfCached: Bool) {
        lock.lock()
        if skipIfCached, cache[frame] != nil {
            if latest == nil {
                if cache[frame + 1] == nil {
                    latest = (frame + 1, time + 1 / self.frameRate)
                } else if cache[frame + 2] == nil {
                    latest = (frame + 2, time + 2 / self.frameRate)
                }
            }
        } else {
            latest = (frame, time)
        }
        let shouldStart = !running && latest != nil
        if shouldStart {
            running = true
        }
        lock.unlock()

        if shouldStart {
            workQueue.async { [weak self] in
                self?.processLoop()
            }
        }
    }

    private func kickIfNeeded() {
        lock.lock()
        let shouldStart = isEnabled && !running && latest != nil
        if shouldStart {
            running = true
        }
        lock.unlock()
        if shouldStart {
            processLoop()
        }
    }

    private func processLoop() {
        while true {
            lock.lock()
            guard isEnabled, let job = latest else {
                running = false
                lock.unlock()
                return
            }
            latest = nil
            let alreadyCached = cache[job.frame] != nil
            lock.unlock()

            if alreadyCached {
                continue
            }

            guard let generator else {
                lock.lock()
                if latest == nil {
                    latest = job
                }
                running = false
                lock.unlock()
                return
            }

            let cmTime = CMTime(seconds: job.time, preferredTimescale: 60000)
            var actual = CMTime.zero
            let image = try? generator.copyCGImage(at: cmTime, actualTime: &actual)
            let detected = image.flatMap {
                pose.detect(cgImage: $0, orientation: .up, timestamp: job.time)
            }

            lock.lock()
            cache[job.frame] = detected
            let shouldApply = displayedFrame == job.frame
            let prefetch: (frame: Int, time: Double)? = {
                guard isEnabled, latest == nil else { return nil }
                if cache[job.frame + 1] == nil {
                    return (job.frame + 1, job.time + 1 / frameRate)
                }
                if cache[job.frame + 2] == nil {
                    return (job.frame + 2, job.time + 2 / frameRate)
                }
                return nil
            }()
            if let prefetch {
                latest = prefetch
            }
            lock.unlock()

            if shouldApply {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isEnabled, self.displayedFrame == job.frame else { return }
                    self.skeleton = detected
                }
            }
        }
    }
}
