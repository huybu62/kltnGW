#if os(macOS)
import Foundation
import CoreMedia
import VideoToolbox

/// Hardware H.264/HEVC encoder tuned for interactive screen content:
/// real-time, no B-frames (no reordering delay), low-latency rate control,
/// keyframes only on demand.
final class VideoEncoder {
    struct Configuration {
        var codec: VideoCodec
        var width: Int
        var height: Int
        var framesPerSecond: Int
        var bitrate: Int
    }

    struct EncodedFrame {
        var data: Data
        var isKeyframe: Bool
        /// Present on keyframes.
        var parameterSets: [Data]?
        var nalUnitHeaderLength: Int
        var presentationTime: CMTime
    }

    enum EncoderError: Error, LocalizedError {
        case cannotCreate(OSStatus)
        var errorDescription: String? {
            switch self {
            case .cannotCreate(let status): return "The video encoder couldn't start (error \(status))."
            }
        }
    }

    /// Called on VideoToolbox's thread, in order. `nil` = frame was dropped
    /// by the encoder (still counts as finished for flow control).
    var onOutput: ((EncodedFrame?) -> Void)?

    private(set) var configuration: Configuration
    private var session: VTCompressionSession?
    private let lock = NSLock()
    private var keyframeRequested = true

    /// Fixed for the session's lifetime (read from VideoToolbox's thread).
    let codec: VideoCodec

    /// Tries the requested codec first, then falls back to H.264 (e.g. older
    /// Intel Macs without an HEVC hardware encoder).
    init(configuration: Configuration) throws {
        var config = configuration
        if let session = Self.makeSession(config) {
            self.session = session
        } else if config.codec == .hevc {
            config.codec = .h264
            guard let session = Self.makeSession(config) else { throw EncoderError.cannotCreate(-1) }
            self.session = session
        } else {
            throw EncoderError.cannotCreate(-1)
        }
        self.configuration = config
        self.codec = config.codec
    }

    deinit { invalidate() }

    private static func makeSession(_ config: Configuration) -> VTCompressionSession? {
        var specification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
        ]
        if config.codec == .h264 {
            specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true
        }
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width), height: Int32(config.height),
            codecType: config.codec.codecType,
            encoderSpecification: specification as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil,
            compressionSessionOut: &created)
        guard status == noErr, let session = created else { return nil }

        func set(_ key: CFString, _ value: Any) {
            VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
        }
        set(kVTCompressionPropertyKey_RealTime, true)
        set(kVTCompressionPropertyKey_AllowFrameReordering, false)
        set(kVTCompressionPropertyKey_ProfileLevel,
            config.codec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, config.framesPerSecond)
        // Keyframes are requested explicitly; this is only a safety net.
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, config.framesPerSecond * 30)
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 30)
        applyBitrate(config.bitrate, to: session)
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }

    private static func applyBitrate(_ bitrate: Int, to session: VTCompressionSession) {
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFTypeRef)
        // Cap bursts at 1.5× the average over any 1-second window.
        let bytesPerSecond = bitrate / 8 * 3 / 2
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [bytesPerSecond, 1] as CFArray)
    }

    func updateBitrate(_ bitrate: Int) {
        lock.lock(); let session = self.session; lock.unlock()
        guard let session else { return }
        configuration.bitrate = bitrate
        Self.applyBitrate(bitrate, to: session)
    }

    func requestKeyframe() {
        lock.lock(); keyframeRequested = true; lock.unlock()
    }

    private func takeKeyframeRequest() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let requested = keyframeRequested
        keyframeRequested = false
        return requested
    }

    /// Returns false if the frame was not submitted (no output will follow).
    @discardableResult
    func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
        lock.lock(); let session = self.session; lock.unlock()
        guard let session else { return false }

        var properties: CFDictionary?
        if takeKeyframeRequest() {
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: presentationTime,
            duration: .invalid, frameProperties: properties, infoFlagsOut: nil
        ) { [weak self] status, flags, sampleBuffer in
            self?.handleOutput(status: status, flags: flags, sampleBuffer: sampleBuffer)
        }
        if status != noErr {
            if properties != nil { requestKeyframe() }  // try again next frame
            return false
        }
        return true
    }

    private func handleOutput(status: OSStatus, flags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr, !flags.contains(.frameDropped), let sampleBuffer,
              CMSampleBufferDataIsReady(sampleBuffer),
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            onOutput?(nil)
            return
        }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyframe = !notSync

        var parameterSets: [Data]?
        var nalLength = 4
        if isKeyframe, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let extracted = Self.parameterSets(of: format, codec: codec)
            parameterSets = extracted.sets
            nalLength = extracted.nalUnitHeaderLength
        }

        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let copyStatus = data.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        guard copyStatus == noErr else {
            onOutput?(nil)
            return
        }

        onOutput?(EncodedFrame(data: data, isKeyframe: isKeyframe, parameterSets: parameterSets,
                               nalUnitHeaderLength: nalLength,
                               presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }

    static func parameterSets(of format: CMFormatDescription,
                              codec: VideoCodec) -> (sets: [Data], nalUnitHeaderLength: Int) {
        var count = 0
        var nalLength: Int32 = 4
        var sets: [Data] = []

        func fetch(_ index: Int) -> OSStatus {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let status: OSStatus
            switch codec {
            case .h264:
                status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size, parameterSetCountOut: &count,
                    nalUnitHeaderLengthOut: &nalLength)
            case .hevc:
                status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size, parameterSetCountOut: &count,
                    nalUnitHeaderLengthOut: &nalLength)
            }
            if status == noErr, let pointer {
                sets.append(Data(bytes: pointer, count: size))
            }
            return status
        }

        guard fetch(0) == noErr else { return ([], 4) }
        if count > 1 {
            for index in 1..<count { _ = fetch(index) }
        }
        return (sets, Int(nalLength))
    }

    func invalidate() {
        lock.lock()
        let session = self.session
        self.session = nil
        lock.unlock()
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
    }
}
#endif
