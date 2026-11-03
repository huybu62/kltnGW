// swift-tools-version:5.9
import PackageDescription

// ScreenBridgeKit: the shared core used by the Host (macOS) and Display
// (macOS + iPadOS) apps. Apple frameworks only: Network, CryptoKit,
// Security, ScreenCaptureKit, VideoToolbox, AVFoundation. No iCloud.
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
        // Private CoreGraphics virtual-display declarations (Extend mode, macOS only).
        .target(
            name: "CGVirtualDisplayPrivate",
            linkerSettings: [.linkedFramework("CoreGraphics", .when(platforms: [.macOS]))]
        ),
        .target(
            name: "ScreenBridgeKit",
            dependencies: [
                .target(name: "CGVirtualDisplayPrivate", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(name: "ScreenBridgeKitTests", dependencies: ["ScreenBridgeKit"]),
    ]
)
