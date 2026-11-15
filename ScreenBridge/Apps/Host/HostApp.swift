import SwiftUI
import ServiceManagement
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
            OpenAtLoginToggle()
                .padding(.horizontal)
                .padding(.top, 4)
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
        stream.shutdown()
    }
}

private struct HostMenuContent: View {
    @ObservedObject var coordinator: ConnectionCoordinator
    @ObservedObject var stream: HostStreamController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if stream.lidClosedModeEnabled && !coordinator.isConnected {
                lidModeReminder
            }
            DiscoveryDebugView(coordinator: coordinator)
            displayCountPicker
            if coordinator.isConnected || !stream.streams.isEmpty {
                HostStreamPanel(stream: stream)
            }
        }
    }

    /// How many iPads / Macs may extend this Mac at once.
    private var displayCountPicker: some View {
        Picker("Extra displays", selection: $coordinator.maxConnections) {
            Text("1").tag(1)
            Text("2").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 6)
        .help("With 2, a second iPad or Mac can connect while the first is in use.")
    }

    /// Reminder that the Mac won't sleep when closed, shown while not connected.
    private var lidModeReminder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("This Mac won't sleep when you close it", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("“Use with the lid closed” is still on. Turn it off before putting the MacBook in a bag.")
                .font(.caption)
            Button("Turn Off") { stream.setLidClosedMode(false) }
        }
        .padding()
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding([.horizontal, .top])
    }
}

/// Starts ScreenBridge automatically when you log in to this Mac.
private struct OpenAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Open at login", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                    enabled = SMAppService.mainApp.status == .enabled
                }))
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { enabled = SMAppService.mainApp.status == .enabled }
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var coordinator: ConnectionCoordinator

    var body: some View {
        Image(systemName: coordinator.isConnected
              ? "rectangle.connected.to.line.below"
              : "rectangle.on.rectangle")
    }
}
