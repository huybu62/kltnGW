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

            status
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
