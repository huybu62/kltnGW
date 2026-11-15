import SwiftUI
import ScreenBridgeKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Step-by-step help when the other device doesn't show up, ending with a
/// manual connection by IP address that works even when the network blocks
/// device discovery.
struct ConnectionHelpView: View {
    @ObservedObject var coordinator: ConnectionCoordinator
    @ObservedObject var discovery: DiscoveryService
    var onDone: (() -> Void)?

    @State private var manualHost = ""
    @State private var manualPort = "52790"
    @State private var addresses: [LocalAddresses.Address] = []

    init(coordinator: ConnectionCoordinator, onDone: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self.discovery = coordinator.discovery
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Can't find your device?").font(.title2.bold())
                    Spacer()
                    if let onDone {
                        Button("Done", action: onDone)
                    }
                }
                Text("Check these in order. Most problems are solved by the first three.")
                    .foregroundStyle(.secondary)

                HelpStep(number: 1, symbol: "apps.ipad.landscape",
                         title: "Open ScreenBridge on both devices",
                         detail: "On the iPad keep the app on screen; iPadOS pauses apps in the background.")
                HelpStep(number: 2, symbol: "wifi",
                         title: "Same Wi-Fi network, or plug in a cable",
                         detail: "Both devices on the same Wi-Fi (5 GHz is best), or connected with a USB-C / Thunderbolt cable.")
                HelpStep(number: 3, symbol: "network",
                         title: "Allow Local Network",
                         detail: localNetworkDetail,
                         warning: discovery.health == .localNetworkDenied) {
                    Button("Open Settings", action: openLocalNetworkSettings)
                }
                HelpStep(number: 4, symbol: "lock.shield",
                         title: "Turn off VPN",
                         detail: "A VPN on either device can hide the other one.")
                #if os(macOS)
                HelpStep(number: 5, symbol: "flame",
                         title: "Firewall",
                         detail: "System Settings → Network → Firewall → Options: allow ScreenBridge, and turn off “Block all incoming connections”.")
                #endif
                HelpStep(number: lastStepNumber, symbol: "building.2",
                         title: "Office, school, hotel or café Wi-Fi",
                         detail: "Many of these networks stop devices from seeing each other. Use a cable, or turn on your phone's Personal Hotspot and join it with both devices.")

                manualConnection
            }
            .padding()
        }
        .onAppear { addresses = LocalAddresses.current() }
    }

    private var lastStepNumber: Int {
        #if os(macOS)
        return 6
        #else
        return 5
        #endif
    }

    private var localNetworkDetail: String {
        #if os(macOS)
        return "System Settings → Privacy & Security → Local Network → turn on ScreenBridge, then quit and reopen it."
        #else
        return "Settings → Privacy & Security → Local Network → turn on ScreenBridge."
        #endif
    }

    // MARK: Manual connection

    private var manualConnection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect by address", systemImage: "number")
                .font(.headline)
            Text("Works even when the devices can't find each other automatically.")
                .font(.callout).foregroundStyle(.secondary)

            Text("This device's address (type it on the other device):")
                .font(.callout)
            if addresses.isEmpty {
                Text("No network connection").font(.callout.monospaced()).foregroundStyle(.secondary)
            } else {
                ForEach(addresses) { address in
                    HStack {
                        Image(systemName: address.link.systemImage).foregroundStyle(.secondary)
                        Text(verbatim: "\(address.address) : \(discovery.listeningPort.map(String.init) ?? "52790")")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Text("Or enter the other device's address:")
                .font(.callout)
                .padding(.top, 4)
            HStack {
                TextField("192.168.1.20", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                Text(verbatim: ":")
                TextField("52790", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Connect") {
                    guard let port = UInt16(manualPort.trimmingCharacters(in: .whitespaces)) else { return }
                    coordinator.connect(host: manualHost.trimmingCharacters(in: .whitespaces), port: port)
                    onDone?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualHost.isEmpty || !coordinator.canConnectMore)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func openLocalNetworkSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

private struct HelpStep<Accessory: View>: View {
    let number: Int
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var warning = false
    let accessory: Accessory

    init(number: Int, symbol: String, title: LocalizedStringKey, detail: String,
         warning: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.number = number
        self.symbol = symbol
        self.title = title
        self.detail = LocalizedStringKey(detail)
        self.warning = warning
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(warning ? Color.red : Color.accentColor).frame(width: 34, height: 34)
                Image(systemName: symbol).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(warning ? Color.red.opacity(0.1) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

extension HelpStep where Accessory == EmptyView {
    init(number: Int, symbol: String, title: LocalizedStringKey, detail: String, warning: Bool = false) {
        self.init(number: number, symbol: symbol, title: title, detail: detail, warning: warning) { EmptyView() }
    }
}
