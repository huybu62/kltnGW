#if os(macOS)
import Foundation
import AppKit
import CoreGraphics
import IOKit.pwr_mgt

/// "Use with the lid closed": macOS sleeps a MacBook when its lid closes
/// unless a *physical* external display is attached, and a virtual display
/// doesn't count. `pmset disablesleep` is the system switch that keeps the
/// Mac awake anyway (it's what tools like Amphetamine use). It needs an
/// administrator password and stays on until turned off.
enum LidClosedMode {
    /// Reads the current setting (`SleepDisabled` in `pmset -g`).
    static var isEnabled: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        for line in output.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
        }
        return false
    }

    /// Asks for the administrator password, then flips the setting. Main thread.
    /// Returns false if the user cancelled or it failed.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let command = "/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)"
        let source = "do shell script \"\(command)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}

/// Keeps the screens (including the virtual one) from sleeping or locking
/// for idleness while a Display is connected.
final class DisplaySleepAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    init(reason: String) {
        let status = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString, &assertionID)
        active = status == kIOReturnSuccess
    }

    deinit {
        if active { IOPMAssertionRelease(assertionID) }
    }
}

/// Mutes this Mac's own speakers while its sound plays on the Display.
enum SystemAudio {
    static var isMuted: Bool {
        run("output muted of (get volume settings)") == "true"
    }

    static func setMuted(_ muted: Bool) {
        _ = run("set volume \(muted ? "with" : "without") output muted")
    }

    /// Main thread.
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }
}

enum BuiltInDisplay {
    /// False when the MacBook's lid is closed (its screen leaves the active list).
    static var isActive: Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }
}
#endif
