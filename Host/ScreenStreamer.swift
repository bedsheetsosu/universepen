import Foundation
import ScreenCaptureKit
import CoreMedia
import TafelKit

struct StreamStats: Equatable {
    var fps: Double = 0
    var mbps: Double = 0
    var dropped: Int = 0
}

/// ScreenCaptureKit -> VideoToolbox pipeline. One instance per running stream.
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var encoder: VideoEncoder?
    private let sampleQueue = DispatchQueue(label: "tafel.capture", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "tafel.capture.audio", qos: .userInteractive)
    private var capturesAudio = false
    /// Mac sound as 16-bit PCM (audio queue).
    var onAudio: ((AudioChunk) -> Void)?

    /// Encoded output (callback thread).
    var onEncoded: ((VideoFormat?, VideoFrame) -> Void)?
    /// Return false to skip encoding a captured frame (network backlog).
    var shouldEncode: (() -> Bool)?
    var onStats: ((StreamStats) -> Void)?
    var onStopped: ((Error?) -> Void)?

    private(set) var outputWidth = 0
    private(set) var outputHeight = 0
    private(set) var encoderDescription = ""

    private let statsLock = NSLock()
    private var frameCount = 0
    private var byteCount = 0
    private var dropped = 0
    private var statsTimer: DispatchSourceTimer?

    func start(filter: SCContentFilter, sourceRect: CGRect?, width: Int, height: Int, quality: StreamQuality) async throws {
        let enc = try VideoEncoder(codec: quality.codec, width: width, height: height, quality: quality)
        enc.onOutput = { [weak self] format, frame in
            guard let self else { return }
            self.statsLock.withLock {
                self.frameCount += 1
                self.byteCount += frame.data.count
            }
            self.onEncoded?(format, frame)
        }
        encoder = enc
        outputWidth = width
        outputHeight = height
        encoderDescription = "\(quality.codec.rawValue.uppercased()) \(width)×\(height) · "
            + (enc.isHardware ? "Hardware" : "Software") + (enc.usesLowLatencyRC ? " · Low-Latency-RC" : "")

        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = height
        if let sourceRect { cfg.sourceRect = sourceRect }
        cfg.scalesToFit = true
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(quality.fps, 1)))
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        cfg.queueDepth = 3
        cfg.showsCursor = true
        capturesAudio = quality.audio
        applyAudio(cfg)

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if capturesAudio { try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue) }
        try await s.startCapture()
        stream = s
        startStatsTimer()
    }

    /// Live update of the captured area (region mode sliders) without restarting.
    func updateSourceRect(_ rect: CGRect, width: Int, height: Int, fps: Int) async {
        guard let stream else { return }
        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = height
        cfg.sourceRect = rect
        cfg.scalesToFit = true
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        cfg.queueDepth = 3
        cfg.showsCursor = true
        applyAudio(cfg)
        try? await stream.updateConfiguration(cfg)
    }

    private func applyAudio(_ cfg: SCStreamConfiguration) {
        cfg.capturesAudio = capturesAudio
        cfg.sampleRate = 48_000
        cfg.channelCount = 2
        // Never feed our own process back (we play nothing, but stay safe).
        cfg.excludesCurrentProcessAudio = true
    }

    func requestKeyframe() { encoder?.requestKeyframe() }

    func stop() async {
        statsTimer?.cancel()
        statsTimer = nil
        if let s = stream {
            stream = nil
            try? await s.stopCapture()
        }
        encoder?.invalidate()
        encoder = nil
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sbuf: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            if sbuf.isValid, let chunk = Self.pcm16(sbuf) { onAudio?(chunk) }
            return
        }
        guard type == .screen, sbuf.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sbuf, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw), status == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sbuf) else { return }
        if let shouldEncode, !shouldEncode() {
            statsLock.withLock { dropped += 1 }
            return
        }
        encoder?.encode(pixelBuffer, pts: CMSampleBufferGetPresentationTimeStamp(sbuf),
                        captureTime: Date().timeIntervalSince1970)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped?(error)
    }

    /// Converts a ScreenCaptureKit audio buffer (normally Float32, non-interleaved) into
    /// interleaved signed 16-bit PCM.
    static func pcm16(_ sbuf: CMSampleBuffer) -> AudioChunk? {
        guard let desc = CMSampleBufferGetFormatDescription(sbuf),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return nil }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(asbd.mChannelsPerFrame)
        guard asbd.mFormatID == kAudioFormatLinearPCM, channels > 0, channels <= 8 else { return nil }
        let frames = CMSampleBufferGetNumSamples(sbuf)
        guard frames > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sbuf, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil,
                                                                bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                                flags: 0, blockBufferOut: nil)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sbuf, bufferListSizeNeededOut: nil, bufferListOut: abl, bufferListSize: sizeNeeded,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer) == noErr else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(abl)

        // Output is always stereo (mono is duplicated, extra channels dropped).
        let outCh = 2
        var out = Data(count: frames * outCh * 2)
        out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
            let o = dst.bindMemory(to: Int16.self)
            func sample(_ frame: Int, _ ch: Int) -> Float {
                let c = min(ch, channels - 1)
                if nonInterleaved {
                    guard c < buffers.count, let p = buffers[c].mData else { return 0 }
                    return isFloat ? p.assumingMemoryBound(to: Float.self)[frame]
                                   : Float(p.assumingMemoryBound(to: Int16.self)[frame]) / 32768
                } else {
                    guard let p = buffers[0].mData else { return 0 }
                    let i = frame * channels + c
                    return isFloat ? p.assumingMemoryBound(to: Float.self)[i]
                                   : Float(p.assumingMemoryBound(to: Int16.self)[i]) / 32768
                }
            }
            for f in 0..<frames {
                for ch in 0..<outCh {
                    let v = max(-1, min(1, sample(f, ch)))
                    o[f * outCh + ch] = Int16(v * 32767).littleEndian
                }
            }
        }
        return AudioChunk(sampleRate: Int(asbd.mSampleRate), channels: outCh,
                          captureTime: Date().timeIntervalSince1970, samples: out)
    }

    private func startStatsTimer() {
        let t = DispatchSource.makeTimerSource(queue: sampleQueue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let s: StreamStats = self.statsLock.withLock {
                defer { self.frameCount = 0; self.byteCount = 0 }
                return StreamStats(fps: Double(self.frameCount), mbps: Double(self.byteCount) * 8 / 1_000_000, dropped: self.dropped)
            }
            self.onStats?(s)
        }
        t.resume()
        statsTimer = t
    }
}
