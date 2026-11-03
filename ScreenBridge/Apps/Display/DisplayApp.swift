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

    var body: some View {
        if coordinator.phase == .connected && stream.isReceiving {
            ZStack(alignment: .top) {
                VideoSurfaceView(controller: stream)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showControls.toggle() }
                if showControls {
                    controls
                }
            }
            .background(Color.black)
            #if os(iOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
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
            Button("Hide") { showControls = false }
            Button("Disconnect", role: .destructive) { coordinator.disconnect() }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}
