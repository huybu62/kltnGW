import SwiftUI
import ScreenBridgeKit

/// Phase 1 test bench: nearby devices, 1-click connect, pairing codes, link
/// and RTT. Replaced by the radar UI in Phase 4; the coordinator API stays.
struct DiscoveryDebugView: View {
    @ObservedObject var coordinator: ConnectionCoordinator
    @ObservedObject var discovery: DiscoveryService

    init(coordinator: ConnectionCoordinator) {
        self.coordinator = coordinator
        self.discovery = coordinator.discovery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if discovery.health == .localNetworkDenied {
                permissionBanner
            }
            if let warning = coordinator.identityWarning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            statusRow
            Divider()
            Text(coordinator.role == .host ? "Nearby displays" : "Nearby Macs")
                .font(.headline)
            if discovery.peers.isEmpty {
                Text("Searching… Make sure ScreenBridge is open on the other device.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(discovery.peers) { peer in
                    peerRow(peer)
                }
            }
            if !coordinator.trustedPeers.isEmpty {
                Divider()
                Text("Paired devices").font(.headline)
                ForEach(coordinator.trustedPeers) { peer in
                    HStack {
                        Image(systemName: peer.platform.systemImage)
                        Text(peer.name)
                        Spacer()
                        Button("Forget") { coordinator.forget(peer) }
                    }
                }
            }
        }
        .padding()
        .sheet(item: pairingBinding) { request in
            PairingCodeView(request: request) { approved in
                coordinator.respondToPairing(approved: approved)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: coordinator.localDevice.platform.systemImage).font(.title2)
            VStack(alignment: .leading) {
                Text(coordinator.localDevice.name).font(.headline)
                Text("ID \(String(coordinator.localDevice.id.prefix(8))) · port \(discovery.listeningPort.map(String.init) ?? "–")")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Local Network access is off", systemImage: "wifi.exclamationmark")
                .font(.headline).foregroundStyle(.red)
            ForEach(Array(LocalNetworkDiagnostics.enablePermissionSteps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(.callout)
            }
        }
        .padding(8)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Every connected device, each with its own link and Disconnect.
            ForEach(coordinator.connections, id: \.sessionID) { session in
                connectionRow(session)
            }
            switch coordinator.phase {
            case .idle, .connected:
                if !coordinator.isConnected || coordinator.canConnectMore {
                    Label(discoveryStatusText, systemImage: "dot.radiowaves.left.and.right")
                }
            case .connecting(let name):
                HStack { ProgressView().controlSize(.small); Text(name.isEmpty ? "Finishing…" : "Connecting to \(name)…") }
            case .awaitingPairing:
                Label("Compare the codes on both screens", systemImage: "number.square")
            case .failed(let message):
                HStack {
                    Label(message, systemImage: "xmark.octagon").foregroundStyle(.red)
                    Spacer()
                    Button("OK") { coordinator.dismissError() }
                }
            }
        }
    }

    private func connectionRow(_ session: SecureSession) -> some View {
        let id = session.peer.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Connected to \(session.peer.name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Disconnect") { coordinator.disconnect(peerID: id) }
            }
            if let link = coordinator.links[id] {
                Label("\(link.displayName) · RTT \(coordinator.roundTrips[id].map { String(format: "%.1f ms", $0) } ?? "…")",
                      systemImage: link.systemImage)
                    .font(.callout)
            }
            if coordinator.switchingLinks.contains(id) {
                Label("Switching link…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            } else if coordinator.betterLinks.contains(id) {
                Label("A faster link is available", systemImage: "bolt.horizontal")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var discoveryStatusText: String {
        switch discovery.health {
        case .idle: return "Not searching"
        case .starting: return "Starting…"
        case .running: return "Visible as “\(discovery.registeredServiceName ?? coordinator.localDevice.name)”"
        case .localNetworkDenied: return "Blocked by Local Network permission"
        case .waiting(let reason): return "Waiting for network: \(reason)"
        case .failed(let reason): return "Discovery error: \(reason) (retrying)"
        }
    }

    private func peerRow(_ peer: DiscoveredPeer) -> some View {
        HStack {
            Image(systemName: peer.advertisement.platform.systemImage).font(.title3)
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(peer.name)
                    if coordinator.isTrusted(peer) { Image(systemName: "lock.fill").font(.caption2) }
                }
                HStack(spacing: 6) {
                    ForEach(peer.links, id: \.self) { link in
                        Label(link.displayName, systemImage: link.systemImage).font(.caption2)
                    }
                    if let display = peer.advertisement.display {
                        Text("\(display.resolutionLabel) @\(display.maxRefreshRate)Hz").font(.caption2)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if peer.advertisement.isBusy {
                Text("Busy").font(.caption).foregroundStyle(.secondary)
            } else if !peer.advertisement.isCompatible {
                Text("Update needed").font(.caption).foregroundStyle(.orange)
            } else {
                if coordinator.isConnected(to: peer.id) {
                    Text("Connected").font(.caption).foregroundStyle(.green)
                } else {
                    Button("Connect") { coordinator.connect(to: peer) }
                        .disabled(!coordinator.canConnectMore)
                }
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

struct PairingCodeView: View {
    let request: PairingRequest
    let respond: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: request.peer.platform.systemImage).font(.system(size: 44))
            Text("Pair with “\(request.peer.name)”?").font(.title3.bold())
            Text("Check that the other screen shows the same code.")
                .foregroundStyle(.secondary)
            Text(request.formattedCode)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .padding(.vertical, 4)
            if request.previouslyPaired {
                Label("You paired with this device before, but it no longer recognizes this one. "
                      + "Only continue if you reset or reinstalled ScreenBridge on it.",
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
