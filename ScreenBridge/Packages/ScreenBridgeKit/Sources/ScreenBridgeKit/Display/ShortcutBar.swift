import SwiftUI

/// A strip of keys beside the Mac's screen (like Sidecar's sidebar): hold
/// or tap ⌘ ⌥ ⌃ ⇧ with one hand while clicking or drawing with the other,
/// plus one-tap Esc, Undo, Redo, Cut, Copy, Paste and Save.
///
/// Modifier keys: **tap** to lock (stays down until tapped again),
/// **press and hold** to keep it down only while held.
public struct ShortcutBar: View {
    @ObservedObject var controller: DisplayStreamController

    public init(controller: DisplayStreamController) {
        self.controller = controller
    }

    // HID usages
    private static let command: UInt16 = 0xE3
    private static let option: UInt16 = 0xE2
    private static let control: UInt16 = 0xE0
    private static let shift: UInt16 = 0xE1

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ModifierKey(symbol: "command", usage: Self.command, controller: controller)
                ModifierKey(symbol: "option", usage: Self.option, controller: controller)
                ModifierKey(symbol: "control", usage: Self.control, controller: controller)
                ModifierKey(symbol: "shift", usage: Self.shift, controller: controller)

                Divider().padding(.vertical, 4)

                ShortcutKey(symbol: "escape", label: "Esc") { controller.press(0x29) }
                ShortcutKey(symbol: "arrow.uturn.backward", label: "Undo") {
                    controller.press(0x1D, with: [Self.command])                    // ⌘Z
                }
                ShortcutKey(symbol: "arrow.uturn.forward", label: "Redo") {
                    controller.press(0x1D, with: [Self.command, Self.shift])        // ⇧⌘Z
                }
                ShortcutKey(symbol: "scissors", label: "Cut") { controller.press(0x1B, with: [Self.command]) }
                ShortcutKey(symbol: "doc.on.doc", label: "Copy") { controller.press(0x06, with: [Self.command]) }
                ShortcutKey(symbol: "doc.on.clipboard", label: "Paste") { controller.press(0x19, with: [Self.command]) }
                ShortcutKey(symbol: "square.and.arrow.down", label: "Save") { controller.press(0x16, with: [Self.command]) }

                Divider().padding(.vertical, 4)

                // The Smart Keyboard Folio has no function row; these are the
                // Mac's brightness / volume / playback keys.
                ShortcutKey(symbol: "sun.min", label: "Dimmer") { controller.pressMediaKey(MediaKey.brightnessDown) }
                ShortcutKey(symbol: "sun.max", label: "Brighter") { controller.pressMediaKey(MediaKey.brightnessUp) }
                ShortcutKey(symbol: "speaker.wave.1", label: "Vol −") { controller.pressMediaKey(MediaKey.volumeDown) }
                ShortcutKey(symbol: "speaker.wave.3", label: "Vol +") { controller.pressMediaKey(MediaKey.volumeUp) }
                ShortcutKey(symbol: "speaker.slash", label: "Mute") { controller.pressMediaKey(MediaKey.mute) }
                ShortcutKey(symbol: "playpause", label: "Play") { controller.pressMediaKey(MediaKey.playPause) }
            }
            .padding(.vertical, 12)
        }
        .frame(width: 60)
        .background(.ultraThinMaterial)
    }
}

/// Tap = lock / unlock. Press and hold = down only while held.
private struct ModifierKey: View {
    let symbol: String
    let usage: UInt16
    @ObservedObject var controller: DisplayStreamController
    @State private var pressStart: Date?
    @State private var wasLatched = false

    private var isDown: Bool { controller.latchedModifiers.contains(usage) }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 46, height: 46)
            .foregroundStyle(isDown ? Color.white : Color.primary)
            .background(isDown ? Color.accentColor : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard pressStart == nil else { return }
                        pressStart = Date()
                        wasLatched = isDown
                        if !wasLatched { controller.setModifier(usage, down: true) }
                    }
                    .onEnded { _ in
                        let held = Date().timeIntervalSince(pressStart ?? Date())
                        pressStart = nil
                        if held > 0.35 || wasLatched {
                            controller.setModifier(usage, down: false)  // released after a hold, or unlocked
                        }
                        // A quick tap on an unlocked key leaves it locked down.
                    }
            )
            .accessibilityLabel(Text(symbol))
    }
}

private struct ShortcutKey: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(label).font(.system(size: 9))
            }
            .frame(width: 46, height: 46)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
