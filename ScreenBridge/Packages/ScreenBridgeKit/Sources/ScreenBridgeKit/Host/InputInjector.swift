#if os(macOS)
import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

/// Turns input from the Display into real mouse events on this Mac.
///
/// Posting events needs the Accessibility permission (System Settings →
/// Privacy & Security → Accessibility). Without it macOS silently drops them.
final class InputInjector {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (first time) that leads to the setting.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private let source = CGEventSource(stateID: .hidSystemState)
    private var leftButtonDown = false
    private var lastPoint = CGPoint.zero
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var clickCount: Int64 = 1

    /// Must be called from one serial queue.
    func handle(_ event: InputEvent, on displayID: CGDirectDisplayID) {
        let bounds = CGDisplayBounds(displayID)
        func place(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: bounds.minX + CGFloat(min(max(x, 0), 1)) * (bounds.width - 1),
                    y: bounds.minY + CGFloat(min(max(y, 0), 1)) * (bounds.height - 1))
        }

        switch event {
        case .pointer(let phase, let button, let x, let y):
            let point = place(x, y)
            lastPoint = point
            switch (phase, button) {
            case (.began, .left):
                updateClickCount(at: point)
                leftButtonDown = true
                post(.leftMouseDown, at: point, button: .left, clickState: clickCount)
            case (.moved, .left):
                post(leftButtonDown ? .leftMouseDragged : .mouseMoved, at: point, button: .left)
            case (.ended, .left), (.cancelled, .left):
                if leftButtonDown {
                    leftButtonDown = false
                    post(.leftMouseUp, at: point, button: .left, clickState: clickCount)
                }
            case (_, .none):
                post(leftButtonDown ? .leftMouseDragged : .mouseMoved, at: point, button: .left)
            }

        case .rightClick(let x, let y):
            let point = place(x, y)
            post(.rightMouseDown, at: point, button: .right, clickState: 1)
            post(.rightMouseUp, at: point, button: .right, clickState: 1)

        case .scroll(let phase, let x, let y, let deltaX, let deltaY):
            if phase == .began {
                // Scroll whatever is under the fingers.
                post(.mouseMoved, at: place(x, y), button: .left)
            }
            guard deltaX != 0 || deltaY != 0,
                  let scroll = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                       wheel1: Int32(deltaY.rounded()), wheel2: Int32(deltaX.rounded()),
                                       wheel3: 0) else { return }
            scroll.post(tap: .cghidEventTap)
        }
    }

    private func updateClickCount(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let near = hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 8
        clickCount = (now - lastClickTime < NSEvent.doubleClickInterval && near) ? min(clickCount + 1, 3) : 1
        lastClickTime = now
        lastClickPoint = point
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int64? = nil) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        if let clickState {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        event.post(tap: .cghidEventTap)
    }
}
#endif
