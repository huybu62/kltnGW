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
/// - 2-finger drag: scroll · 2-finger tap: right-click · pinch: zoom
/// - Apple Pencil (2nd gen / Pro) double-tap: right-click at the Pencil
/// - Hold 2 fingers still for ~0.6 s, or 3-finger tap: show/hide the
///   status overlay (`onToggleControls`)
/// - 3-finger tap: show/hide the shortcut bar (`onToggleShortcutBar`)
/// - 3-finger swipe: ← → switch Desktops / full-screen apps (⌃← ⌃→),
///   ↑ Mission Control (⌃↑), ↓ App Exposé (⌃↓), like a Mac trackpad
/// - Lifting the Pencil out of hover range near a screen edge nudges the
///   pointer off the edge, so an auto-hiding Dock closes after you pick an app
/// - Apple Pencil acts as a pen tablet (pressure, tilt) for drawing apps;
///   while the Pencil is in use, the resting hand is ignored (palm rejection)
/// - Hardware keyboard (Smart Keyboard Folio…) and Magic Trackpad go to the
///   Mac; the iPad's own round pointer is hidden over the video.
public struct VideoSurfaceView {
    let controller: DisplayStreamController
    let onToggleControls: () -> Void
    let onToggleShortcutBar: () -> Void

    /// - Parameters:
    ///   - onToggleControls: hold two fingers still (~0.6 s): status overlay.
    ///   - onToggleShortcutBar: three-finger tap: shortcut bar.
    public init(controller: DisplayStreamController,
                onToggleControls: @escaping () -> Void = {},
                onToggleShortcutBar: @escaping () -> Void = {}) {
        self.controller = controller
        self.onToggleControls = onToggleControls
        self.onToggleShortcutBar = onToggleShortcutBar
    }

