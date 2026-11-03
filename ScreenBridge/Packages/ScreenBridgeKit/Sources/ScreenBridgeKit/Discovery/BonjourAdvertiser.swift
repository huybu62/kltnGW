import Foundation
import Network

/// Publishes this device via Bonjour and accepts incoming connections.
///
/// The NWListener uses the same parameters as outgoing connections, so
/// accepted connections already have ScreenBridge framing installed. With
/// `includePeerToPeer` it is reachable over AWDL as well as Wi-Fi/Ethernet/
/// Thunderbolt Bridge — and none of it involves iCloud or an Apple ID.
///
/// Confined to the main queue.
final class BonjourAdvertiser {
    var onIncomingConnection: ((NWConnection) -> Void)?
    var onHealthChanged: ((DiscoveryHealth) -> Void)?
    var onRegisteredNameChanged: ((String?) -> Void)?
    var onPortChanged: ((UInt16?) -> Void)?

    /// We first try a fixed, documented port so the manual-connection
    /// fallback ("type 192.168.1.20 : 52790") is predictable; if it's taken
    /// we let the OS pick one.
    static let preferredPort: UInt16 = 52790
    private var usePreferredPort = true

    private var listener: NWListener?
    private var advertisement: PeerAdvertisement
    private var restartAttempt = 0
    private var restartWorkItem: DispatchWorkItem?

    init(advertisement: PeerAdvertisement) {
        self.advertisement = advertisement
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard listener == nil else { return }
        onHealthChanged?(.starting)

        let listener: NWListener
        do {
            if usePreferredPort, let port = NWEndpoint.Port(rawValue: Self.preferredPort) {
                listener = try NWListener(using: ScreenBridgeParameters.make(), on: port)
            } else {
                listener = try NWListener(using: ScreenBridgeParameters.make())
            }
        } catch {
            // Almost always a missing `com.apple.security.network.server`
            // entitlement on a sandboxed Mac app.
            onHealthChanged?(.failed("Couldn't open a listening socket: \(error.localizedDescription)"))
            scheduleRestart()
            return
        }
        self.listener = listener
        listener.service = makeService()

        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            switch change {
            case .add(let endpoint):
                if case .service(let name, _, _, _) = endpoint {
                    self?.onRegisteredNameChanged?(name)
                }
            case .remove:
                self?.onRegisteredNameChanged?(nil)
            @unknown default:
                break
            }
        }

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener else { return }
            switch state {
            case .ready:
                self.restartAttempt = 0
                self.onPortChanged?(listener.port?.rawValue)
                self.onHealthChanged?(.running)
            case .waiting(let error):
                self.onHealthChanged?(DiscoveryHealth(error: error, failed: false))
            case .failed(let error):
                if case .posix(.EADDRINUSE) = error, self.usePreferredPort {
                    // Another app (or a second copy of ours) owns the port.
                    self.usePreferredPort = false
                    self.listener?.cancel()
                    self.listener = nil
                    self.start()
                    return
                }
                // Common on iPadOS after returning from background (ECONNABORTED).
                self.onHealthChanged?(DiscoveryHealth(error: error, failed: true))
                self.scheduleRestart()
            case .cancelled, .setup:
                break
            @unknown default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self, let handler = self.onIncomingConnection else {
                connection.cancel()
                return
            }
            handler(connection)
        }

        listener.start(queue: .main)
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        restartWorkItem?.cancel()
        restartWorkItem = nil
        listener?.cancel()
        listener = nil
        onRegisteredNameChanged?(nil)
        onPortChanged?(nil)
        onHealthChanged?(.idle)
    }

    func restart() {
        stop()
        start()
    }

    /// Re-publishes the TXT record (e.g. busy flag or name changed).
    func update(advertisement: PeerAdvertisement) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard advertisement != self.advertisement else { return }
        self.advertisement = advertisement
        listener?.service = makeService()
    }

    private func makeService() -> NWListener.Service {
        NWListener.Service(name: advertisement.serviceName, type: ScreenBridgeService.type,
                           domain: nil, txtRecord: advertisement.txtRecord)
    }

    private func scheduleRestart() {
        listener?.cancel()
        listener = nil
        restartWorkItem?.cancel()
        let delay = min(pow(2, Double(restartAttempt)), 30)
        restartAttempt += 1
        let work = DispatchWorkItem { [weak self] in self?.start() }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
