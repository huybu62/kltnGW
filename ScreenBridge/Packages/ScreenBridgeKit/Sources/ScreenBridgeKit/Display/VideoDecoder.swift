import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

/// Hardware H.264/HEVC decoder. Frames go in exactly as the Host's encoder
/// produced them (length-prefixed NAL units); decoded IOSurface-backed
/// pixel buffers come out, ready for zero-copy display.
final class VideoDecoder {
    /// Called on VideoToolbox's thread.
    var onDecoded: ((CVPixelBuffer) -> Void)?
    /// The decoder can't continue without a keyframe (bad data, decoder
    /// reset after the iPad app was backgrounded…).
    var onNeedsKeyframe: (() -> Void)?

    private let lock = NSLock()
    private var format: VideoFormat?
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var waitingForKeyframe = true

    var currentFormat: VideoFormat? {
        lock.lock(); defer { lock.unlock() }
        return format
    }

    /// Applies a format from the Host. No-op if nothing changed.
    func configure(_ newFormat: VideoFormat) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if newFormat == format, session != nil { return true }
        guard let description = Self.makeFormatDescription(newFormat) else { return false }
        invalidateLocked()
        guard let session = Self.makeSession(description) else { return false }
        format = newFormat
        formatDescription = description
        self.session = session
        waitingForKeyframe = true
        return true
    }

    func decode(_ data: Data, isKeyframe: Bool) {
        lock.lock()
        if waitingForKeyframe && !isKeyframe {
            lock.unlock()
            return  // a keyframe is already on its way
        }
        if isKeyframe { waitingForKeyframe = false }
        let session = self.session
        let description = formatDescription
        lock.unlock()

        guard let session, let description,
              let sample = Self.makeSampleBuffer(data, format: description) else {
            needKeyframe()
            return
        }
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample, flags: [], infoFlagsOut: nil
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard let self else { return }
            if status == noErr, let imageBuffer {
                self.onDecoded?(imageBuffer)
            } else if status != noErr {
                self.needKeyframe()
            }
        }
        if status == kVTInvalidSessionErr {
            // iPadOS tears decoder sessions down in the background.
            rebuildSession()
            needKeyframe()
        } else if status != noErr {
            needKeyframe()
        }
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        invalidateLocked()
        format = nil
        formatDescription = nil
        waitingForKeyframe = true
    }

    private func needKeyframe() {
        lock.lock(); waitingForKeyframe = true; lock.unlock()
        onNeedsKeyframe?()
    }

    private func rebuildSession() {
        lock.lock(); defer { lock.unlock() }
        guard let description = formatDescription else { return }
        invalidateLocked()
        session = Self.makeSession(description)
    }

    private func invalidateLocked() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    // MARK: - CoreMedia plumbing

    static func makeFormatDescription(_ format: VideoFormat) -> CMVideoFormatDescription? {
        guard !format.parameterSets.isEmpty else { return nil }
        // Stable copies of each parameter set for the C API.
        let buffers: [UnsafeMutablePointer<UInt8>] = format.parameterSets.map { set in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(set.count, 1))
            set.copyBytes(to: pointer, count: set.count)
            return pointer
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers: [UnsafePointer<UInt8>] = buffers.map { UnsafePointer($0) }
        let sizes: [Int] = format.parameterSets.map(\.count)
        let nalLength = Int32(format.nalUnitHeaderLength)

        var description: CMFormatDescription?
        let status: OSStatus = pointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                switch format.codec {
                case .h264:
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: pointers.count,
                        parameterSetPointers: pointerBuffer.baseAddress!,
                        parameterSetSizes: sizeBuffer.baseAddress!,
                        nalUnitHeaderLength: nalLength, formatDescriptionOut: &description)
                case .hevc:
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: pointers.count,
                        parameterSetPointers: pointerBuffer.baseAddress!,
                        parameterSetSizes: sizeBuffer.baseAddress!,
                        nalUnitHeaderLength: nalLength, extensions: nil,
                        formatDescriptionOut: &description)
                }
            }
        }
        return status == noErr ? description : nil
    }

    static func makeSession(_ description: CMVideoFormatDescription) -> VTDecompressionSession? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: description,
            decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil, decompressionSessionOut: &session)
        guard status == noErr, let session else { return nil }
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        return session
    }

    static func makeSampleBuffer(_ data: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        let length = data.count
        guard length > 0 else { return nil }
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &blockBuffer) == noErr,
              let blockBuffer else { return nil }

        let copied = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: blockBuffer,
                                                 offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == noErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sampleSize = length
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer) == noErr else { return nil }
        return sampleBuffer
    }
}
