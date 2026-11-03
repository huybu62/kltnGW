#if os(macOS)
import Foundation
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Captures one display with ScreenCaptureKit, straight into the encoder's
/// native pixel format (NV12) so there's no colour conversion in between.
///
/// ScreenCaptureKit only delivers a frame when something on screen changed:
/// a still desktop costs almost nothing in CPU, battery or Wi-Fi.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: Error, LocalizedError {
        case displayNotFound
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .displayNotFound: return "The screen to capture couldn't be found."
            case .permissionDenied: return "Screen Recording permission is off for ScreenBridge."
            }
        }
    }

    /// Called on the capture queue for every *changed* frame.
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    /// Called on the audio queue with system audio, when enabled.
    var onAudio: ((CMSampleBuffer) -> Void)?
    /// Called if macOS stops the stream (display unplugged, permission revoked…).
    var onStop: ((Error) -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "app.screenbridge.capture", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "app.screenbridge.capture.audio", qos: .userInteractive)

    /// True if this app may capture the screen. Calling `requestPermission`
    /// shows the system prompt the first time.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, framesPerSecond: Int,
               captureAudio: Bool, showsCursor: Bool = true) async throws {
        let display = try await Self.findDisplay(displayID)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 5
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = captureAudio
        if captureAudio {
            configuration.sampleRate = Int(AudioPacketHeader.sampleRate)
            configuration.channelCount = Int(AudioPacketHeader.channels)
            configuration.excludesCurrentProcessAudio = true
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if captureAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    /// A newly created virtual display can take a moment to show up.
    private static func findDisplay(_ displayID: CGDirectDisplayID) async throws -> SCDisplay {
        for _ in 0..<30 {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                if !hasPermission { throw CaptureError.permissionDenied }
                throw error
            }
            if let display = content.displays.first(where: { $0.displayID == displayID }) {
                return display
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CaptureError.displayNotFound
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        if type == .audio {
            if sampleBuffer.isValid { onAudio?(sampleBuffer) }
            return
        }
        guard type == .screen, sampleBuffer.isValid,
              let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRaw = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete,  // .idle = nothing changed; skip
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }
}
#endif
