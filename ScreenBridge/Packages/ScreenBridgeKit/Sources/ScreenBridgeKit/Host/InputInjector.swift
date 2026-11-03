#if os(macOS)
import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

/// Turns input from the Display into real mouse and keyboard events on
/// this Mac.
///
/// Posting events needs the Accessibility permission (System Settings →
/// Privacy & Security → Accessibility). Without it macOS silently drops them.
///
/// Shortcut layer for keyboards that lack keys or whose shortcuts iPadOS
/// keeps for itself — hold Control + Option and press:
/// - Tab → ⌘Tab (app switcher) · Space → ⌘Space (Spotlight)
/// - ` → Esc · 1…0, -, = → F1…F12
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

    /// All injection happens here, in order (key repeat timers too).
    private let queue = DispatchQueue(label: "app.screenbridge.input", qos: .userInteractive)
    private let source = CGEventSource(stateID: .hidSystemState)

    // Pointer state
    private var leftButtonDown = false
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var clickCount: Int64 = 1

    // Keyboard state
    private var heldModifiers: [UInt16: KeyMap.Modifier] = [:]   // key code → modifier
    private var capsLockOn = false
    /// Keys currently down → what was actually posted for them (after the shortcut layer).
    private var pressedKeys: [UInt16: (code: UInt16, flags: CGEventFlags)] = [:]
    private var repeatTimer: DispatchSourceTimer?

    private var modifierFlags: CGEventFlags {
        var flags = CGEventFlags()
        for modifier in heldModifiers.values { flags.insert(modifier.flag) }
        if capsLockOn { flags.insert(.maskAlphaShift) }
        return flags
    }

    func submit(_ event: InputEvent, on displayID: CGDirectDisplayID) {
        queue.async { self.handle(event, on: displayID) }
    }

    /// Lets go of every key and button (session ended mid-press), so the Mac
    /// isn't left with a stuck ⌘ or a held mouse button.
    func releaseAll() {
        queue.async {
            self.stopRepeat()
            for (_, posted) in self.pressedKeys {
                self.postKey(posted.code, down: false, flags: [])
            }
            self.pressedKeys.removeAll()
            let modifiers = Array(self.heldModifiers.keys)
            self.heldModifiers.removeAll()
            for code in modifiers { self.postModifierChange(code) }
            if self.leftButtonDown, let location = CGEvent(source: nil)?.location {
                self.leftButtonDown = false
                self.postMouse(.leftMouseUp, at: location, button: .left)
            }
        }
    }

    // MARK: - Dispatch

    private func handle(_ event: InputEvent, on displayID: CGDirectDisplayID) {
        let bounds = CGDisplayBounds(displayID)
        func place(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: bounds.minX + CGFloat(min(max(x, 0), 1)) * (bounds.width - 1),
                    y: bounds.minY + CGFloat(min(max(y, 0), 1)) * (bounds.height - 1))
        }

        switch event {
        case .pointer(let phase, let button, let x, let y):
            let point = place(x, y)
            switch (phase, button) {
            case (.began, .left):
                updateClickCount(at: point)
                leftButtonDown = true
                postMouse(.leftMouseDown, at: point, button: .left, clickState: clickCount)
            case (.moved, .left):
                postMouse(leftButtonDown ? .leftMouseDragged : .mouseMoved, at: point, button: .left)
            case (.ended, .left), (.cancelled, .left):
                if leftButtonDown {
                    leftButtonDown = false
                    postMouse(.leftMouseUp, at: point, button: .left, clickState: clickCount)
                }
            case (_, .none):
                postMouse(leftButtonDown ? .leftMouseDragged : .mouseMoved, at: point, button: .left)
            }

        case .rightClick(let x, let y):
            let point = place(x, y)
            postMouse(.rightMouseDown, at: point, button: .right, clickState: 1)
            postMouse(.rightMouseUp, at: point, button: .right, clickState: 1)

        case .scroll(let phase, let x, let y, let deltaX, let deltaY):
            if phase == .began {
                // Scroll whatever is under the fingers.
                postMouse(.mouseMoved, at: place(x, y), button: .left)
            }
            guard deltaX != 0 || deltaY != 0,
                  let scroll = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                       wheel1: Int32(deltaY.rounded()), wheel2: Int32(deltaX.rounded()),
                                       wheel3: 0) else { return }
            scroll.flags = modifierFlags
            scroll.post(tap: .cghidEventTap)

        case .key(let usage, let down):
            guard let code = KeyMap.macKeyCode(forHIDUsage: usage) else { return }
            handleKey(code, down: down)

        case .macKey(let code, let down):
            handleKey(code, down: down)

        case .modifierState(let raw):
            reconcileModifiers(with: CGEventFlags(rawValue: UInt64(raw)))

        case .zoom(let zoomIn, let x, let y):
            postMouse(.mouseMoved, at: place(x, y), button: .left)  // zoom what's under the fingers
            let key = zoomIn ? KeyMap.equal : KeyMap.minus
            postKey(key, down: true, flags: .maskCommand)
            postKey(key, down: false, flags: .maskCommand)
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ code: UInt16, down: Bool) {
        if let modifier = KeyMap.modifier(forMacKeyCode: code) {
            if modifier == .capsLock {
                if down { capsLockOn.toggle() }
            } else if down {
                heldModifiers[code] = modifier
            } else {
                heldModifiers[code] = nil
            }
            stopRepeat()
            postModifierChange(code)
            return
        }

        if down {
            let target = shortcutLayer(code) ?? (code: code, flags: modifierFlags)
            pressedKeys[code] = target
            postKey(target.code, down: true, flags: target.flags)
            startRepeat(target)
        } else {
            let target = pressedKeys.removeValue(forKey: code) ?? (code: code, flags: modifierFlags)
            stopRepeat()
            postKey(target.code, down: false, flags: target.flags)
        }
    }

    /// Makes our idea of held modifiers match what the Display reports.
    private func reconcileModifiers(with reported: CGEventFlags) {
        let modifiers: [(KeyMap.Modifier, UInt16)] = [(.shift, 0x38), (.control, 0x3B), (.option, 0x3A), (.command, 0x37)]
        for (modifier, code) in modifiers {
            let held = heldModifiers.values.contains(modifier)
            let wanted = reported.contains(modifier.flag)
            if held, !wanted {
                heldModifiers = heldModifiers.filter { $0.value != modifier }
                postModifierChange(code)
            } else if !held, wanted {
                heldModifiers[code] = modifier
                postModifierChange(code)
            }
        }
    }

    /// Control + Option + key → a key/shortcut the keyboard or iPadOS can't send.
    private func shortcutLayer(_ code: UInt16) -> (code: UInt16, flags: CGEventFlags)? {
        let flags = modifierFlags
        guard flags.contains(.maskControl), flags.contains(.maskAlternate),
              !flags.contains(.maskCommand) else { return nil }
        if code == KeyMap.tab { return (code: KeyMap.tab, flags: .maskCommand) }
        if code == KeyMap.space { return (code: KeyMap.space, flags: .maskCommand) }
        if code == KeyMap.grave { return (code: KeyMap.escape, flags: []) }
        if let index = KeyMap.numberRow.firstIndex(of: code) {
            return (code: KeyMap.functionKeys[index], flags: [])
        }
        return nil
    }

    /// Synthetic key-downs don't auto-repeat, so repeat like a real keyboard
    /// while the key is held, using the Mac's own repeat settings.
    private func startRepeat(_ target: (code: UInt16, flags: CGEventFlags)) {
        stopRepeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let delay = max(NSEvent.keyRepeatDelay, 0.15)
        let interval = max(NSEvent.keyRepeatInterval, 0.015)
        timer.schedule(deadline: .now() + delay, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.postKey(target.code, down: true, flags: target.flags, isRepeat: true)
        }
        repeatTimer = timer
        timer.resume()
    }

    private func stopRepeat() {
        repeatTimer?.cancel()
        repeatTimer = nil
    }

    private func postKey(_ code: UInt16, down: Bool, flags: CGEventFlags, isRepeat: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        event.flags = flags
        if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cghidEventTap)
    }

    private func postModifierChange(_ code: UInt16) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: true) else { return }
        event.type = .flagsChanged
        event.flags = modifierFlags
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Mouse

    private func updateClickCount(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let near = hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 8
        clickCount = (now - lastClickTime < NSEvent.doubleClickInterval && near) ? min(clickCount + 1, 3) : 1
        lastClickTime = now
        lastClickPoint = point
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int64? = nil) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        if let clickState {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        event.flags = modifierFlags  // ⇧-click, ⌘-click…
        event.post(tap: .cghidEventTap)
    }
}
#endif
