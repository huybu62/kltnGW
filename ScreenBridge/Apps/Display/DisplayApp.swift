import SwiftUI
import ScreenBridgeKit
#if os(iOS)
import UIKit
#endif

/// Display = the Mac or iPad that shows the Host's screen. Same code on both
/// platforms; the rendering surface arrives in Phase 2.
@main
struct ScreenBridgeDisplayApp: App {
    @StateObject private var coordinator = ConnectionCoordinator(role: .display)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ScrollView {
                DiscoveryDebugView(coordinator: coordinator)
                    .frame(maxWidth: 560)
            }
            .onAppear { coordinator.start() }
            .onChange(of: scenePhase) { phase in
                #if os(iOS)
                // iPadOS tears listeners down in the background; re-advertise.
                if phase == .active { coordinator.appDidBecomeActive() }
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
