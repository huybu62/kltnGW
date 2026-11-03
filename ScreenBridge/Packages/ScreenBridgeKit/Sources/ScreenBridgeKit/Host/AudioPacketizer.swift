#if os(macOS)
import Foundation
import AVFoundation
import CoreMedia

/// Converts ScreenCaptureKit's audio (32-bit float, non-interleaved) into
/// `sealedAudio` payloads (16-bit interleaved PCM at 48 kHz stereo).
/// Called on ScreenCaptureKit's audio queue.
final class AudioPacketizer {
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: Double(AudioPacketHeader.sampleRate),
                                             channels: AVAudioChannelCount(AudioPacketHeader.channels),
                                             interleaved: true)!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func packet(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        input.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList) == noErr else { return nil }

        if converter == nil || inputFormat != format {
            converter = AVAudioConverter(from: format, to: outputFormat)
            inputFormat = format
        }
        let ratio = outputFormat.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 16
        guard let converter,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else { return nil }

        let byteCount = Int(output.frameLength) * Int(AudioPacketHeader.channels) * MemoryLayout<Int16>.size
        var packet = AudioPacketHeader().encoded()
        packet.append(Data(bytes: samples[0], count: byteCount))
        return packet
    }
}
#endif
