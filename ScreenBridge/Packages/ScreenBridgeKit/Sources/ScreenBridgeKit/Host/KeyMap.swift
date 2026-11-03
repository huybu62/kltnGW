#if os(macOS)
import CoreGraphics

/// USB HID keyboard usages (what iPadOS reports) → macOS virtual key codes
/// (what CGEvent posts). Both describe the *physical* key position, so the
/// Mac's own input source (US, Vietnamese Telex/VNI…) decides the character.
enum KeyMap {
    static func macKeyCode(forHIDUsage usage: UInt16) -> UInt16? {
        table[usage]
    }

    enum Modifier {
        case shift, control, option, command, capsLock

        var flag: CGEventFlags {
            switch self {
            case .shift: return .maskShift
            case .control: return .maskControl
            case .option: return .maskAlternate
            case .command: return .maskCommand
            case .capsLock: return .maskAlphaShift
            }
        }
    }

    /// Modifier keys by macOS key code.
    static func modifier(forMacKeyCode code: UInt16) -> Modifier? {
        switch code {
        case 0x38, 0x3C: return .shift
        case 0x3B, 0x3E: return .control
        case 0x3A, 0x3D: return .option
        case 0x37, 0x36: return .command
        case 0x39: return .capsLock
        default: return nil
        }
    }

    // macOS key codes used by the shortcut layer.
    static let tab: UInt16 = 0x30
    static let space: UInt16 = 0x31
    static let escape: UInt16 = 0x35
    static let grave: UInt16 = 0x32
    /// F1…F12 in order.
    static let functionKeys: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
    /// 1 2 3 4 5 6 7 8 9 0 - = (the keys that become F1…F12 in the shortcut layer).
    static let numberRow: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18]

    private static let table: [UInt16: UInt16] = {
        var map: [UInt16: UInt16] = [:]
        // Letters a…z = HID 0x04…0x1D
        let letters: [UInt16] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
        for (index, code) in letters.enumerated() { map[UInt16(0x04 + index)] = code }
        // 1…9, 0 = HID 0x1E…0x27
        let digits: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for (index, code) in digits.enumerated() { map[UInt16(0x1E + index)] = code }
        // F1…F12 = HID 0x3A…0x45
        for (index, code) in functionKeys.enumerated() { map[UInt16(0x3A + index)] = code }

        let others: [UInt16: UInt16] = [
            0x28: 0x24,  // Return
            0x29: 0x35,  // Escape
            0x2A: 0x33,  // Delete (backspace)
            0x2B: 0x30,  // Tab
            0x2C: 0x31,  // Space
            0x2D: 0x1B,  // -
            0x2E: 0x18,  // =
            0x2F: 0x21,  // [
            0x30: 0x1E,  // ]
            0x31: 0x2A,  // \
            0x32: 0x2A,  // non-US #
            0x33: 0x29,  // ;
            0x34: 0x27,  // '
            0x35: 0x32,  // `
            0x36: 0x2B,  // ,
            0x37: 0x2F,  // .
            0x38: 0x2C,  // /
            0x39: 0x39,  // Caps Lock
            0x4A: 0x73,  // Home
            0x4B: 0x74,  // Page Up
            0x4C: 0x75,  // Forward Delete
            0x4D: 0x77,  // End
            0x4E: 0x79,  // Page Down
            0x4F: 0x7C,  // →
            0x50: 0x7B,  // ←
            0x51: 0x7D,  // ↓
            0x52: 0x7E,  // ↑
            0x64: 0x0A,  // ISO § / <
            0xE0: 0x3B,  // Left Control
            0xE1: 0x38,  // Left Shift
            0xE2: 0x3A,  // Left Option
            0xE3: 0x37,  // Left Command
            0xE4: 0x3E,  // Right Control
            0xE5: 0x3C,  // Right Shift
            0xE6: 0x3D,  // Right Option
            0xE7: 0x36,  // Right Command
        ]
        map.merge(others) { _, new in new }
        return map
    }()
}
#endif
