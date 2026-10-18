import AVFoundation
import CoreAudio

/// Captures microphone audio and hands 16 kHz mono Float32 buffers to a consumer.
///
/// Uses AVCaptureSession rather than AVAudioEngine: AVAudioEngine always opens the *default* input first,
/// so with Bluetooth headphones it flips them into low-quality "call" audio even when another mic is chosen.
/// A capture session opens only the requested device and is fully torn down after each dictation.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "FreeFlow.audio")
    private let lock = NSLock()
    private var samples16k: [Float] = []
    private var converter: AVAudioConverter?
    private(set) var startedAt = Date()
    private(set) var peakLevel: Float = 0

    /// Called on the audio queue with each captured buffer (16 kHz mono Float32).
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Normalised 0…1 input level, called on the audio queue.
    var onLevel: ((Float) -> Void)?

    /// Format of the buffers passed to `onBuffer`.
    var format: AVAudioFormat { Self.whisperFormat }

    /// Starts recording from the device with the given CoreAudio UID (nil = system default).
    func start(deviceUID: String?) throws {
        stop()
        let device = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
        guard let device else {
            throw NSError(domain: "FreeFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone available"])
        }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "FreeFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: "Can't use \(device.localizedName)"])
        }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.whisperFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "FreeFlow", code: 3, userInfo: [NSLocalizedDescriptionKey: "Can't capture audio"])
        }
        session.addOutput(output)

        lock.withLock { samples16k.removeAll(keepingCapacity: true) }
        peakLevel = 0
        converter = nil
        self.session = session
        startedAt = Date()
        // startRunning blocks while the device spins up; keep the hotkey responsive.
        queue.async { session.startRunning() }
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        queue.async {
            session.stopRunning()
            for o in session.outputs { (o as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil) }
        }
        // Wait for in-flight buffers so callers see every sample.
        queue.sync {}
    }

    var duration: TimeInterval { Date().timeIntervalSince(startedAt) }

    func takeSamples() -> [Float] { lock.withLock { samples16k } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard session != nil, let buffer = pcmBuffer(from: sampleBuffer) else { return }
        onBuffer?(buffer)
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let level = min(1, sqrt(sum / Float(max(n, 1))) * 12)
        if level > peakLevel { peakLevel = level }
        onLevel?(level)
        let chunk = Array(UnsafeBufferPointer(start: ch, count: n))
        lock.withLock { samples16k.append(contentsOf: chunk) }
    }

    /// Copies a capture sample buffer into an AVAudioPCMBuffer, converting to 16 kHz mono if the device ignored our settings.
    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let srcFormat = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let src = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frames) else { return nil }
        src.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                           into: src.mutableAudioBufferList) == noErr else { return nil }
        if srcFormat == Self.whisperFormat { return src }

        if converter == nil || converter?.inputFormat != srcFormat {
            converter = AVAudioConverter(from: srcFormat, to: Self.whisperFormat)
        }
        guard let converter else { return nil }
        let cap = AVAudioFrameCount(Double(frames) * Self.whisperFormat.sampleRate / srcFormat.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.whisperFormat, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return src
        }
        return out.frameLength > 0 ? out : nil
    }
}

enum WAV {
    /// Encodes 16 kHz mono Float32 samples as a 16-bit PCM WAV file.
    static func encode(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataSize)
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataSize)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            u16(UInt16(bitPattern: v))
        }
        return d
    }
}
