import SwiftUI
import UIKit

struct SwingPlaybackView: View {
    @Environment(SwingLibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    let swing: Swing

    @State private var playback = VideoPlaybackController()
    @State private var annotations: [Annotation] = []
    @State private var tool: AnnotationTool = .none
    @State private var colorHex = "FFFFFF"
    @State private var showPose = false
    @State private var showVideo = true
    @State private var showAngles = false
    @State private var visibleAngles: Set<PoseAngle> = Set(PoseAngle.allCases)
    @State private var isEditing = false
    @State private var isViewMenuOpen = false
    @State private var pose = PlaybackPoseController()
    @State private var loadFailed = false
    @State private var playerVideoRect: CGRect = .zero
    @State private var showTagEditor = false

    private var current: Swing {
        library.swings.first(where: { $0.id == swing.id }) ?? swing
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if current.syncStatus == .cloudOnly {
                cloudOnlyState
            } else {
                videoStage
            }
        }
        .overlay(alignment: .trailing) {
            if current.hasLocalVideo {
                FrameScrubberView(
                    currentFrame: playback.currentFrame,
                    totalFrames: playback.totalFrames,
                    onScrubStart: { playback.beginScrub() },
                    onSeek: { frame in
                        playback.scrub(toFrame: frame)
                    },
                    onScrubEnd: { playback.endScrub() }
                )
                .ignoresSafeArea()
            }
        }
        .defersSystemGestures(on: .trailing)
        .background(DisableInteractivePopGesture())
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showTagEditor = true
                } label: {
                    Image(systemName: current.tags.isEmpty ? "tag" : "tag.fill")
                }
                .accessibilityLabel("Tags")

