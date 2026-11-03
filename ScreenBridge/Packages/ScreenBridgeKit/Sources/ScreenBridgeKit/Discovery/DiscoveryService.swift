import Foundation
import Combine
import Network

/// The discovery façade the UI binds to: advertises this device, browses for
/// the counterpart role, and publishes a stable, sorted list for the radar.
///
/// Both roles advertise *and* browse, so either side can start a connection
/// ("1-click connect" from the Mac's menu bar or from the iPad).
///
/// Main-thread confined (all Network callbacks are scheduled on `.main`).
public final class DiscoveryService: ObservableObject {
    @Published public private(set) var peers: [DiscoveredPeer] = []
    @Published public private(set) var health: DiscoveryHealth = .idle
    /// Name Bonjour actually registered (may differ after collision renaming).
    @Published public private(set) var registeredServiceName: String?
    @Published public private(set) var isRunning = false
    /// TCP port we listen on, for the manual-connection fallback screen.
    @Published public private(set) var listeningPort: UInt16?

    public private(set) var localDevice: DeviceInfo
    public let browseRoles: Set<PeerRole>

    /// Raw incoming connections, already framed; handed to the session layer.
    public var onIncomingConnection: ((NWConnection) -> Void)?

    private let browser: BonjourBrowser
    private let advertiser: BonjourAdvertiser?
    private var browserHealth: DiscoveryHealth = .idle
    private var advertiserHealth: DiscoveryHealth = .idle
    private var isBusy = false

    /// - Parameters:
    ///   - browseRoles: which roles to show; defaults to the counterpart role.
    ///   - advertise: publish this device so others can find and connect to it.
    public init(localDevice: DeviceInfo, browseRoles: Set<PeerRole>? = nil, advertise: Bool = true) {
        self.localDevice = localDevice
        self.browseRoles = browseRoles ?? [localDevice.role.counterpart]
        self.browser = BonjourBrowser(localDeviceID: localDevice.id)
        self.advertiser = advertise ? BonjourAdvertiser(advertisement: PeerAdvertisement(device: localDevice)) : nil

        browser.onPeersChanged = { [weak self] peers in self?.apply(peers) }
        browser.onHealthChanged = { [weak self] health in
            self?.browserHealth = health
            self?.recomputeHealth()
        }
        advertiser?.onHealthChanged = { [weak self] health in
            self?.advertiserHealth = health
            self?.recomputeHealth()
        }
        advertiser?.onRegisteredNameChanged = { [weak self] name in self?.registeredServiceName = name }
        advertiser?.onPortChanged = { [weak self] port in self?.listeningPort = port }
        advertiser?.onIncomingConnection = { [weak self] connection in
            guard let self, let handler = self.onIncomingConnection else {
                connection.cancel()
                return
            }
            handler(connection)
        }
    }

    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRunning else { return }
        isRunning = true
        advertiser?.start()
        browser.start()
    }

    public func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning else { return }
        isRunning = false
        browser.stop()
        advertiser?.stop()
    }

    /// Tear down and re-create the listener and browser. Call when an iPad app
    /// becomes active again: iPadOS invalidates listeners in the background.
    public func restart() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning else { return start() }
        advertiser?.restart()
        browser.restart()
    }

    /// Advertise busy so other radars grey this device out during a session.
    public func setBusy(_ busy: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        isBusy = busy
        advertiser?.update(advertisement: PeerAdvertisement(device: localDevice, isBusy: busy))
    }

    /// Update the advertised name/capabilities (e.g. user renamed the iPad).
    public func updateLocalDevice(_ device: DeviceInfo) {
        dispatchPrecondition(condition: .onQueue(.main))
        localDevice = device
        advertiser?.update(advertisement: PeerAdvertisement(device: device, isBusy: isBusy))
    }

    public func peer(id: String) -> DiscoveredPeer? {
        peers.first { $0.id == id }
    }

    private func apply(_ merged: [String: DiscoveredPeer]) {
        peers = merged.values
            .filter { browseRoles.contains($0.advertisement.role) }
            .sorted { lhs, rhs in
                if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
                if lhs.bestLink != rhs.bestLink { return lhs.bestLink < rhs.bestLink }
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    private func recomputeHealth() {
        health = advertiser == nil ? browserHealth : DiscoveryHealth.worst(browserHealth, advertiserHealth)
    }
}
