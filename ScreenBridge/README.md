# ScreenBridge

Use any Mac or iPad as a second display for a Mac, **even when the devices are signed in to different Apple IDs**.

| Role | Platform | What it does |
|------|----------|--------------|
| **Host** | macOS 13+ (menu bar app) | Captures the screen with ScreenCaptureKit, encodes it with VideoToolbox (H.264/HEVC), sends it |
| **Display** | macOS 13+ / iPadOS 16+ | Receives, decodes with VideoToolbox, renders with `AVSampleBufferDisplayLayer`/Metal |

Status: **Phase 1 of 4 is done.** This phase covers discovery, the transport, pairing across Apple IDs, and the encrypted session. Phase 2 adds the video pipeline, Phase 3 streams it, Phase 4 builds the final UI (radar, onboarding).

---

## Why this works across Apple IDs (and Sidecar doesn't)

Sidecar trusts devices through iCloud and Continuity, so both devices must use the same Apple ID. ScreenBridge doesn't use iCloud at all:

| Concern | Sidecar | ScreenBridge |
|---|---|---|
| Finding devices | Continuity (iCloud account) | Bonjour `_screenbridge._tcp` on every interface, AWDL included |
| Device identity | Apple ID | Ed25519 key generated on each device, kept in the local Keychain (`ThisDeviceOnly`, never synced) |
| Trust | Same iCloud account | One-time pairing: both screens show the same 6-digit code |
| Encryption | Apple-managed | X25519 ECDH, then ChaCha20-Poly1305 per direction |
| Device name | iCloud name | System name, or a name you set yourself (iPadOS 16+ hides the real name from apps) |

The things that *do* gate cross-account use are per-app, not per-Apple-ID. The code handles each one:

- **Local Network privacy** (iOS 14+, macOS 15+). Detected as `kDNSServiceErr_PolicyDenied` and reported as `DiscoveryHealth.localNetworkDenied`, with step-by-step fix instructions.
- **App Sandbox.** Without `network.server`, `NWListener` fails. Both entitlements are set in `project.yml`.
- **Missing Keychain entitlement** (unsigned builds). Falls back to a 0600 file, so the app still runs.
- **Networks that block multicast** (guest or corporate Wi-Fi). AWDL peer-to-peer still works without a router. As a last resort you can connect manually to the IP shown on the device, on fixed port **52790**.

## Pairing protocol

```
Initiator (either side)                       Responder
  ClientHello {device, IK_I, H(EK_I‖nonce)} ─▶
                                          ◀─ ServerHello {device, IK_R, EK_R, nonce, trustsPeer}
  KeyReveal {EK_I, nonce, trustsPeer}       ─▶  (checks the commitment)
            shared = X25519(EK_I, EK_R),  TH = H(all three messages)
  ── both trust each other ──▶ exchange Sign_IK(TH ‖ role)  → connected, no prompt
  ── otherwise ──▶ both show SAS = HKDF(shared, TH) mod 10⁶ → users confirm → signatures → keys saved
```

- The device ID is a fingerprint of the identity key, and every handshake checks it. No one can pose as a device they don't hold the key for.
- The commitment in the first message stops a man-in-the-middle from trying keys until the codes match. Each MITM attempt has a 10⁻⁶ chance of success, and the user sees a prompt every time.
- If one side forgets the pairing (it was reset or reinstalled), both sides fall back to the code prompt, and the side that still knows the peer shows a warning.
- Once paired, a device reconnects with no prompt. Turn off `autoAccept` if you want codes compared on every connection.

## Link priority

`PeerConnector` tries the routes Bonjour found in this order, pinning each attempt to its interface with `requiredInterface`:

1. **Thunderbolt Bridge** (`bridge0…99`): Mac ↔ Mac over a Thunderbolt/USB4 cable, 10–40 Gbit/s
2. **Ethernet**, including a USB-C Ethernet adapter on an iPad
3. **Wi-Fi** on the same network
4. **Direct Wi-Fi (AWDL)**: no router needed
5. An unpinned attempt where the OS picks the route

Wired attempts time out after 2 s and wireless ones after 5 s, so a missing cable costs almost nothing. If a better path appears mid-session (you plug in the cable), it is reported as `betterLinkAvailable`. Phase 3 will move the stream onto it.

## ⚠️ Constraints to know before Phases 2–3

