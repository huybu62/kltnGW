import SwiftUI
import ScreenBridgeKit

/// Host = the Mac whose screen is shared. Lives in the menu bar (LSUIElement).
@main
struct ScreenBridgeHostApp: App {
    @NSApplicationDelegateAdaptor(HostAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            HostMenuContent(coordinator: appDelegate.coordinator, stream: appDelegate.stream)
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
    private(set) lazy var stream = HostStreamController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.mediaSink = stream
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}

private struct HostMenuContent: View {
    @ObservedObject var coordinator: ConnectionCoordinator
    let stream: HostStreamController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoveryDebugView(coordinator: coordinator)
            if coordinator.phase == .connected {
                HostStreamPanel(stream: stream)
            }
        }
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
