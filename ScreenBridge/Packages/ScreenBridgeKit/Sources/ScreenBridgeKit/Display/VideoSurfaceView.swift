import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Shows a `DisplayStreamController`'s video (letterboxed to the Host's
/// aspect ratio) and turns touches, Apple Pencil, trackpad and mouse input
/// on it into input for the Mac.
///
/// iPad gestures:
/// - 1 finger / Pencil: tap = click, double-tap = double-click, drag = drag
/// - Pencil hover / trackpad pointer: moves the Mac's cursor
/// - 2-finger drag: scroll · 2-finger tap: right-click
/// - 3-finger tap: show/hide the overlay (`onToggleControls`)
public struct VideoSurfaceView {
    let controller: DisplayStreamController
    let onToggleControls: () -> Void

    public init(controller: DisplayStreamController, onToggleControls: @escaping () -> Void = {}) {
        self.controller = controller
        self.onToggleControls = onToggleControls
    }

    fileprivate func configure(_ view: LayerHostingView) {
        let controller = self.controller
        view.videoSize = { controller.videoSize }
        view.onInput = { controller.sendInput($0) }
        view.onToggleControls = onToggleControls
    }
}

#if os(iOS)
extension VideoSurfaceView: UIViewRepresentable {
    public func makeUIView(context: Context) -> LayerHostingView {
        let view = LayerHostingView(hosted: controller.displayLayer)
        configure(view)
        return view
    }

    public func updateUIView(_ view: LayerHostingView, context: Context) {
        configure(view)
    }
}

public final class LayerHostingView: UIView, UIGestureRecognizerDelegate {
    var videoSize: () -> CGSize? = { nil }
    var onInput: (InputEvent) -> Void = { _ in }
    var onToggleControls: () -> Void = {}

    private let hosted: CALayer

    // One-finger state. A finger press is held back briefly so that the
    // start of a two-finger scroll doesn't click whatever is under it.
    private var pendingPress: CGPoint?
    private var pendingWork: DispatchWorkItem?
    private var buttonDown = false
    private var pressIsPencil = false
    private var lastScrollTranslation = CGPoint.zero
    private static let pressDelay: TimeInterval = 0.08
    private static let dragThreshold: CGFloat = 6

    init(hosted: CALayer) {
        self.hosted = hosted
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(hosted)
        isMultipleTouchEnabled = true
        installGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted.frame = bounds
        CATransaction.commit()
    }

    private func installGestures() {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.numberOfTouchesRequired = 1
        press.delegate = self

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.allowedScrollTypesMask = .all  // trackpad two-finger scrolling too
        scroll.delegate = self

        let rightClick = UITapGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.numberOfTouchesRequired = 2
        rightClick.delegate = self

        let toggle = UITapGestureRecognizer(target: self, action: #selector(handleToggle(_:)))
        toggle.numberOfTouchesRequired = 3

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))

