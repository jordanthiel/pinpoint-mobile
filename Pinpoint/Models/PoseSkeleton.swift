import CoreGraphics
import Foundation
import Vision

struct PoseJoint: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let location: CGPoint
    let confidence: Float

    var displayPoint: CGPoint {
        CGPoint(x: location.x, y: 1 - location.y)
    }
}

struct PoseSkeleton: Equatable {
    var joints: [String: PoseJoint]
    var timestamp: TimeInterval

    subscript(_ joint: VNHumanBodyPoseObservation.JointName) -> PoseJoint? {
        joints[joint.rawValue.rawValue]
    }

    var isPersonDetected: Bool {
        let hips = confidence(of: .root) >= 0.2 || (confidence(of: .leftHip) >= 0.2 && confidence(of: .rightHip) >= 0.2)
        let shoulders = confidence(of: .leftShoulder) >= 0.2 || confidence(of: .rightShoulder) >= 0.2
        return hips && shoulders
    }

    func confidence(of joint: VNHumanBodyPoseObservation.JointName) -> Float {
        self[joint]?.confidence ?? 0
    }

    func point(of joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let joint = self[joint], joint.confidence >= 0.15 else { return nil }
        return joint.location
    }

    /// 0 ≈ wrists at hips, 1 ≈ wrists at head. Vision Y increases upward.
    var wristHeight: Double {
        guard let wrist = leadWrist else { return 0 }
        let hip = point(of: .root) ?? midpoint(of: .leftHip, .rightHip)
        let head = point(of: .nose) ?? point(of: .neck) ?? midpoint(of: .leftShoulder, .rightShoulder)
        guard let hip, let head else { return 0 }
        let span = Double(head.y - hip.y)
        guard span > 0.05 else { return 0 }
        return min(max(Double(wrist.y - hip.y) / span, 0), 1.4)
    }

    var leadWrist: CGPoint? {
        let left = self[.leftWrist]
        let right = self[.rightWrist]
        switch (left, right) {
        case let (l?, r?):
            return (l.confidence >= r.confidence ? l : r).location
        case let (l?, nil):
            return l.location
        case let (nil, r?):
            return r.location
        default:
            return nil
        }
    }

    var isStandingStill: Bool {
        isPersonDetected && wristHeight < 0.42
    }

    func displayPoint(
        of joint: VNHumanBodyPoseObservation.JointName,
        minConfidence: Float = 0.18
    ) -> CGPoint? {
        guard let joint = self[joint], joint.confidence >= minConfidence else { return nil }
        return joint.displayPoint
    }

    func displayMidpoint(
        of a: VNHumanBodyPoseObservation.JointName,
        _ b: VNHumanBodyPoseObservation.JointName
    ) -> CGPoint? {
        guard let pa = displayPoint(of: a), let pb = displayPoint(of: b) else { return nil }
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }

    func measuredAngle(for angle: PoseAngle) -> MeasuredPoseAngle? {
        guard let points = anglePoints(for: angle) else { return nil }
        let degrees = Self.interiorAngle(at: points.vertex, p1: points.start, p2: points.end)
        return MeasuredPoseAngle(
            angle: angle,
            vertex: points.vertex,
            start: points.start,
            end: points.end,
            degrees: degrees
        )
    }

    private func anglePoints(
        for angle: PoseAngle
    ) -> (start: CGPoint, vertex: CGPoint, end: CGPoint)? {
        switch angle {
        case .spine:
            let hip = displayMidpoint(of: .leftHip, .rightHip) ?? displayPoint(of: .root)
            let shoulder = displayMidpoint(of: .leftShoulder, .rightShoulder)
                ?? displayPoint(of: .neck)
            guard let hip, let shoulder else { return nil }
            let vertical = CGPoint(x: hip.x, y: hip.y - 0.2)
            return (shoulder, hip, vertical)
        default:
            let joints = angle.joints
            guard let start = displayPoint(of: joints.start),
                  let vertex = displayPoint(of: joints.vertex),
                  let end = displayPoint(of: joints.end) else { return nil }
            return (start, vertex, end)
        }
    }

    static func interiorAngle(at vertex: CGPoint, p1: CGPoint, p2: CGPoint) -> Double {
        let v1 = CGVector(dx: p1.x - vertex.x, dy: p1.y - vertex.y)
        let v2 = CGVector(dx: p2.x - vertex.x, dy: p2.y - vertex.y)
        let mag1 = hypot(v1.dx, v1.dy)
        let mag2 = hypot(v2.dx, v2.dy)
        guard mag1 > 0.001, mag2 > 0.001 else { return 0 }
        let cosine = max(-1, min(1, (v1.dx * v2.dx + v1.dy * v2.dy) / (mag1 * mag2)))
        return Double(acos(cosine)) * 180 / .pi
    }