1. **Bluetooth can't carry video.** In practice BLE moves well under 1 Mbit/s. A 1080p60 stream needs 15–40 Mbit/s, and Retina needs more. The Network framework also no longer runs Bonjour over Bluetooth. Where Bluetooth helps is waking or finding a device when Wi-Fi is off. That optional CoreBluetooth beacon fits behind the discovery layer later. AWDL already gives a cable-free, router-free path at Wi-Fi speeds.
2. **iPad over a USB-C cable isn't an IP link.** A Mac ↔ Mac Thunderbolt Bridge is a normal network interface and works now. An iPad cabled to a Mac has no network interface unless you use a USB-C Ethernet adapter. A true wired iPad mode means talking to `usbmuxd` on the Mac, the approach PeerTalk uses. That's planned as an optional Phase 3 transport.
3. **"Extend" needs a virtual display.** Mirroring an existing screen uses only public API (ScreenCaptureKit). To *extend* the desktop, macOS needs a display to place windows on. Creating one in software uses `CGVirtualDisplay`, a private API. Many shipping tools use it, but it rules out the Mac App Store. A cheap HDMI dummy plug is the all-public alternative. Phase 2 will put this behind a protocol so either approach works.
4. **iPadOS must stay in the foreground** to receive. The app re-advertises on `scenePhase == .active` and turns off the idle timer while connected.

## Project layout

```
ScreenBridge/
├── project.yml                     XcodeGen spec (3 app targets, Universal Binary)
├── Packages/ScreenBridgeKit/       Shared Swift package (all networking lives here)
│   ├── Sources/ScreenBridgeKit/
│   │   ├── Discovery/   ServiceConstants, PeerAdvertisement (TXT), DiscoveredPeer,
│   │   │                BonjourBrowser, BonjourAdvertiser, DiscoveryService, DiscoveryHealth
│   │   ├── Transport/   LinkType, WireProtocol (NWProtocolFramer), NetworkParameters,
│   │   │                PeerConnection (async/await NWConnection), PeerConnector
│   │   ├── Identity/    DeviceInfo, DeviceIdentity, SecretStore, TrustStore,
│   │   │                HandshakeCrypto, SessionCrypto
│   │   └── Session/     HandshakeMessages, SessionHandshake, SecureSession,
│   │                    ConnectionCoordinator (what SwiftUI binds to)
│   └── Tests/           TXT, framing, link ranking, crypto, loopback end-to-end handshake
└── Apps/
    ├── Host/            Menu bar app (MenuBarExtra)
    ├── Display/         macOS + iPadOS app
    └── Shared/          Phase 1 debug UI (replaced by the radar UI in Phase 4)
```

## Build & run

Requirements: Xcode 15 or newer, on macOS 13 or newer.

```bash
brew install xcodegen
```

```bash
cd ScreenBridge && xcodegen generate && open ScreenBridge.xcodeproj
```

Run the package tests. They include a real handshake over loopback between two independent identities, which is exactly the different-Apple-ID case:

```bash
cd ScreenBridge/Packages/ScreenBridgeKit && swift test
```

Check that a Release build is universal:

```bash
xcodebuild -project ScreenBridge.xcodeproj -scheme ScreenBridgeHost -configuration Release -derivedDataPath build
```

```bash
lipo -archs "build/Build/Products/Release/ScreenBridge.app/Contents/MacOS/ScreenBridge"
```

The `lipo` command should print `x86_64 arm64`.

### Phase 1 test checklist (two devices, two different Apple IDs)

1. Run **ScreenBridgeHost** on Mac A. Run **ScreenBridgeDisplay-iOS** on the iPad, or **ScreenBridgeDisplay-macOS** on Mac B.
2. Accept the Local Network prompt on both devices.
3. Each device lists the other within a second or two, with its link badges (Wi-Fi, Direct Wi-Fi, and Thunderbolt if cabled).
4. Click **Connect** on either side. Both screens show the same 6-digit code. Confirm on both.
5. You should see "Connected", the link type, and a live RTT. Expect a few ms on Wi-Fi and well under 1 ms on Thunderbolt.
6. Disconnect, then connect again. This time there is no code prompt, because the devices are paired.
7. Tap **Forget** on one side and connect again. The code prompt returns, and the other side shows a warning.
8. Mac ↔ Mac only: plug in a Thunderbolt cable and enable *Thunderbolt Bridge* in System Settings → Network. The peer now shows a ⚡ Thunderbolt badge, and new connections prefer that link.