        [press, scroll, rightClick, toggle, hover].forEach(addGestureRecognizer)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UILongPressGestureRecognizer {
            pressIsPencil = touch.type == .pencil
        }
        return true
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        VideoGeometry.normalize(point, videoSize: videoSize() ?? bounds.size, in: bounds)
    }

    private func sendPointer(_ phase: PointerPhase, _ button: PointerButton, at point: CGPoint) {
        let p = normalized(point)
        onInput(.pointer(phase: phase, button: button, x: Double(p.x), y: Double(p.y)))
    }

    // MARK: One finger / Pencil

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            if pressIsPencil {
                pressDown(at: point)  // a Pencil is never the start of a scroll
            } else {
                pendingPress = point
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let start = self.pendingPress else { return }
                    self.pressDown(at: start)
                }
                pendingWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.pressDelay, execute: work)
            }
        case .changed:
            if let start = pendingPress, hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold {
                pressDown(at: start)
            }
            if buttonDown { sendPointer(.moved, .left, at: point) }
        case .ended:
            if let start = pendingPress { pressDown(at: start) }  // quick tap
            if buttonDown {
                buttonDown = false
                sendPointer(.ended, .left, at: point)
            }
        case .cancelled, .failed:
            cancelPendingPress()
            if buttonDown {
                buttonDown = false
                sendPointer(.cancelled, .left, at: point)
            }
        default:
            break
        }
    }

    private func pressDown(at point: CGPoint) {
        cancelPendingPress()
        guard !buttonDown else { return }
        buttonDown = true
        sendPointer(.began, .left, at: point)
    }

    private func cancelPendingPress() {
        pendingWork?.cancel()
        pendingWork = nil
        pendingPress = nil
    }

    // MARK: Two fingers

    @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
        let location = normalized(recognizer.location(in: self))
        let translation = recognizer.translation(in: self)
        let scale = VideoGeometry.pointScale(videoSize: videoSize() ?? bounds.size, in: bounds)
            / max(window?.screen.scale ?? 2, 1)
        switch recognizer.state {
        case .began:
            // Two fingers down: this is a scroll, not a click.
            cancelPendingPress()
            if buttonDown {
                buttonDown = false
                sendPointer(.cancelled, .left, at: recognizer.location(in: self))
            }
            lastScrollTranslation = .zero
            onInput(.scroll(phase: .began, x: Double(location.x), y: Double(location.y), deltaX: 0, deltaY: 0))
        case .changed:
            let dx = (translation.x - lastScrollTranslation.x) * scale
            let dy = (translation.y - lastScrollTranslation.y) * scale
            lastScrollTranslation = translation
            onInput(.scroll(phase: .moved, x: Double(location.x), y: Double(location.y),
                            deltaX: Double(dx), deltaY: Double(dy)))
        case .ended, .cancelled, .failed:
            onInput(.scroll(phase: .ended, x: Double(location.x), y: Double(location.y), deltaX: 0, deltaY: 0))
        default:
            break
        }
    }

    @objc private func handleRightClick(_ recognizer: UITapGestureRecognizer) {
        cancelPendingPress()
        let p = normalized(recognizer.location(in: self))
        onInput(.rightClick(x: Double(p.x), y: Double(p.y)))
    }

    @objc private func handleToggle(_ recognizer: UITapGestureRecognizer) {
        onToggleControls()
    }

    // MARK: Hover (Pencil hover, trackpad, mouse)

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            if !buttonDown { sendPointer(.moved, .none, at: recognizer.location(in: self)) }
        default:
            break
        }
    }
}

#elseif os(macOS)
extension VideoSurfaceView: NSViewRepresentable {
    public func makeNSView(context: Context) -> LayerHostingView {
        let view = LayerHostingView(hosted: controller.displayLayer)
        configure(view)
        return view
    }

    public func updateNSView(_ view: LayerHostingView, context: Context) {
        configure(view)
    }
}

/// On a Mac acting as the display, its own mouse and trackpad control the
/// Host while the pointer is over the video.
public final class LayerHostingView: NSView {
    var videoSize: () -> CGSize? = { nil }
    var onInput: (InputEvent) -> Void = { _ in }
    var onToggleControls: () -> Void = {}

    private let hosted: CALayer
    private var trackingArea: NSTrackingArea?

    init(hosted: CALayer) {
        self.hosted = hosted
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(hosted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }  // top-left origin, like the wire format
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted.frame = bounds
        CATransaction.commit()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func normalized(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return VideoGeometry.normalize(point, videoSize: videoSize() ?? bounds.size, in: bounds)
    }

    private func pointer(_ phase: PointerPhase, _ button: PointerButton, _ event: NSEvent) {
        let p = normalized(event)
        onInput(.pointer(phase: phase, button: button, x: Double(p.x), y: Double(p.y)))
    }

    public override func mouseDown(with event: NSEvent) { pointer(.began, .left, event) }
    public override func mouseDragged(with event: NSEvent) { pointer(.moved, .left, event) }
    public override func mouseUp(with event: NSEvent) { pointer(.ended, .left, event) }
    public override func mouseMoved(with event: NSEvent) { pointer(.moved, .none, event) }

    public override func rightMouseDown(with event: NSEvent) {
        let p = normalized(event)
        onInput(.rightClick(x: Double(p.x), y: Double(p.y)))
    }

    public override func scrollWheel(with event: NSEvent) {
        let p = normalized(event)
        let scale = Double(VideoGeometry.pointScale(videoSize: videoSize() ?? bounds.size, in: bounds)
                           / max(window?.backingScaleFactor ?? 2, 1))
        let phase: PointerPhase = event.phase == .began ? .began : (event.phase == .ended ? .ended : .moved)
        onInput(.scroll(phase: phase, x: Double(p.x), y: Double(p.y),
                        deltaX: Double(event.scrollingDeltaX) * scale,
                        deltaY: Double(event.scrollingDeltaY) * scale))
    }
}
#endif
