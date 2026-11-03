import Foundation
import CoreGraphics

public enum PointerPhase: String, Codable, Sendable {
    case began, moved, ended, cancelled
}

public enum PointerButton: String, Codable, Sendable {
    /// Hover (Apple Pencil hover, trackpad/mouse on iPad, mouse on a Mac).
    case none
    case left
}

/// Display → Host input, sent sealed as `sealedInput` (JSON). Positions are
/// normalized to the video picture: (0,0) top-left, (1,1) bottom-right, so
/// they don't depend on either screen's size or the letterboxing.
public enum InputEvent: Codable, Sendable, Equatable {
    case pointer(phase: PointerPhase, button: PointerButton, x: Double, y: Double)
    case rightClick(x: Double, y: Double)
    /// Deltas in points; positive `deltaY` = fingers moved down (content
    /// follows the fingers, like on an iPad).
    case scroll(phase: PointerPhase, x: Double, y: Double, deltaX: Double, deltaY: Double)
    /// A physical key on an iPad keyboard (Smart Keyboard Folio, Magic
    /// Keyboard…), as a USB HID usage code. Modifier keys are sent too.
    case key(usage: UInt16, down: Bool)
    /// A key on a Mac acting as the display, as a macOS virtual key code.
    case macKey(code: UInt16, down: Bool)
    /// One step of a pinch: zoom in/out in the app under the pointer
    /// (sent to the Mac as ⌘= / ⌘−, which nearly every Mac app supports).
    case zoom(zoomIn: Bool, x: Double, y: Double)
    /// Which of ⇧ ⌃ ⌥ ⌘ are physically held right now (bits as in
    /// UIKeyModifierFlags / CGEventFlags, which share values). Sent before
    /// clicks and scrolls so the Mac can let go of a modifier whose key-up
    /// iPadOS swallowed (a stuck ⌃ turns every click into a right-click).
    case modifierState(flags: UInt32)
}

/// Where the (aspect-fit) video sits inside a view, and conversions to the
/// normalized coordinates used on the wire.
public enum VideoGeometry {
    public static func videoRect(videoSize: CGSize, in bounds: CGRect) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Normalized position of `point` (top-left origin) in the video, clamped to 0…1.
    public static func normalize(_ point: CGPoint, videoSize: CGSize, in bounds: CGRect) -> CGPoint {
        let rect = videoRect(videoSize: videoSize, in: bounds)
        let x = (point.x - rect.minX) / max(rect.width, 1)
        let y = (point.y - rect.minY) / max(rect.height, 1)
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    /// How many video pixels one view point covers (to scale scroll deltas).
    public static func pointScale(videoSize: CGSize, in bounds: CGRect) -> CGFloat {
        let rect = videoRect(videoSize: videoSize, in: bounds)
        guard rect.width > 0 else { return 1 }
        return videoSize.width / rect.width
    }
}
