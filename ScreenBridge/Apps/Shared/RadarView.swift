import SwiftUI
import ScreenBridgeKit

/// Radar of nearby devices: this device in the middle, pulsing rings and a
/// sweeping beam, and every device found as a bubble you tap to connect.
/// Faster links sit closer to the middle (cable inside, Wi-Fi outside).
struct RadarView: View {
    let localDevice: DeviceInfo
    let peers: [DiscoveredPeer]
    let isConnected: (DiscoveredPeer) -> Bool
    let isPaired: (DiscoveredPeer) -> Bool
    let canConnect: Bool
    let onTap: (DiscoveredPeer) -> Void
    var size: CGFloat = 320

    @State private var pulse = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            rings
            beam
            center
            ForEach(peers) { peer in
                PeerBubble(peer: peer,
                           connected: isConnected(peer),
                           paired: isPaired(peer),
                           enabled: canConnect || isConnected(peer))
                    .position(position(of: peer))
                    .onTapGesture {
                        guard canConnect, !isConnected(peer), peer.isAvailable else { return }
                        onTap(peer)
                    }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: peers.map(\.id))
        .onAppear {
            pulse = true
            sweep = true
        }
    }

    // MARK: Pieces

    private var rings: some View {
        ZStack {
            ForEach(1...3, id: \.self) { index in
                Circle()
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                    .frame(width: size * CGFloat(index) / 3, height: size * CGFloat(index) / 3)
            }
            // A ring that keeps expanding outward, like a sonar ping.
            Circle()
                .stroke(Color.accentColor.opacity(pulse ? 0 : 0.45), lineWidth: 2)
                .frame(width: pulse ? size : size * 0.2, height: pulse ? size : size * 0.2)
                .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false), value: pulse)
        }
    }

    private var beam: some View {
        Circle()
            .fill(AngularGradient(gradient: Gradient(colors: [Color.accentColor.opacity(0.28), .clear, .clear]),
                                  center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(sweep ? 360 : 0))
            .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: sweep)
            .mask(Circle())
            .allowsHitTesting(false)
    }

    private var center: some View {
        VStack(spacing: 4) {
            Image(systemName: localDevice.platform.systemImage)
                .font(.system(size: size * 0.09, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size * 0.2, height: size * 0.2)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: Color.accentColor.opacity(0.5), radius: 10)
            Text(localDevice.name)
                .font(.caption2.bold())
                .lineLimit(1)
                .frame(maxWidth: size * 0.4)
        }
    }

    // MARK: Layout

    /// Stable angle per device (so bubbles don't jump around), and a radius
    /// by link: cable closest, Direct Wi-Fi furthest.
    private func position(of peer: DiscoveredPeer) -> CGPoint {
        var hash: UInt32 = 2_166_136_261
        for byte in peer.id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        let angle = Double(hash % 360) * .pi / 180
        let fraction: CGFloat
        switch peer.bestLink {
        case .thunderbolt, .ethernet: fraction = 0.52
        case .wifi: fraction = 0.72
        default: fraction = 0.86
        }
        let radius = size / 2 * fraction
        return CGPoint(x: size / 2 + radius * CGFloat(cos(angle)),
                       y: size / 2 + radius * CGFloat(sin(angle)))
    }
}

/// One nearby device on the radar.
private struct PeerBubble: View {
    let peer: DiscoveredPeer
    let connected: Bool
    let paired: Bool
    let enabled: Bool

    private var tint: Color {
        if connected { return .green }
        if !peer.isAvailable || !enabled { return .gray }
        return paired ? .accentColor : .orange
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: peer.advertisement.platform.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(tint.gradient))
                    .shadow(color: tint.opacity(0.45), radius: 6)
                Image(systemName: peer.bestLink.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .padding(4)
                    .background(Circle().fill(.thinMaterial))
                    .offset(x: 4, y: 4)
            }
            Text(peer.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(statusText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 96)
        .contentShape(Rectangle())
        .opacity(enabled || connected ? 1 : 0.55)
    }

    private var statusText: LocalizedStringKey {
        if connected { return "Connected" }
        if peer.advertisement.isBusy { return "Busy" }
        if !peer.advertisement.isCompatible { return "Update needed" }
        return paired ? "Tap to connect" : "Tap to pair"
    }
}
