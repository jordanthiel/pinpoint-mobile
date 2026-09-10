import SwiftUI
import UIKit

struct FrameScrubberView: View {
    let currentFrame: Int
    let totalFrames: Int
    let onScrubStart: () -> Void
    let onSeek: (Int) -> Void
    let onScrubEnd: () -> Void

    var body: some View {
        FrameScrubberRepresentable(
            currentFrame: currentFrame,
            totalFrames: totalFrames,
            onScrubStart: onScrubStart,
            onSeek: onSeek,
            onScrubEnd: onScrubEnd
        )
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("Frame scrubber")
        .accessibilityValue("Frame \(currentFrame + 1) of \(max(totalFrames, 1))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(currentFrame + 1)
            case .decrement: onSeek(currentFrame - 1)
            default: break
            }
        }
    }
}

private struct FrameScrubberRepresentable: UIViewRepresentable {
    var currentFrame: Int
    var totalFrames: Int
    var onScrubStart: () -> Void
    var onSeek: (Int) -> Void
    var onScrubEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> FrameScrubberUIView {
        let view = FrameScrubberUIView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: FrameScrubberUIView, context: Context) {
        context.coordinator.onScrubStart = onScrubStart
        context.coordinator.onSeek = onSeek
        context.coordinator.onScrubEnd = onScrubEnd
        uiView.update(currentFrame: currentFrame, totalFrames: max(totalFrames, 1))
    }

    final class Coordinator {
        weak var view: FrameScrubberUIView?
        var onScrubStart: () -> Void = {}
        var onSeek: (Int) -> Void = { _ in }
        var onScrubEnd: () -> Void = {}
        var didStartScrub = false

        func beginScrubIfNeeded() {
            guard !didStartScrub else { return }
            didStartScrub = true
            onScrubStart()
        }

        func endScrub() {
            guard didStartScrub else { return }
            didStartScrub = false
            onScrubEnd()
        }
    }
}

fileprivate final class FrameScrubberUIView: UIView, UIScrollViewDelegate {
    weak var coordinator: FrameScrubberRepresentable.Coordinator?

    private let scrollView = UIScrollView()
    private let ticksView = TickStripView()
    private let tickSpacing: CGFloat = 11
    private var totalFrames = 1
    private var lastEmittedFrame = 0
    private var lastEmitTime: CFTimeInterval = 0
    private var ignoreProgrammaticScroll = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.28)
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.backgroundColor = .clear
        addSubview(scrollView)

        ticksView.backgroundColor = .clear
        ticksView.isOpaque = false
        ticksView.isUserInteractionEnabled = false
        ticksView.contentMode = .redraw
        addSubview(ticksView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        ticksView.frame = bounds
        let inset = bounds.height / 2
        if abs(scrollView.contentInset.top - inset) > 0.5 {
            scrollView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
            scrollView.verticalScrollIndicatorInsets = scrollView.contentInset
            rebuildContentSize()
            setOffset(for: lastEmittedFrame)
        }
        refreshTicks()
    }

    func update(currentFrame: Int, totalFrames: Int) {
        let frames = max(totalFrames, 1)
        let frame = min(max(currentFrame, 0), frames - 1)
        let framesChanged = frames != self.totalFrames
        self.totalFrames = frames

        if framesChanged {
            rebuildContentSize()
        }

        if scrollView.isDragging || scrollView.isDecelerating {
            return
        }

        if framesChanged || frame != lastEmittedFrame {
            lastEmittedFrame = frame
            setOffset(for: frame)
            refreshTicks()
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        coordinator?.beginScrubIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refreshTicks()
        guard !ignoreProgrammaticScroll else { return }
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        coordinator?.beginScrubIfNeeded()
        emitFrame(from: scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        emitFrame(from: scrollView, force: true)
        if !decelerate {
            snap(to: frameIndex(from: scrollView))
            coordinator?.endScrub()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        emitFrame(from: scrollView, force: true)
        snap(to: frameIndex(from: scrollView))
        coordinator?.endScrub()
    }

    private func rebuildContentSize() {
        let height = CGFloat(max(totalFrames - 1, 0)) * tickSpacing
        scrollView.contentSize = CGSize(width: bounds.width, height: max(height, 1))
    }

    private func setOffset(for frame: Int) {
        ignoreProgrammaticScroll = true
        let y = CGFloat(frame) * tickSpacing - scrollView.adjustedContentInset.top
        scrollView.contentOffset = CGPoint(x: 0, y: y)
        ignoreProgrammaticScroll = false
    }

    private func snap(to frame: Int) {
        ignoreProgrammaticScroll = true
        let y = CGFloat(frame) * tickSpacing - scrollView.adjustedContentInset.top
        scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        ignoreProgrammaticScroll = false
        lastEmittedFrame = frame
    }

    private func frameIndex(from scrollView: UIScrollView) -> Int {
        let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let frame = Int((y / tickSpacing).rounded())
        return min(max(frame, 0), max(totalFrames - 1, 0))
    }

    private func emitFrame(from scrollView: UIScrollView, force: Bool = false) {
        let frame = frameIndex(from: scrollView)
        let now = CACurrentMediaTime()
        if !force {
            if frame == lastEmittedFrame { return }
            if now - lastEmitTime < 1.0 / 40.0 { return }
        }
        lastEmitTime = now
        lastEmittedFrame = frame
        coordinator?.onSeek(frame)
    }

    private func refreshTicks() {
        ticksView.offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        ticksView.tickSpacing = tickSpacing
        ticksView.setNeedsDisplay()
    }
}

fileprivate final class TickStripView: UIView {
    var offset: CGFloat = 0
    var tickSpacing: CGFloat = 11

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        var y = -offset.truncatingRemainder(dividingBy: tickSpacing)
        if y > 0 { y -= tickSpacing }
        var tick = Int(floor(offset / tickSpacing))

        while y < bounds.height + tickSpacing {
            let isMajor = tick.isMultiple(of: 5)
            let inset: CGFloat = isMajor ? 7 : 12
            context.setStrokeColor(UIColor.white.withAlphaComponent(isMajor ? 0.85 : 0.25).cgColor)
            context.setLineWidth(isMajor ? 1.5 : 1)
            context.move(to: CGPoint(x: inset, y: y))
            context.addLine(to: CGPoint(x: bounds.width - inset, y: y))
            context.strokePath()
            y += tickSpacing
            tick += 1
        }

        context.setStrokeColor(UIColor(PinpointTheme.accent).cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 3, y: bounds.midY))
        context.addLine(to: CGPoint(x: bounds.width - 3, y: bounds.midY))
        context.strokePath()
    }
}
