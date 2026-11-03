import SwiftUI
import ScreenBridgeKit
#if os(iOS)
import UIKit
#endif

/// Display = the Mac or iPad that shows the Host's screen.
@main
struct ScreenBridgeDisplayApp: App {
    @StateObject private var coordinator = ConnectionCoordinator(role: .display)
    @StateObject private var stream = DisplayStreamController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DisplayRootView(coordinator: coordinator, stream: stream)
                .onAppear {
                    coordinator.mediaSink = stream
                    coordinator.start()
                }
                .onChange(of: scenePhase) { phase in
                    #if os(iOS)
                    // iPadOS tears listeners and decoders down in the background.
                    if phase == .active {
                        coordinator.appDidBecomeActive()
                        stream.refresh()
                    }
                    #endif
                }
                #if os(iOS)
                // A display must not dim/lock mid-session.
                .onChange(of: coordinator.phase) { phase in
                    UIApplication.shared.isIdleTimerDisabled = (phase == .connected)
                }
                #endif
        }
    }
}

private struct DisplayRootView: View {
    @ObservedObject var coordinator: ConnectionCoordinator
    @ObservedObject var stream: DisplayStreamController
    @State private var showControls = false
    /// Shortcut bar beside the Mac screen (iPad), remembered between launches.
    @AppStorage("ScreenBridge.showShortcutBar") private var showShortcutBar = true

    var body: some View {
        if stream.isReceiving {
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    #if os(iOS)
                    if showShortcutBar {
                        ShortcutBar(controller: stream)
                            .ignoresSafeArea(edges: .vertical)
                    }
                    #endif
                    VideoSurfaceView(controller: stream,
                                     onToggleControls: { showControls.toggle() },
                                     onToggleShortcutBar: { showShortcutBar.toggle() })
                        .ignoresSafeArea()
                }
                if showControls {
                    controls
                }
                if stream.isReconnecting || coordinator.phase != .connected {
                    Label("Reconnecting…", systemImage: "arrow.triangle.2.circlepath")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 40)
                }
                #if os(macOS)
                // ⌘K shows/hides the overlay on a Mac display (no 3-finger tap there).
                Button("") { showControls.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                #endif
            }
            .background(Color.black)
            #if os(iOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            // Edge swipes (Home, Control Center, Notification Center) need a
            // second swipe, so a stray swipe while working doesn't leave the
            // Mac screen. Swipe up twice from the bottom to go Home.
            .defersSystemGestures(on: .all)
            #endif
        } else {
            ScrollView {
                DiscoveryDebugView(coordinator: coordinator)
                    .frame(maxWidth: 560)
                if coordinator.phase == .connected {
                    Label("Connected. Waiting for the Mac to start sharing…", systemImage: "hourglass")
                        .padding()
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Image(systemName: coordinator.activeLink?.systemImage ?? "network")
            Text(stream.stats?.summary ?? "…").font(.caption.monospaced())
            Spacer()
            #if os(iOS)
            Toggle("Shortcut bar", isOn: $showShortcutBar)
                .toggleStyle(.button)
            #endif
            Button("Hide") { showControls = false }
            Button("Disconnect", role: .destructive) { coordinator.disconnect() }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}
