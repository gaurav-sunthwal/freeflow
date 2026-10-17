import AVFoundation

/// Captures microphone audio with AVAudioEngine and hands buffers to a consumer.
/// Also keeps a 16 kHz mono Float32 copy for engines that need the whole clip (Whisper API).
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples16k: [Float] = []
    private(set) var startedAt = Date()

    /// Called on the audio thread with each captured buffer in the input's native format.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Normalised 0…1 input level, called on the audio thread.
    var onLevel: ((Float) -> Void)?

    static let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start() throws {
        lock.withLock { samples16k.removeAll(keepingCapacity: true) }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: format, to: Self.whisperFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        startedAt = Date()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    var duration: TimeInterval { Date().timeIntervalSince(startedAt) }

    func takeSamples() -> [Float] { lock.withLock { samples16k } }

    private func process(_ buffer: AVAudioPCMBuffer) {
        onBuffer?(buffer)

        if let ch = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            onLevel?(min(1, rms * 12))
        }

        guard let converter else { return }
        let ratio = Self.whisperFormat.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.whisperFormat, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let ch = out.floatChannelData?[0], out.frameLength > 0 {
            let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
            lock.withLock { samples16k.append(contentsOf: chunk) }
        }
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
