import SwiftUI
import Combine
import ScreenBridgeKit

/// The main screen on both apps: who's connected, a radar of nearby
/// devices (tap one to connect), pairing codes, and help when nothing shows up.
///
/// `compact` is the Mac menu-bar version: smaller radar, help inline instead
/// of in a sheet (sheets don't sit well in a menu-bar window).
struct ConnectionHomeView: View {
    @ObservedObject var coordinator: ConnectionCoordinator
    @ObservedObject var discovery: DiscoveryService
    let compact: Bool

    @State private var showHelp = false
    @State private var searchStarted = Date()
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(coordinator: ConnectionCoordinator, compact: Bool = false) {
        self.coordinator = coordinator
        self.discovery = coordinator.discovery
        self.compact = compact
    }

    private var lookingFor: LocalizedStringKey {
        coordinator.role == .host ? "Looking for iPads and Macs to use as a display…"
                                  : "Looking for your Mac…"
    }

    /// Nothing found for a while: offer help.
    private var searchingTooLong: Bool {
        discovery.peers.isEmpty && !discovery.isQuiet && now.timeIntervalSince(searchStarted) > 8
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 18) {
            header
            if discovery.health == .localNetworkDenied {
                permissionBanner
            }
            if let warning = coordinator.identityWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            ForEach(coordinator.connections, id: \.sessionID) { session in
                ConnectionCard(coordinator: coordinator, session: session)
            }
            operationStatus

            if coordinator.canConnectMore {
                RadarView(localDevice: coordinator.localDevice,
                          peers: discovery.peers,
                          isConnected: { coordinator.isConnected(to: $0.id) },
                          isPaired: { coordinator.isTrusted($0) },
                          canConnect: coordinator.canConnectMore,
                          onTap: { coordinator.connect(to: $0) },
                          size: compact ? 250 : 360)
                Text(discovery.peers.isEmpty ? lookingFor : "Tap a device to connect")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if searchingTooLong || showHelp {
                Button {
                    showHelp.toggle()
                } label: {
                    Label(showHelp && compact ? LocalizedStringKey("Hide help")
                                              : LocalizedStringKey("Can't find your device?"),
                          systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)
            } else if coordinator.canConnectMore {
                Button("Connection help") { showHelp = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            if compact && showHelp {
                ConnectionHelpView(coordinator: coordinator)
                    .frame(maxHeight: 420)
            }

            pairedDevices
        }
        .padding(compact ? 12 : 24)
        .onReceive(tick) { now = $0 }
        .onChange(of: discovery.isQuiet) { quiet in
            if !quiet { searchStarted = Date() }
        }
        .sheet(item: pairingBinding) { request in
            PairingCodeView(request: request) { approved in
                coordinator.respondToPairing(approved: approved)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showHelp) {
            ConnectionHelpView(coordinator: coordinator) { showHelp = false }
        }
        #endif
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 2) {
            Text("ScreenBridge").font(compact ? .headline : .largeTitle.bold())
            Text(verbatim: coordinator.localDevice.name)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local Network access is off", systemImage: "wifi.exclamationmark")
                .font(.headline).foregroundStyle(.red)
            Text("ScreenBridge can't see other devices until you allow it.")
                .font(.callout)
            Button("Show me how") { showHelp = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var operationStatus: some View {
        switch coordinator.phase {
        case .idle, .connected:
            EmptyView()
        case .connecting(let name):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if name.isEmpty {
                    Text("Finishing…")
                } else {
                    Text("Connecting to \(name)…")
                }
            }
        case .awaitingPairing:
            Label("Compare the codes on both screens", systemImage: "number.square")
        case .failed(let message):
            VStack(spacing: 8) {
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("OK") { coordinator.dismissError() }
                    Button("Get help") {
                        coordinator.dismissError()
                        showHelp = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pairedDevices: some View {
        if !coordinator.trustedPeers.isEmpty {
            DisclosureGroup {
                ForEach(coordinator.trustedPeers) { peer in
                    HStack {
                        Image(systemName: peer.platform.systemImage)
                        Text(verbatim: peer.name)
                        Spacer()
                        Button("Forget") { coordinator.forget(peer) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                Text("Paired devices (\(coordinator.trustedPeers.count))").font(.subheadline)
            }
        }
    }

    /// Dismissing the sheet any way other than the buttons counts as "decline".
    private var pairingBinding: Binding<PairingRequest?> {
        Binding(
            get: { coordinator.pairingRequest },
            set: { newValue in
                if newValue == nil, coordinator.pairingRequest != nil {
                    coordinator.respondToPairing(approved: false)
                }
            })
    }
}

/// One connected device: link, latency, and its own Disconnect.
private struct ConnectionCard: View {
    @ObservedObject var coordinator: ConnectionCoordinator
    let session: SecureSession

    var body: some View {
        let id = session.peer.id
        HStack(spacing: 12) {
            Image(systemName: session.peer.platform.systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.green.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: session.peer.name).font(.headline)
                if let link = coordinator.links[id] {
                    HStack(spacing: 4) {
                        Image(systemName: link.systemImage)
                        Text(verbatim: link.displayName)
                        if let rtt = coordinator.roundTrips[id] {
                            Text(verbatim: String(format: "· %.0f ms", rtt))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                if coordinator.switchingLinks.contains(id) {
                    Text("Switching link…").font(.caption).foregroundStyle(.secondary)
                } else if coordinator.betterLinks.contains(id) {
                    Text("A faster link is available").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Disconnect", role: .destructive) { coordinator.disconnect(peerID: id) }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PairingCodeView: View {
    let request: PairingRequest
    let respond: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: request.peer.platform.systemImage).font(.system(size: 44))
            Text("Pair with “\(request.peer.name)”?").font(.title3.bold())
            Text("Check that the other screen shows the same code.")
                .foregroundStyle(.secondary)
            Text(verbatim: request.formattedCode)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .padding(.vertical, 4)
            if request.previouslyPaired {
                Label("You paired with this device before, but it no longer recognizes this one. Only continue if you reset or reinstalled ScreenBridge on it.",
                      systemImage: "exclamationmark.shield")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Decline", role: .cancel) { respond(false) }
                Button("Codes Match") { respond(true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