                Menu {
                    Button {
                        showTagEditor = true
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                    if current.syncStatus == .local {
                        Button {
                            Task { await library.upload(current) }
                        } label: {
                            Label("Upload to cloud", systemImage: "cloud")
                        }
                    }
                    ShareLink(item: library.videoURL(for: current)) {
                        Label("Share video", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!current.hasLocalVideo)
                } label: {
                    Image(systemName: current.syncStatus.systemImage)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if current.hasLocalVideo {
                PlaybackBarView(
                    isPlaying: playback.isPlaying,
                    currentFrame: playback.currentFrame,
                    totalFrames: playback.totalFrames,
                    currentTimeLabel: playback.currentTimeLabel,
                    durationLabel: playback.durationLabel,
                    playbackRate: playback.playbackRate,
                    onTogglePlay: { playback.togglePlay() },
                    onScrubStart: { playback.beginScrub() },
                    onSeekProgress: { progress in
                        playback.scrub(toFrame: Int((progress * Double(max(playback.totalFrames - 1, 0))).rounded()))
                    },
                    onScrubEnd: { playback.endScrub() },
                    onSetRate: { playback.setRate($0) }
                )
            }
        }
        .task {
            annotations = current.annotations
            guard current.hasLocalVideo else { return }
            let url = library.videoURL(for: current)
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadFailed = true
                return
            }
            await playback.load(
                url: url,
                recordedFrameRate: current.frameRate,
                durationHint: current.duration
            )
            pose.prepare(url: url, frameRate: playback.frameRate)
        }
        .onChange(of: showPose) { _, enabled in
            pose.setEnabled(
                enabled,
                frame: playback.currentFrame,
                time: playback.currentTime,
                frameRate: playback.frameRate
            )
        }
        .onChange(of: showAngles) { _, enabled in
            if enabled { showPose = true }
        }
        .onChange(of: showVideo) { _, visible in
            if !visible { showPose = true }
        }
        .onChange(of: isViewMenuOpen) { _, open in
            if open { isEditing = false }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                isViewMenuOpen = false
                if case .none = tool {
                    tool = .draw(.pen)
                }
            } else {
                tool = .none
            }
        }
        .onChange(of: playback.currentFrame) { _, frame in
            guard showPose else { return }
            pose.update(frame: frame, time: playback.currentTime, frameRate: playback.frameRate)
        }
        .onDisappear {
            playback.pause()
            library.updateAnnotations(current, annotations: annotations)
        }
        .onChange(of: annotations) { _, newValue in
            library.updateAnnotations(current, annotations: newValue)
        }
        .onChange(of: current.hasLocalVideo) { _, hasVideo in
            guard hasVideo else { return }
            Task {
                await playback.load(
                    url: library.videoURL(for: current),
                    recordedFrameRate: current.frameRate,
                    durationHint: current.duration
                )
                pose.prepare(url: library.videoURL(for: current), frameRate: playback.frameRate)
                pose.setEnabled(
                    showPose,
                    frame: playback.currentFrame,
                    time: playback.currentTime,
                    frameRate: playback.frameRate
                )
            }
        }
        .alert("Video missing", isPresented: $loadFailed) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("This swing's video isn't on this iPhone.")
        }
        .sheet(isPresented: $showTagEditor) {
            SwingTagEditorView(swing: current)
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var videoStage: some View {
        ZStack {
            videoAndPose

            AnnotationOverlayView(
                annotations: $annotations,
                tool: $tool,
                colorHex: colorHex,
                isEditing: isEditing
            )
            .padding(.leading, 52)
            .padding(.trailing, 48)
            .padding(.bottom, 8)
        }
        .overlay {
            if showPose, showAngles {
                MovablePoseAngleReadoutView(
                    skeleton: pose.skeleton,
                    visibleAngles: visibleAngles,
                    onDismiss: { showAngles = false }
                )
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    PoseViewOptionsButton(isOpen: $isViewMenuOpen, isActive: showPose || !showVideo)
                    AnnotationToolbarView(
                        tool: $tool,
                        colorHex: $colorHex,
                        isExpanded: $isEditing,
                        canUndo: !annotations.isEmpty,
                        onUndo: {
                            if !annotations.isEmpty { annotations.removeLast() }
                        },
                        onClear: { annotations.removeAll() }
                    )
                }

                if isViewMenuOpen {
                    PoseViewOptionsPanel(
                        showPose: $showPose,
                        showVideo: $showVideo,
                        showAngles: $showAngles,
                        visibleAngles: $visibleAngles
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.leading, 10)
            .padding(.top, 12)
            .animation(.easeInOut(duration: 0.2), value: isViewMenuOpen)
        }
        .animation(.easeInOut(duration: 0.2), value: showAngles)
    }

    private var videoAndPose: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                PlayerView(player: playback.player, videoRect: $playerVideoRect)
                    .frame(width: size.width, height: size.height)
                    .opacity(showVideo ? 1 : 0)
                    .allowsHitTesting(false)

                if showPose {
                    PoseOverlayView(
                        skeleton: pose.skeleton,
                        videoSize: overlayVideoSize,
                        gravity: .fit,
                        videoRect: playerVideoRect,
                        showAngles: showAngles,
                        visibleAngles: visibleAngles
                    )
                    .frame(width: size.width, height: size.height)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var overlayVideoSize: CGSize {
        if playback.videoSize.width > 0, playback.videoSize.height > 0 {
            return playback.videoSize
        }
        return CGSize(width: current.width, height: current.height)
    }

    private var cloudOnlyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 42))
                .foregroundStyle(PinpointTheme.accent)
            Text("This swing is in the cloud")
                .font(.title3.weight(.semibold))
            Text("Download it to this iPhone to play it back frame by frame.")
                .font(.body)
                .foregroundStyle(PinpointTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await library.download(current) }
            } label: {
                Label(
                    current.syncStatus == .downloading ? "Downloading…" : "Download",
                    systemImage: "cloud"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(current.syncStatus == .downloading)
            .padding(.horizontal, 48)
        }
    }
}

private struct DisableInteractivePopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        private var wasEnabled: Bool?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            if wasEnabled == nil {
                wasEnabled = gesture.isEnabled
            }
            gesture.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let wasEnabled {
                navigationController?.interactivePopGestureRecognizer?.isEnabled = wasEnabled
            }
        }
    }
}
