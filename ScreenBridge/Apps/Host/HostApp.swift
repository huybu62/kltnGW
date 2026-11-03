import SwiftUI
import ScreenBridgeKit

/// Host = the Mac whose screen is shared. Lives in the menu bar (LSUIElement).
@main
struct ScreenBridgeHostApp: App {
    @NSApplicationDelegateAdaptor(HostAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            DiscoveryDebugView(coordinator: appDelegate.coordinator)
                .frame(width: 380)
            Divider()
            Button("Quit ScreenBridge") { NSApplication.shared.terminate(nil) }
                .padding(.bottom, 8)
        } label: {
            MenuBarIcon(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the coordinator so discovery starts at launch, not when the menu
/// is first opened.
@MainActor
final class HostAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    // lazy: built on first (main-actor) access rather than in NSObject.init.
    private(set) lazy var coordinator = ConnectionCoordinator(role: .host)

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var coordinator: ConnectionCoordinator

    var body: some View {
        Image(systemName: coordinator.phase == .connected
              ? "rectangle.connected.to.line.below"
              : "rectangle.on.rectangle")
    }
}
