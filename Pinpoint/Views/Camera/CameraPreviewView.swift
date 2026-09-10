@preconcurrency import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var isFrontCamera = false

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.isFrontCamera = isFrontCamera
        view.syncRotationCoordinator()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        if uiView.isFrontCamera != isFrontCamera {
            uiView.isFrontCamera = isFrontCamera
            uiView.resetRotationCoordinator()
        }
        uiView.syncRotationCoordinator()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var coordinatedDeviceID: String?
        var isFrontCamera = false

        func resetRotationCoordinator() {
            rotationObservation?.invalidate()
            rotationObservation = nil
            rotationCoordinator = nil
            coordinatedDeviceID = nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            syncRotationCoordinator()
        }

        func syncRotationCoordinator() {
            guard let device = currentVideoDevice() else { return }
            if coordinatedDeviceID != device.uniqueID {
                rotationObservation?.invalidate()
                let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                rotationCoordinator = coordinator
                coordinatedDeviceID = device.uniqueID
                rotationObservation = coordinator.observe(
                    \.videoRotationAngleForHorizonLevelPreview,
                    options: [.initial, .new]
                ) { [weak self] coordinator, _ in
                    let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                    DispatchQueue.main.async {
                        self?.apply(previewAngle: angle)
                    }
                }
            }
            apply(previewAngle: rotationCoordinator?.videoRotationAngleForHorizonLevelPreview)
        }

        private func apply(previewAngle: CGFloat?) {
            guard let connection = previewLayer.connection else { return }
            let angle = previewAngle ?? CameraService.currentVideoRotationAngle()
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = true
            }
        }

        private func currentVideoDevice() -> AVCaptureDevice? {
            previewLayer.session?
                .inputs
                .compactMap { $0 as? AVCaptureDeviceInput }
                .first { $0.device.hasMediaType(.video) }?
                .device
        }

        deinit {
            rotationObservation?.invalidate()
        }
    }
}

struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    @Binding var videoRect: CGRect

    init(player: AVPlayer, videoRect: Binding<CGRect> = .constant(.zero)) {
        self.player = player
        self._videoRect = videoRect
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(videoRect: $videoRect)
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(player: player)
        view.onVideoRectChange = { rect in
            context.coordinator.update(rect)
        }
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
        context.coordinator.videoRect = $videoRect
        uiView.onVideoRectChange = { rect in
            context.coordinator.update(rect)
        }
        DispatchQueue.main.async {
            uiView.reportVideoRect()
        }
    }

    final class Coordinator {
        var videoRect: Binding<CGRect>
        private var readyObservation: NSKeyValueObservation?
        private var lastReported = CGRect.null

        init(videoRect: Binding<CGRect>) {
            self.videoRect = videoRect
        }

        deinit {
            readyObservation?.invalidate()
        }

        func observe(_ view: PlayerUIView) {
            readyObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak view] _, _ in
                DispatchQueue.main.async {
                    view?.reportVideoRect()
                }
            }
        }

        func update(_ rect: CGRect) {
            guard rect != lastReported else { return }
            lastReported = rect
            DispatchQueue.main.async { [weak self] in
                guard let self, self.videoRect.wrappedValue != rect else { return }
                self.videoRect.wrappedValue = rect
            }
        }
    }

    final class PlayerUIView: UIView {
        let playerLayer = AVPlayerLayer()
        var onVideoRectChange: ((CGRect) -> Void)?

        init(player: AVPlayer) {
            super.init(frame: .zero)
            backgroundColor = .black
            isOpaque = true
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            layer.addSublayer(playerLayer)
            setContentHuggingPriority(.defaultLow, for: .horizontal)
            setContentHuggingPriority(.defaultLow, for: .vertical)
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
            reportVideoRect()
        }

        func reportVideoRect() {
            onVideoRectChange?(playerLayer.videoRect)
        }
    }
}
