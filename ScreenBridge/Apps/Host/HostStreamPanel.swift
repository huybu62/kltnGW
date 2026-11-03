import SwiftUI
import ScreenBridgeKit

/// Stream controls shown in the menu bar while a Display is connected.
struct HostStreamPanel: View {
    @ObservedObject var stream: HostStreamController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Screen sharing").font(.headline)

            Picker("Mode", selection: $stream.mode) {
                ForEach(StreamMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Quality", selection: $stream.quality) {
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }

            Picker("Refresh", selection: $stream.frameRate) {
                ForEach(StreamFrameRate.allCases) { rate in
                    Text(rate.displayName).tag(rate)
                        .disabled(rate.rawValue > stream.displayMaxRefreshRate)
                }
            }
            .pickerStyle(.segmented)
            if stream.frameRate.rawValue > stream.displayMaxRefreshRate {
                Text("This display shows at most \(stream.displayMaxRefreshRate) Hz; streaming at \(stream.displayMaxRefreshRate) Hz.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if stream.frameRate == .fps120 {
                Text("120 Hz: smoothest, but uses more battery and Wi-Fi. Works best close to the router or over a cable.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            status

            if stream.state == .streaming {
                controlPermission
            }

            Divider()

            Toggle("Draw pointer on iPad (less lag)", isOn: $stream.drawPointerOnDisplay)
            Text(stream.drawPointerOnDisplay
                 ? "The pointer moves instantly on the iPad but is always a plain arrow."
                 : "The pointer is part of the video: it changes shape (text, resize…) but lags slightly.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Play sound on iPad", isOn: $stream.soundOnDisplay)
            if stream.soundOnDisplay {
                Toggle("Mute this Mac's speakers", isOn: $stream.muteMacWhileSharing)
                    .padding(.leading, 16)
            }

            Toggle("Use with the lid closed", isOn: Binding(
                get: { stream.lidClosedModeEnabled },
                set: { stream.setLidClosedMode($0) }))
            if stream.lidClosedModeEnabled {
                Text("The Mac stays awake when closed and the iPad becomes its main screen. "
                     + "Plug the MacBook into power. Don't put it in a bag while this is on.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Asks for your Mac password. Closing the lid then keeps the Mac running on the iPad.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var controlPermission: some View {
        if stream.canControlMac {
            Label("Touch & Apple Pencil control: on", systemImage: "hand.tap")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Allow touch & Apple Pencil control", systemImage: "hand.tap")
                Text("macOS needs the Accessibility permission for ScreenBridge to move the pointer and click.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Accessibility Settings") { stream.requestControlPermission() }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch stream.state {
        case .idle:
            EmptyView()
        case .starting:
            HStack { ProgressView().controlSize(.small); Text("Starting video…") }
        case .streaming:
            VStack(alignment: .leading, spacing: 2) {
                Label("Streaming", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                if let stats = stream.stats {
                    Text(stats.summary).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if stream.mode == .extend {
                    Text("Drag windows to the right edge of your screen. Arrange the new display in System Settings → Displays.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .reconnecting:
            HStack { ProgressView().controlSize(.small); Text("Connection lost. Reconnecting…") }
        case .needsScreenRecordingPermission:
            VStack(alignment: .leading, spacing: 6) {
                Label("Screen Recording permission needed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("1. Open Screen Recording settings.\n2. Turn on ScreenBridge.\n3. Quit and reopen ScreenBridge if macOS asks.")
                    .font(.caption)
                HStack {
                    Button("Open Settings") { stream.openScreenRecordingSettings() }
                    Button("Try Again") { stream.retry() }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "xmark.octagon").foregroundStyle(.red)
                Button("Try Again") { stream.retry() }
            }
        }
    }
}