    fileprivate func configure(_ view: LayerHostingView) {
        let controller = self.controller
        view.videoSize = { controller.videoSize }
        view.streamFrameRate = { controller.streamFrameRate }
        view.onInput = { controller.sendInput($0) }
        view.onToggleControls = onToggleControls
        view.onToggleShortcutBar = onToggleShortcutBar
        view.drawsCursor = { controller.drawsCursor }
        view.extraModifierFlags = { controller.shortcutBarModifierFlags }
        controller.onCursorUpdate = { [weak view] point, visible in
            view?.remoteCursorMoved(to: point, visible: visible)
        }
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

public final class LayerHostingView: UIView, UIGestureRecognizerDelegate, UIPointerInteractionDelegate,
                                     UIPencilInteractionDelegate {
    var videoSize: () -> CGSize? = { nil }
    var streamFrameRate: () -> Int? = { nil }
    var drawsCursor: () -> Bool = { false }
    /// Modifiers held on the shortcut bar, reported along with the keyboard's.
    var extraModifierFlags: () -> UInt32 = { 0 }

    /// The pointer drawn locally (when the Mac leaves it out of the video):
    /// it follows touch/trackpad/Pencil instantly instead of a network
    /// round trip later.
    private let cursorLayer = CAShapeLayer()
    private var lastLocalPointerTime: CFTimeInterval = 0

    // Apple Pencil as a pen tablet + palm rejection
    private weak var pressRecognizer: UILongPressGestureRecognizer?
    private var pencilTouch: UITouch?
    private var lastPencilActivity: CFTimeInterval = 0
    private var penInProximity = false
    /// Fingers are ignored this long after the Pencil was last used.
    private static let palmRejectionWindow: CFTimeInterval = 1.0
    /// Touches wider than this are a palm or the side of a hand, not a
    /// fingertip. iPadOS reports radii in steps of ~10.4 pt and an ordinary
    /// fingertip is often 20.8 or 31.3, so only 52+ counts as a palm.
    private static let palmRadius: CGFloat = 50

    /// ProMotion drops to 60 Hz (or lower) when an app looks idle, and
    /// trackpad / Pencil-hover positions are only reported at the display's
    /// current rate. While the Mac streams above 60 fps, this display link
    /// asks iPadOS to stay at 120 Hz.
    private var displayLink: CADisplayLink?
    private var wantsHighRate = false
    private var ticksSinceRateCheck = 0
    private static let highRate = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    /// Otherwise ask for a steady 60 Hz. (Never lower: touch, trackpad and
    /// Pencil positions are reported at the display's refresh rate, so a
    /// lower rate makes the pointer lag.)
    private static let lowRate = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    var onInput: (InputEvent) -> Void = { _ in }
    var onToggleControls: () -> Void = {}
    var onToggleShortcutBar: () -> Void = {}

    private let hosted: CALayer

    // One-finger state. A finger press is held back briefly so that the
    // start of a two-finger scroll doesn't click whatever is under it.
    private var pendingPress: CGPoint?
    private var pendingWork: DispatchWorkItem?
    private var buttonDown = false
    /// Pencil and trackpad clicks can't be the start of a two-finger
    /// scroll, so they skip the hold-back delay.
    private var pressIsImmediate = false
    private var pressIsPencil = false
    private var heldKeys = Set<UInt16>()
    private var lastScrollTranslation = CGPoint.zero
    /// While a pinch is clearly under way, two-finger scrolling pauses.
    private var pinching = false
    private var lastZoomStepScale: CGFloat = 1
    private static let zoomStep: CGFloat = 1.18
    /// Where the Pencil last touched or hovered (target of its double-tap).
    private var lastPencilPoint: CGPoint?
    /// The current hover comes from an Apple Pencil (not the trackpad).
    private var hoverIsPencil = false
    private var lastHoverPoint: CGPoint?
    /// The Pencil clicked since it last left hover range; when it leaves
    /// again, the pointer is moved off the screen edge (see `nudgeOffScreenEdge`).
    private var pencilClicked = false
    private var pencilNudgeWork: DispatchWorkItem?
    private static let pressDelay: TimeInterval = 0.08
    private static let dragThreshold: CGFloat = 6

    init(hosted: CALayer) {
        self.hosted = hosted
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(hosted)
        isMultipleTouchEnabled = true
        setUpCursorLayer()
        installGestures()
    }

    // MARK: Local pointer

    private func setUpCursorLayer() {
        // The classic macOS arrow, tip at (0, 0).
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: 17))
        path.addLine(to: CGPoint(x: 4.2, y: 13.2))
        path.addLine(to: CGPoint(x: 7, y: 19.5))
        path.addLine(to: CGPoint(x: 9.6, y: 18.4))
        path.addLine(to: CGPoint(x: 6.9, y: 12.2))
        path.addLine(to: CGPoint(x: 12.2, y: 12.2))
        path.close()
        cursorLayer.path = path.cgPath
        cursorLayer.fillColor = UIColor.black.cgColor
        cursorLayer.strokeColor = UIColor.white.cgColor
        cursorLayer.lineWidth = 1.2
        cursorLayer.lineJoin = .round
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 13, height: 20)
        cursorLayer.anchorPoint = .zero
        cursorLayer.shadowOpacity = 0.3
        cursorLayer.shadowRadius = 1.5
        cursorLayer.shadowOffset = CGSize(width: 0, height: 1)
        cursorLayer.zPosition = 10
        cursorLayer.isHidden = true
        layer.addSublayer(cursorLayer)
    }

    private func placeCursor(at point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.position = point
        cursorLayer.isHidden = false
        CATransaction.commit()
    }

    /// Our own input moved the pointer: draw it there now.
    private func moveLocalCursor(to point: CGPoint) {
        guard drawsCursor() else {
            if !cursorLayer.isHidden { cursorLayer.isHidden = true }
            return
        }
        lastLocalPointerTime = CACurrentMediaTime()
        placeCursor(at: point)
    }

    /// The Mac reports where its pointer is (e.g. moved by the Mac's own trackpad).
    func remoteCursorMoved(to normalizedPoint: CGPoint, visible: Bool) {
        guard drawsCursor() else {
            cursorLayer.isHidden = true
            return
        }
        // Right after local input this is just our own movement arriving late.
        guard CACurrentMediaTime() - lastLocalPointerTime > 0.3 else { return }
        guard visible else {
            cursorLayer.isHidden = true
            return
        }
        let rect = VideoGeometry.videoRect(videoSize: videoSize() ?? bounds.size, in: bounds)
        placeCursor(at: CGPoint(x: rect.minX + normalizedPoint.x * rect.width,
                                y: rect.minY + normalizedPoint.y * rect.height))
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
        pressRecognizer = press

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = self

        let rightClick = UITapGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.numberOfTouchesRequired = 2
        rightClick.delegate = self

        let toggle = UITapGestureRecognizer(target: self, action: #selector(handleToggle(_:)))
        toggle.numberOfTouchesRequired = 3
        toggle.delegate = self

        // Hold two fingers still: show/hide the overlay. A quick two-finger
        // tap is still a right-click (it waits only until the hold fails).
        let holdToggle = UILongPressGestureRecognizer(target: self, action: #selector(handleHoldToggle(_:)))
        holdToggle.numberOfTouchesRequired = 2
        holdToggle.minimumPressDuration = 0.6
        holdToggle.allowableMovement = 12
        holdToggle.delegate = self
        rightClick.require(toFail: holdToggle)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self

        let threeFingerSwipe = UIPanGestureRecognizer(target: self, action: #selector(handleThreeFingerSwipe(_:)))
        threeFingerSwipe.minimumNumberOfTouches = 3
        threeFingerSwipe.maximumNumberOfTouches = 3
        threeFingerSwipe.delegate = self

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))

        // Trackpad / mouse: two-finger click = right-click, two-finger swipe = scroll.
        let secondaryClick = UITapGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        secondaryClick.buttonMaskRequired = .secondary
        // Trackpad / mouse only. For fingers and the Pencil iPadOS ignores the
        // button mask, so without this every tap was also a right-click.
        secondaryClick.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        let wheel = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        wheel.allowedScrollTypesMask = .all
        wheel.allowedTouchTypes = []  // scroll events only, never fingers on the glass
        wheel.delegate = self

        [press, scroll, rightClick, toggle, holdToggle, pinch, threeFingerSwipe, hover, secondaryClick, wheel]
            .forEach(addGestureRecognizer)
        addInteraction(UIPointerInteraction(delegate: self))
        // `UIPencilInteraction(delegate:)` is iPadOS 17.5+; set the delegate instead.
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
    }

    // MARK: Apple Pencil double-tap → right-click

    // Deprecated in iPadOS 17.5 in favour of `pencilInteraction(_:didReceiveTap:)`,
    // but it's the one that works on every supported version.
    public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        let point = lastPencilPoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let p = normalized(point)
        onInput(.rightClick(x: Double(p.x), y: Double(p.y)))
    }

    // MARK: Pointer (hide the iPad's own cursor; the Mac draws its own in the video)

    public func pointerInteraction(_ interaction: UIPointerInteraction,
                                   styleFor region: UIPointerRegion) -> UIPointerStyle? {
        UIPointerStyle.hidden()
    }

    // MARK: Keyboard

    public override var canBecomeFirstResponder: Bool { true }

    /// Turns off iPadOS's three-finger undo/redo/copy gestures over the
    /// video, so three-finger swipes reach the Mac.
    public override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

    /// Tells the Mac which modifier keys are really held right now.
    private func sendModifiers(of recognizer: UIGestureRecognizer) {
        let flags = UInt32(truncatingIfNeeded: recognizer.modifierFlags.rawValue) & 0x1E_0000  // ⇧ ⌃ ⌥ ⌘
        onInput(.modifierState(flags: flags | extraModifierFlags()))
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
            startHighRefreshRate()
        } else {
            releaseHeldKeys()
            stopHighRefreshRate()
        }
    }

    // MARK: ProMotion

    private func startHighRefreshRate() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        link.preferredFrameRateRange = Self.lowRate
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopHighRefreshRate() {
        displayLink?.invalidate()  // CADisplayLink retains its target; break the cycle
        displayLink = nil
    }

    /// Re-checks the stream's frame rate about twice a second.
    @objc private func displayLinkTick() {
        ticksSinceRateCheck += 1
        guard ticksSinceRateCheck >= (wantsHighRate ? 60 : 15) else { return }
        ticksSinceRateCheck = 0
        let wanted = (streamFrameRate() ?? 60) > 60
        guard wanted != wantsHighRate else { return }
        wantsHighRate = wanted
        displayLink?.preferredFrameRateRange = wanted ? Self.highRate : Self.lowRate
    }

    public override func resignFirstResponder() -> Bool {
        releaseHeldKeys()
        return super.resignFirstResponder()
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = forward(presses, down: true)
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = forward(presses, down: false)
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = forward(presses, down: false)
        if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
    }

    /// Sends keyboard presses to the Mac; returns the presses that weren't keys.
    private func forward(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key else {
                unhandled.insert(press)
                continue
            }
            let usage = UInt16(truncatingIfNeeded: key.keyCode.rawValue)
            if down {
                heldKeys.insert(usage)
            } else {
                heldKeys.remove(usage)
            }
            onInput(.key(usage: usage, down: down))
        }
        return unhandled
    }

    /// Never leave a key (e.g. ⌘) stuck down on the Mac.
    private func releaseHeldKeys() {
        for usage in heldKeys { onInput(.key(usage: usage, down: false)) }
        heldKeys.removeAll()
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let now = CACurrentMediaTime()
        if touch.type == .pencil { lastPencilActivity = now }
        if touch.type == .direct {
            // Palm rejection: a palm is a wide touch, and while writing or
            // drawing with the Pencil every finger touch is the resting hand.
            if touch.majorRadius > Self.palmRadius { return false }
            if hoverIsPencil || now - lastPencilActivity < Self.palmRejectionWindow { return false }
        }
        if gestureRecognizer === pressRecognizer {
            pressIsImmediate = touch.type == .pencil || touch.type == .indirectPointer
            pressIsPencil = touch.type == .pencil
            pencilTouch = touch.type == .pencil ? touch : nil
        }
        return true
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        VideoGeometry.normalize(point, videoSize: videoSize() ?? bounds.size, in: bounds)
    }

    private func sendPointer(_ phase: PointerPhase, _ button: PointerButton, at point: CGPoint) {
        let p = normalized(point)
        moveLocalCursor(to: point)
        onInput(.pointer(phase: phase, button: button, x: Double(p.x), y: Double(p.y)))
    }

    /// Left-button events of the one-finger/Pencil press: pen-tablet events
    /// (pressure, tilt) for the Pencil, plain mouse events otherwise.
    private func sendPress(_ phase: PointerPhase, at point: CGPoint) {
        guard pressIsPencil, let touch = pencilTouch else {
            sendPointer(phase, .left, at: point)
            return
        }
        lastPencilActivity = CACurrentMediaTime()
        penInProximity = true
        let p = normalized(point)
        moveLocalCursor(to: point)
        let lifting = phase == .ended || phase == .cancelled
        let pressure: Double = touch.maximumPossibleForce > 0
            ? min(1, Double(touch.force / (touch.maximumPossibleForce * 0.75)))
            : 0.5
        let tilt = max(0, 1 - Double(touch.altitudeAngle / (.pi / 2)))  // 0 upright … 1 flat
        let azimuth = Double(touch.azimuthAngle(in: self))
        onInput(.pen(phase: phase, x: Double(p.x), y: Double(p.y), pressure: lifting ? 0 : pressure,
                     tiltX: cos(azimuth) * tilt, tiltY: sin(azimuth) * tilt))
    }

    private func setPenProximity(_ near: Bool) {
        guard near != penInProximity else { return }
        penInProximity = near
        onInput(.penProximity(entering: near))
    }

    // MARK: One finger / Pencil

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        if pressIsImmediate { lastPencilPoint = point }
        switch recognizer.state {
        case .began:
            sendModifiers(of: recognizer)
            if pressIsImmediate {
                pressDown(at: point)  // Pencil / trackpad click: never the start of a scroll
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
            if buttonDown { sendPress(.moved, at: point) }
        case .ended:
            if let start = pendingPress { pressDown(at: start) }  // quick tap
            if buttonDown {
                buttonDown = false
                sendPress(.ended, at: point)
            }
            if pressIsPencil { pencilDidClick(at: point) }
        case .cancelled, .failed:
            cancelPendingPress()
            if buttonDown {
                buttonDown = false
                sendPress(.cancelled, at: point)
            }
        default:
            break
        }
    }

    private func pressDown(at point: CGPoint) {
        cancelPendingPress()
        guard !buttonDown else { return }
        buttonDown = true
        sendPress(.began, at: point)
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
                sendPress(.cancelled, at: recognizer.location(in: self))
            }
            lastScrollTranslation = .zero
            sendModifiers(of: recognizer)
            onInput(.scroll(phase: .began, x: Double(location.x), y: Double(location.y), deltaX: 0, deltaY: 0))
        case .changed:
            let dx = (translation.x - lastScrollTranslation.x) * scale
            let dy = (translation.y - lastScrollTranslation.y) * scale
            lastScrollTranslation = translation
            guard !pinching else { return }
            onInput(.scroll(phase: .moved, x: Double(location.x), y: Double(location.y),
                            deltaX: Double(dx), deltaY: Double(dy)))
        case .ended, .cancelled, .failed:
            // Lift-off velocity, so the Mac can keep the page gliding.
            let velocity = pinching ? .zero : recognizer.velocity(in: self)
            onInput(.scroll(phase: .ended, x: Double(location.x), y: Double(location.y),
                            deltaX: Double(velocity.x * scale), deltaY: Double(velocity.y * scale)))
        default:
            break
        }
    }

    @objc private func handleRightClick(_ recognizer: UITapGestureRecognizer) {
        cancelPendingPress()
        sendModifiers(of: recognizer)
        let p = normalized(recognizer.location(in: self))
        onInput(.rightClick(x: Double(p.x), y: Double(p.y)))
    }

    @objc private func handleToggle(_ recognizer: UITapGestureRecognizer) {
        onToggleShortcutBar()
    }

    @objc private func handleHoldToggle(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        cancelPendingPress()
        onToggleControls()
    }

    /// Three-finger swipe → the Mac's own Mission Control / Spaces shortcuts.
    @objc private func handleThreeFingerSwipe(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            cancelPendingPress()
            if buttonDown {
                buttonDown = false
                sendPress(.cancelled, at: recognizer.location(in: self))
            }
        case .ended:
            let t = recognizer.translation(in: self)
            guard max(abs(t.x), abs(t.y)) > 60 else { return }
            let arrow: UInt16
            if abs(t.x) > abs(t.y) {
                arrow = t.x < 0 ? 0x4F : 0x50   // fingers left → next Desktop (⌃→), right → previous (⌃←)
            } else {
                arrow = t.y < 0 ? 0x52 : 0x51   // up → Mission Control (⌃↑), down → App Exposé (⌃↓)
            }
            sendShortcut(control: true, key: arrow)
        default:
            break
        }
    }

    /// Presses ⌃ + key on the Mac (HID usages: 0xE0 = Left Control).
    private func sendShortcut(control: Bool, key usage: UInt16) {
        if control { onInput(.key(usage: 0xE0, down: true)) }
        onInput(.key(usage: usage, down: true))
        onInput(.key(usage: usage, down: false))
        if control { onInput(.key(usage: 0xE0, down: false)) }
    }

    /// Pinch (fingers or trackpad) → one ⌘= / ⌘− per ~18 % of scale change.
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let p = normalized(recognizer.location(in: self))
        switch recognizer.state {
        case .began:
            lastZoomStepScale = 1
            pinching = false
            sendModifiers(of: recognizer)
        case .changed:
            let scale = recognizer.scale
            if abs(log(scale)) > 0.08 { pinching = true }
            while scale / lastZoomStepScale > Self.zoomStep {
                lastZoomStepScale *= Self.zoomStep
                onInput(.zoom(zoomIn: true, x: Double(p.x), y: Double(p.y)))
            }
            while lastZoomStepScale / scale > Self.zoomStep {
                lastZoomStepScale /= Self.zoomStep
                onInput(.zoom(zoomIn: false, x: Double(p.x), y: Double(p.y)))
            }
        default:
            pinching = false
        }
    }

    // MARK: Hover (Pencil hover, trackpad, mouse)

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let point = recognizer.location(in: self)
            lastPencilPoint = point
            lastHoverPoint = point
            if #available(iOS 16.1, *) {
                // Only the Pencil hovers above the glass; a trackpad pointer has no height.
                if recognizer.zOffset > 0 { hoverIsPencil = true }
            }
            if hoverIsPencil {
                lastPencilActivity = CACurrentMediaTime()
                setPenProximity(true)
            }
            if hoverIsPencil {
                pencilNudgeWork?.cancel()  // Pencil still nearby; wait until it leaves
                pencilNudgeWork = nil
            }
            if !buttonDown { sendPointer(.moved, .none, at: point) }
        case .ended, .cancelled:
            if hoverIsPencil, pencilClicked, !buttonDown, let point = lastHoverPoint {
                nudgeOffScreenEdge(from: point)
            }
            if hoverIsPencil, !buttonDown { setPenProximity(false) }
            hoverIsPencil = false
            pencilClicked = false
            lastHoverPoint = nil
        default:
            break
        }
    }

    /// After a Pencil click, once the Pencil is lifted away, the pointer
    /// leaves the edge. Waits for the hover to end; if this iPad reports no
    /// hover at all, does it shortly after the click.
    private func pencilDidClick(at point: CGPoint) {
        pencilClicked = true
        lastHoverPoint = point
        pencilNudgeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pencilClicked, !self.buttonDown else { return }
            self.pencilClicked = false
            self.nudgeOffScreenEdge(from: point)
            self.setPenProximity(false)
        }
        pencilNudgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// After a Pencil click, once the Pencil is lifted away, park the pointer
    /// out of the way: off the edge it was on (so an auto-hiding Dock or menu
    /// bar closes), otherwise against the right edge of the screen so it
    /// doesn't sit on top of what you just tapped.
    private func nudgeOffScreenEdge(from point: CGPoint) {
        let p = normalized(point)
        var target = CGPoint(x: 0.995, y: p.y)
        if p.y > 0.92 { target = CGPoint(x: p.x, y: 0.75) }
        if p.y < 0.04 { target = CGPoint(x: p.x, y: 0.25) }
        if p.x > 0.96 { target = CGPoint(x: 0.75, y: p.y) }
        if p.x < 0.04 { target = CGPoint(x: 0.25, y: p.y) }
        onInput(.pointer(phase: .moved, button: .none, x: Double(target.x), y: Double(target.y)))
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
    /// A Mac display shows its own pointer over the window, so the Host never
    /// leaves the pointer out of the video for it; kept for a shared `configure`.
    var drawsCursor: () -> Bool = { false }
    var extraModifierFlags: () -> UInt32 = { 0 }
    func remoteCursorMoved(to normalizedPoint: CGPoint, visible: Bool) {}
    /// Unused on macOS (Mac displays don't drop their refresh rate the way
    /// ProMotion does); present so `configure` is the same on both platforms.
    var streamFrameRate: () -> Int? = { nil }
    var onInput: (InputEvent) -> Void = { _ in }
    var onToggleControls: () -> Void = {}
    var onToggleShortcutBar: () -> Void = {}

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

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendModifiers(of: event)
        pointer(.began, .left, event)
    }

    private func sendModifiers(of event: NSEvent) {
        let flags = UInt32(truncatingIfNeeded: event.modifierFlags.rawValue) & 0x1E_0000  // ⇧ ⌃ ⌥ ⌘
        onInput(.modifierState(flags: flags | extraModifierFlags()))
    }
    public override func mouseDragged(with event: NSEvent) { pointer(.moved, .left, event) }
    public override func mouseUp(with event: NSEvent) { pointer(.ended, .left, event) }
    public override func mouseMoved(with event: NSEvent) { pointer(.moved, .none, event) }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    public override func keyDown(with event: NSEvent) {
        // The Host repeats held keys itself.
        if !event.isARepeat { onInput(.macKey(code: event.keyCode, down: true)) }
    }

    public override func keyUp(with event: NSEvent) {
        onInput(.macKey(code: event.keyCode, down: false))
    }

    public override func flagsChanged(with event: NSEvent) {
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 0x38, 0x3C: flag = .shift
        case 0x3B, 0x3E: flag = .control
        case 0x3A, 0x3D: flag = .option
        case 0x37, 0x36: flag = .command
        case 0x39: flag = .capsLock
        default: return
        }
        onInput(.macKey(code: event.keyCode, down: event.modifierFlags.contains(flag)))
    }

    public override func rightMouseDown(with event: NSEvent) {
        sendModifiers(of: event)
        let p = normalized(event)
        onInput(.rightClick(x: Double(p.x), y: Double(p.y)))
    }

    public override func scrollWheel(with event: NSEvent) {
        let p = normalized(event)
        let scale = Double(VideoGeometry.pointScale(videoSize: videoSize() ?? bounds.size, in: bounds)
                           / max(window?.backingScaleFactor ?? 2, 1))
        let phase: PointerPhase = event.phase == .began ? .began : (event.phase == .ended ? .ended : .moved)
        if phase == .began { sendModifiers(of: event) }
        onInput(.scroll(phase: phase, x: Double(p.x), y: Double(p.y),
                        deltaX: Double(event.scrollingDeltaX) * scale,
                        deltaY: Double(event.scrollingDeltaY) * scale))
    }
}
#endif
