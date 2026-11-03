// swift-tools-version:5.9
import PackageDescription

// ScreenBridgeKit: the shared networking core used by the Host (macOS) and
// Display (macOS + iPadOS) apps. Pure Apple frameworks only: Network,
// CryptoKit, Security, VideoToolbox. No iCloud, no Continuity, no Apple ID.
let package = Package(
    name: "ScreenBridgeKit",
    platforms: [
        .macOS(.v13),   // ScreenCaptureKit maturity + MenuBarExtra; runs on 2017+ Intel Macs
        .iOS(.v16),
    ],
    products: [
        .library(name: "ScreenBridgeKit", targets: ["ScreenBridgeKit"]),
    ],
    targets: [
        .target(name: "ScreenBridgeKit"),
        .testTarget(name: "ScreenBridgeKitTests", dependencies: ["ScreenBridgeKit"]),
    ]
)
