import AVFoundation
import Vision

final class PoseDetectionService: @unchecked Sendable {
    static let shared = PoseDetectionService()

    private let request = VNDetectHumanBodyPoseRequest()
    private let queue = DispatchQueue(label: "com.pinpoint.pose", qos: .userInitiated)
    private let requestLock = NSLock()
    private var isBusy = false

    private init() {
        request.revision = VNDetectHumanBodyPoseRequestRevision1
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up,
        timestamp: TimeInterval
    ) -> PoseSkeleton? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        return perform(handler: handler, timestamp: timestamp)
    }

    func detect(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        timestamp: TimeInterval
    ) -> PoseSkeleton? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return perform(handler: handler, timestamp: timestamp)
    }

    /// Drops the frame when a previous request is still running.
    func detectIfIdle(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up,
        timestamp: TimeInterval,
        completion: @escaping (PoseSkeleton?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, !self.isBusy else { return }
            self.isBusy = true
            let skeleton = self.detect(pixelBuffer: pixelBuffer, orientation: orientation, timestamp: timestamp)
            self.isBusy = false
            completion(skeleton)
        }
    }

    private func perform(handler: VNImageRequestHandler, timestamp: TimeInterval) -> PoseSkeleton? {
        requestLock.lock()
        defer { requestLock.unlock() }

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.max(by: { $0.confidence < $1.confidence }),
              observation.confidence >= 0.2 else {
            return nil
        }

        guard let recognized = try? observation.recognizedPoints(.all) else {
            return nil
        }

        var joints: [String: PoseJoint] = [:]
        for (name, point) in recognized where point.confidence >= 0.12 {
            let key = name.rawValue.rawValue
            joints[key] = PoseJoint(
                name: key,
                location: CGPoint(x: point.location.x, y: point.location.y),
                confidence: point.confidence
            )
        }
        guard !joints.isEmpty else { return nil }
        return PoseSkeleton(joints: joints, timestamp: timestamp)
    }
}
