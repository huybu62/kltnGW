#if os(iOS)
import AVFoundation
import AVKit
import CoreMedia

/// Picture in Picture for the Mac screen: when you leave the iPad app, the
/// picture shrinks into a floating window and keeps playing, which is also
/// what lets iPadOS keep the app (and the connection) running.
///
/// Needs the "audio" background mode and an active `.playback` audio
/// session. The stream is live, so the window shows no play/skip controls.
final class PictureInPicture: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate,
                              AVPictureInPictureControllerDelegate {
    private var controller: AVPictureInPictureController?
    /// True when the floating window opens, false when it closes.
    var onActiveChanged: ((Bool) -> Void)?

    /// The category Picture in Picture requires. Shared with `AudioPlayer`.
    static func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    init(layer: AVSampleBufferDisplayLayer) {
        super.init()
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        Self.activateAudioSession()
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer,
                                                                playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        pip.requiresLinearPlayback = true
        pip.delegate = self
        controller = pip
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    // MARK: AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Live: no seekable range.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController) -> Bool { false }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onActiveChanged?(true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
#endif
