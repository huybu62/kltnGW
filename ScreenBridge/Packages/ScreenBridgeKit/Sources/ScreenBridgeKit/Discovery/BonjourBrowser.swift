import Foundation
import Network

/// Browses `_screenbridge._tcp` on every interface (including AWDL and the
/// Thunderbolt Bridge) and turns results into merged `DiscoveredPeer`s.
///
/// Confined to the main queue: discovery events are infrequent and feed UI.
final class BonjourBrowser {
    var onPeersChanged: (([String: DiscoveredPeer]) -> Void)?
    var onHealthChanged: ((DiscoveryHealth) -> Void)?

    private let localDeviceID: String
    private var browser: NWBrowser?
    private var peers: [String: DiscoveredPeer] = [:]
    private var restartAttempt = 0
    private var restartWorkItem: DispatchWorkItem?

    init(localDeviceID: String) {
        self.localDeviceID = localDeviceID
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard browser == nil else { return }
        onHealthChanged?(.starting)

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: ScreenBridgeService.type, domain: nil)
        let browser = NWBrowser(for: descriptor, using: ScreenBridgeParameters.browsing())
        self.browser = browser

        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self, let browser, browser === self.browser else { return }
            switch state {
            case .ready:
                self.restartAttempt = 0
                self.onHealthChanged?(.running)
            case .waiting(let error):
                // Includes "Local Network permission denied". The browser
                // resumes by itself if the user grants permission later.
                self.onHealthChanged?(DiscoveryHealth(error: error, failed: false))
            case .failed(let error):
                let health = DiscoveryHealth(error: error, failed: true)
                self.onHealthChanged?(health)
                self.scheduleRestart()
            case .cancelled, .setup:
                break
            @unknown default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            // Rebuild from the full snapshot: simpler and immune to missed deltas.
            self.peers = DiscoveredPeer.merge(results: results, excluding: self.localDeviceID,
                                              previous: self.peers)
            self.onPeersChanged?(self.peers)
        }

        browser.start(queue: .main)
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        restartWorkItem?.cancel()
        restartWorkItem = nil
        browser?.cancel()
        browser = nil
        peers = [:]
        onPeersChanged?([:])
        onHealthChanged?(.idle)
    }

    /// Full restart; call when the app returns to the foreground on iPadOS.
    func restart() {
        stop()
        start()
    }

    private func scheduleRestart() {
        browser?.cancel()
        browser = nil
        restartWorkItem?.cancel()
        let delay = min(pow(2, Double(restartAttempt)), 30)
        restartAttempt += 1
        let work = DispatchWorkItem { [weak self] in self?.start() }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