    static let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .leftShoulder),
        (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .root),
        (.rightHip, .root),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        (.neck, .nose)
    ]

    private func midpoint(
        of a: VNHumanBodyPoseObservation.JointName,
        _ b: VNHumanBodyPoseObservation.JointName
    ) -> CGPoint? {
        guard let pa = point(of: a), let pb = point(of: b) else { return nil }
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }

    var torsoHeight: Double? {
        let shoulder = midpoint(of: .leftShoulder, .rightShoulder)
            ?? point(of: .neck)
            ?? midpoint(of: .leftShoulder, .neck)
            ?? midpoint(of: .rightShoulder, .neck)
        let hip = midpoint(of: .leftHip, .rightHip) ?? point(of: .root)
        guard let shoulder, let hip else { return nil }
        let length = hypot(Double(shoulder.x - hip.x), Double(shoulder.y - hip.y))
        return length > 0.04 ? length : nil
    }

    var shoulderWidth: Double? {
        guard let left = point(of: .leftShoulder), let right = point(of: .rightShoulder) else { return nil }
        return abs(Double(left.x - right.x))
    }

    var hipWidth: Double? {
        guard let left = point(of: .leftHip), let right = point(of: .rightHip) else { return nil }
        return abs(Double(left.x - right.x))
    }

    var ankleWidth: Double? {
        guard let left = point(of: .leftAnkle), let right = point(of: .rightAnkle) else { return nil }
        return abs(Double(left.x - right.x))
    }

    var estimatedCameraAngle: CameraAngle? {
        guard let torso = torsoHeight else { return nil }
        let leftConfidence = confidence(of: .leftShoulder)
        let rightConfidence = confidence(of: .rightShoulder)

        if leftConfidence >= 0.22, rightConfidence >= 0.22, let width = shoulderWidth {
            let ratio = width / torso
            if ratio >= 0.62 { return .faceOn }
            if ratio <= 0.38 { return .downTheLine }
            return nil
        }

        if (leftConfidence >= 0.35 && rightConfidence < 0.15)
            || (rightConfidence >= 0.35 && leftConfidence < 0.15) {
            return .downTheLine
        }
        return nil
    }

    var addressSpineTilt: Double? {
        guard isStandingStill, let measured = measuredAngle(for: .spine) else { return nil }
        return measured.degrees
    }
}

struct MeasuredPoseAngle: Equatable {
    let angle: PoseAngle
    let vertex: CGPoint
    let start: CGPoint
    let end: CGPoint
    let degrees: Double
}

struct PoseAngleReading: Identifiable, Equatable {
    var id: PoseAngle { angle }
    let number: Int
    let angle: PoseAngle
    let measured: MeasuredPoseAngle?

    var degreesText: String {
        guard let measured else { return "—" }
        return "\(Int(measured.degrees.rounded()))°"
    }
}

extension PoseSkeleton {
    func angleReadings(visible: Set<PoseAngle>) -> [PoseAngleReading] {
        var readings: [PoseAngleReading] = []
        var number = 1
        for angle in PoseAngle.allCases where visible.contains(angle) {
            readings.append(
                PoseAngleReading(
                    number: number,
                    angle: angle,
                    measured: measuredAngle(for: angle)
                )
            )
            number += 1
        }
        return readings
    }
}

enum PoseAngle: String, CaseIterable, Identifiable, Hashable {
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case spine
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftShoulder: return "Left shoulder"
        case .rightShoulder: return "Right shoulder"
        case .leftElbow: return "Left elbow"
        case .rightElbow: return "Right elbow"
        case .spine: return "Spine"
        case .leftHip: return "Left hip"
        case .rightHip: return "Right hip"
        case .leftKnee: return "Left knee"
        case .rightKnee: return "Right knee"
        }
    }

    var shortTitle: String {
        switch self {
        case .leftShoulder: return "L Shoulder"
        case .rightShoulder: return "R Shoulder"
        case .leftElbow: return "L Elbow"
        case .rightElbow: return "R Elbow"
        case .spine: return "Spine"
        case .leftHip: return "L Hip"
        case .rightHip: return "R Hip"
        case .leftKnee: return "L Knee"
        case .rightKnee: return "R Knee"
        }
    }

    var joints: (
        start: VNHumanBodyPoseObservation.JointName,
        vertex: VNHumanBodyPoseObservation.JointName,
        end: VNHumanBodyPoseObservation.JointName
    ) {
        switch self {
        case .leftShoulder: return (.leftElbow, .leftShoulder, .leftHip)
        case .rightShoulder: return (.rightElbow, .rightShoulder, .rightHip)
        case .leftElbow: return (.leftShoulder, .leftElbow, .leftWrist)
        case .rightElbow: return (.rightShoulder, .rightElbow, .rightWrist)
        case .spine: return (.neck, .root, .nose)
        case .leftHip: return (.leftShoulder, .leftHip, .leftKnee)
        case .rightHip: return (.rightShoulder, .rightHip, .rightKnee)
        case .leftKnee: return (.leftHip, .leftKnee, .leftAnkle)
        case .rightKnee: return (.rightHip, .rightKnee, .rightAnkle)
        }
    }
}

enum AutoSwingPhase: String, Equatable {
    case watching
    case address
    case backswing
    case downswing
    case impact
    case complete
    case cancelled

    var statusText: String {
        switch self {
        case .watching: return "Auto · looking for address"
        case .address: return "Auto · recording, take the swing"
        case .backswing: return "Auto · backswing"
        case .downswing: return "Auto · downswing"
        case .impact: return "Auto · impact"
        case .complete: return "Auto · swing captured"
        case .cancelled: return "Auto · no swing, still watching"
        }
    }
}

enum AutoSwingCommand: Equatable {
    case startCapture
    case finishCapture
    case cancelCapture
}
