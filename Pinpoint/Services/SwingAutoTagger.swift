import AVFoundation
import Foundation

enum SwingAutoTagger {
    static func suggestTags(videoURL: URL, duration: Double, frameRate: Double) async -> [SwingTag] {
        await Task.detached(priority: .utility) {
            analyze(videoURL: videoURL, duration: duration, frameRate: frameRate)
        }.value
    }

    private static func analyze(videoURL: URL, duration: Double, frameRate: Double) -> [SwingTag] {
        let skeletons = sampleSkeletons(videoURL: videoURL, duration: max(duration, 0.3), frameRate: max(frameRate, 1))
        guard !skeletons.isEmpty else { return [] }

        var tags: [SwingTag] = []
        if let angle = votedAngle(in: skeletons) {
            tags.append(angle.makeTag(source: .automatic))
        }
        if let club = inferredClub(from: skeletons, angle: tags.cameraAngle ?? votedAngle(in: skeletons)) {
            tags.append(club.makeTag(source: .automatic))
        }
        return tags
    }

    private static func sampleSkeletons(videoURL: URL, duration: Double, frameRate: Double) -> [PoseSkeleton] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1 / frameRate, preferredTimescale: 60000)

        let fractions: [Double] = [0.04, 0.10, 0.16, 0.24, 0.32, 0.42, 0.55, 0.68]
        var skeletons: [PoseSkeleton] = []
        for fraction in fractions {
            let time = duration * fraction
            let cmTime = CMTime(seconds: time, preferredTimescale: 60000)
            var actual = CMTime.zero
            guard let image = try? generator.copyCGImage(at: cmTime, actualTime: &actual) else { continue }
            let timestamp = CMTimeGetSeconds(actual)
            if let skeleton = PoseDetectionService.shared.detect(
                cgImage: image,
                orientation: .up,
                timestamp: timestamp
            ) {
                skeletons.append(skeleton)
            }
        }
        return skeletons
    }

    private static func votedAngle(in skeletons: [PoseSkeleton]) -> CameraAngle? {
        var votes: [CameraAngle: Int] = [:]
        for skeleton in skeletons {
            guard let angle = skeleton.estimatedCameraAngle else { continue }
            votes[angle, default: 0] += 1
        }
        guard let winner = votes.max(by: { $0.value < $1.value }) else { return nil }
        let total = votes.values.reduce(0, +)
        if total == 1 { return winner.key }
        return winner.value >= 2 ? winner.key : nil
    }

    private static func inferredClub(from skeletons: [PoseSkeleton], angle: CameraAngle?) -> ClubKind? {
        let address = skeletons.filter(\.isStandingStill)
        let peakWrist = skeletons.map(\.wristHeight).max() ?? 0

        if peakWrist > 0.12, peakWrist < 0.58, !address.isEmpty {
            return .wedge
        }

        switch angle {
        case .downTheLine:
            let tilts = address.compactMap(\.addressSpineTilt)
            if let tilt = median(tilts) {
                if tilt >= 36, peakWrist >= 0.82 { return .driver }
                if tilt <= 26, peakWrist >= 0.62 { return .iron }
            }
        case .faceOn, .none:
            let ratios = address.compactMap { skeleton -> Double? in
                guard let stance = skeleton.ankleWidth ?? skeleton.hipWidth,
                      let shoulders = skeleton.shoulderWidth,
                      shoulders > 0.04 else { return nil }
                return stance / shoulders
            }
            if let ratio = median(ratios) {
                if ratio >= 1.28, peakWrist >= 0.85 { return .driver }
                if ratio <= 1.08, peakWrist >= 0.68, peakWrist <= 1.12 { return .iron }
            }
        }

        return nil
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
