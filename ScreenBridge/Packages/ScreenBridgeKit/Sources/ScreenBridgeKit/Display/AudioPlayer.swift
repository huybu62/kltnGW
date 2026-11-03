import Foundation
import AVFoundation

/// Plays the Mac's sound on this device with a small (~40 ms) buffer.
///
/// If packets pile up (the two devices' audio clocks drift, or the network
/// hiccups and then delivers a burst), packets are dropped once more than
/// ~120 ms is queued, so sound never lags behind the picture.
final class AudioPlayer {
    private let queue = DispatchQueue(label: "app.screenbridge.audio", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let packetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: Double(AudioPacketHeader.sampleRate),
                                             channels: AVAudioChannelCount(AudioPacketHeader.channels),
                                             interleaved: true)!
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: Double(AudioPacketHeader.sampleRate),
                                               channels: AVAudioChannelCount(AudioPacketHeader.channels))!
    private lazy var converter = AVAudioConverter(from: packetFormat, to: playbackFormat)

    private let lock = NSLock()
    private var queuedFrames: Int = 0
    private var engineReady = false

    private var startThreshold: Int { Int(Double(AudioPacketHeader.sampleRate) * 0.04) }
    private var maximumQueued: Int { Int(Double(AudioPacketHeader.sampleRate) * 0.12) }

    /// Any thread.
    func enqueue(_ payload: Data) {
        queue.async { self.play(payload) }
    }

    /// Any thread.
    func stop() {
        queue.async {
            guard self.engineReady else { return }
            self.player.stop()
            self.engine.stop()
            self.engineReady = false
            self.lock.lock(); self.queuedFrames = 0; self.lock.unlock()
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    // MARK: - Audio queue

    private func play(_ payload: Data) {
        guard let header = AudioPacketHeader(payload),
              header.sampleRate == AudioPacketHeader.sampleRate,
              header.channels == AudioPacketHeader.channels else { return }
        let bytesPerFrame = Int(AudioPacketHeader.channels) * MemoryLayout<Int16>.size
        let frameCount = (payload.count - AudioPacketHeader.size) / bytesPerFrame
        guard frameCount > 0 else { return }

        lock.lock()
        let tooFarBehind = queuedFrames > maximumQueued
        lock.unlock()
        if tooFarBehind { return }  // drop to catch up

        guard let output = convert(payload, frames: frameCount), startEngineIfNeeded() else { return }

        lock.lock(); queuedFrames += frameCount; let queued = queuedFrames; lock.unlock()
        player.scheduleBuffer(output) { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.queuedFrames = max(0, self.queuedFrames - frameCount); self.lock.unlock()
        }
        if !player.isPlaying && queued >= startThreshold {
            player.play()
        }
    }

    private func convert(_ payload: Data, frames: Int) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(frames)
        guard let converter,
              let input = AVAudioPCMBuffer(pcmFormat: packetFormat, frameCapacity: frameCount),
              let output = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount),
              let destination = input.int16ChannelData?[0] else { return nil }
        input.frameLength = frameCount
        let byteCount = frames * Int(AudioPacketHeader.channels) * MemoryLayout<Int16>.size
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            memcpy(destination, base.advanced(by: AudioPacketHeader.size), byteCount)
        }
        do {
            try converter.convert(to: output, from: input)
        } catch {
            return nil
        }
        return output
    }

    private func startEngineIfNeeded() -> Bool {
        if engineReady { return true }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
        #endif
        if engine.attachedNodes.contains(player) == false {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        }
        do {
            try engine.start()
        } catch {
            return false
        }
        engineReady = true
        return true
    }
}
