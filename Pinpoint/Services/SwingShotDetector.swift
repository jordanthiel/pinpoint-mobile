import Foundation

final class SwingShotDetector: @unchecked Sendable {
    private(set) var phase: AutoSwingPhase = .watching

    private var lastHeight: Double?
    private var lastTimestamp: TimeInterval?
    private var stillSince: TimeInterval?
    private var captureStartedAt: TimeInterval?
    private var sawHighPoint = false
    private var impactAt: TimeInterval?
    private var audioBaseline: Double = 0.02
    private var personLostAt: TimeInterval?

    private let addressHold: TimeInterval = 0.45
    private let maxWaitForSwing: TimeInterval = 12
    private let followThrough: TimeInterval = 1.7
    private let minCapture: TimeInterval = 1.1

    func reset() {
        phase = .watching
        lastHeight = nil
        lastTimestamp = nil
        stillSince = nil
        captureStartedAt = nil
        sawHighPoint = false
        impactAt = nil
        personLostAt = nil
    }

    func ingestPose(_ skeleton: PoseSkeleton?, at time: TimeInterval) -> AutoSwingCommand? {
        guard let skeleton, skeleton.isPersonDetected else {
            return handleMissingPerson(at: time)
        }
        personLostAt = nil

        let height = skeleton.wristHeight
        let dt = max(time - (lastTimestamp ?? time), 0.001)
        let speed = lastHeight.map { (height - $0) / dt } ?? 0
        lastHeight = height
        lastTimestamp = time

        switch phase {
        case .watching:
            if height < 0.40, abs(speed) < 0.22 {
                if stillSince == nil { stillSince = time }
                if time - (stillSince ?? time) >= addressHold {
                    phase = .address
                    captureStartedAt = time
                    stillSince = nil
                    sawHighPoint = false
                    impactAt = nil
                    return .startCapture
                }
            } else {
                stillSince = nil
            }

        case .address:
            if height > 0.58 || speed > 0.45 {
                phase = .backswing
                sawHighPoint = height > 0.62
            } else if let started = captureStartedAt, time - started > maxWaitForSwing {
                return cancel(at: time)
            }

        case .backswing:
            if height > 0.62 { sawHighPoint = true }
            if sawHighPoint, speed < -0.7, height < 0.85 {
                phase = .downswing
            } else if let started = captureStartedAt, time - started > maxWaitForSwing {
                return cancel(at: time)
            }

        case .downswing:
            if height < 0.42 || (sawHighPoint && speed < -0.35 && height < 0.55) {
                return markImpact(at: time)
            } else if let started = captureStartedAt, time - started > maxWaitForSwing {
                return cancel(at: time)
            }

        case .impact:
            if let impactAt, time - impactAt >= followThrough {
                return finish(at: time)
            }

        case .complete, .cancelled:
            break
        }

        return nil
    }

    func ingestAudio(rms: Double, at time: TimeInterval) -> AutoSwingCommand? {
        audioBaseline = (audioBaseline * 0.92) + (rms * 0.08)
        let spike = rms > max(audioBaseline * 6.5, 0.09) && rms > audioBaseline + 0.05

        guard spike else { return nil }
        guard phase == .backswing || phase == .downswing || phase == .address else { return nil }

        if phase == .address {
            // Ignore setup noise until the club has started moving up.
            return nil
        }
        return markImpact(at: time)
    }

    private func markImpact(at time: TimeInterval) -> AutoSwingCommand? {
        if phase == .impact || phase == .complete { return nil }
        phase = .impact
        impactAt = time
        if let started = captureStartedAt, time - started >= minCapture + followThrough {
            return finish(at: time)
        }
        return nil
    }

    private func finish(at time: TimeInterval) -> AutoSwingCommand? {
        if let started = captureStartedAt, time - started < minCapture {
            return nil
        }
        phase = .complete
        return .finishCapture
    }

    private func cancel(at _: TimeInterval) -> AutoSwingCommand {
        phase = .cancelled
        return .cancelCapture
    }

    private func handleMissingPerson(at time: TimeInterval) -> AutoSwingCommand? {
        lastHeight = nil
        stillSince = nil
        if captureStartedAt != nil {
            if personLostAt == nil { personLostAt = time }
            if let personLostAt, time - personLostAt > 2.2, phase == .address {
                return cancel(at: time)
            }
        }
        return nil
    }
}
