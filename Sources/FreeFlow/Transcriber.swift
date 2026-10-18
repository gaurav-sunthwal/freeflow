import AVFoundation
import Speech

/// A single dictation: audio is appended while recording, then `finish()` returns the text.
protocol TranscriptionSession: AnyObject {
    /// Live text while the user is still speaking (finalized + in-progress words). Called on the main queue.
    var onPartial: ((String) -> Void)? { get set }
    func append(_ buffer: AVAudioPCMBuffer)
    func finish(samples16k: [Float]) async throws -> String
    func cancel()
}

enum TranscriberError: LocalizedError {
    case unsupportedLocale(String)
    case server(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let l): return "On-device speech recognition doesn't support \(l)."
        case .server(let m): return m
        }
    }
}

enum Transcribers {
    static func makeSession(settings: Settings, inputFormat: AVAudioFormat) -> TranscriptionSession {
        switch settings.engine {
        case .apple:
            let vocab = settings.dictionary.map(\.word).filter { !$0.isEmpty }
            return AppleSpeechSession(locale: Locale(identifier: settings.localeID), vocabulary: vocab, inputFormat: inputFormat)
        case .whisperAPI:
            return WhisperAPISession(settings: settings)
        }
    }

    /// Downloads on-device speech assets ahead of time so the first dictation is instant.
    static func prepareAppleAssets(localeID: String) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw TranscriberError.unsupportedLocale(localeID)
        }
        let t = SpeechTranscriber(locale: locale, preset: .transcription)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await req.downloadAndInstall()
        }
    }
}

// MARK: - Apple on-device (SpeechAnalyzer)

/// Streams audio into Apple's on-device SpeechAnalyzer while the user speaks,
/// so the text is ready almost as soon as the hotkey is released.
final class AppleSpeechSession: TranscriptionSession {
    var onPartial: ((String) -> Void)?
    private let lock = NSLock()
    private var pending: [AVAudioPCMBuffer] = []
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<String, Error>?
    private var setupTask: Task<Void, Error>?
    /// Latest live text, returned if finalizing ever stalls.
    private var lastLive = ""
    private var receivedAudio = false

    init(locale: Locale, vocabulary: [String], inputFormat: AVAudioFormat) {
        setupTask = Task { [weak self] in
            guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw TranscriberError.unsupportedLocale(locale.identifier)
            }
            let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                                reportingOptions: [.volatileResults], attributeOptions: [])
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
            }
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: inputFormat)
            let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if !vocabulary.isEmpty {
                let ctx = AnalysisContext()
                ctx.contextualStrings[.general] = vocabulary
                try? await analyzer.setContext(ctx)
            }
            let results = Task<String, Error> { [weak self] in
                var text = ""
                for try await r in transcriber.results {
                    let piece = String(r.text.characters)
                    if r.isFinal { text += piece }
                    let live = r.isFinal ? text : text + piece
                    self?.lock.withLock { self?.lastLive = live }
                    DispatchQueue.main.async { self?.onPartial?(live) }
                }
                return text
            }
            try await analyzer.start(inputSequence: stream)

            guard let self else { return }
            let backlog: [AVAudioPCMBuffer] = self.lock.withLock {
                self.analyzer = analyzer
                self.resultsTask = results
                self.analyzerFormat = format
                if let format, format != inputFormat {
                    self.converter = AVAudioConverter(from: inputFormat, to: format)
                }
                self.continuation = cont
                let b = self.pending
                self.pending.removeAll()
                return b
            }
            backlog.forEach { self.yield($0) }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        // Audio taps reuse buffers, so copy before queueing.
        guard let copy = buffer.copy() as? AVAudioPCMBuffer else { return }
        let ready = lock.withLock { () -> Bool in
            receivedAudio = true
            if continuation == nil { pending.append(copy); return false }
            return true
        }
        if ready { yield(copy) }
    }

    private func yield(_ buffer: AVAudioPCMBuffer) {
        let (cont, conv, fmt) = lock.withLock { (continuation, converter, analyzerFormat) }
        guard let cont else { return }
        if let conv, let fmt {
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * fmt.sampleRate / buffer.format.sampleRate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            if out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
        } else {
            cont.yield(AnalyzerInput(buffer: buffer))
        }
    }

    func finish(samples16k: [Float]) async throws -> String {
        // With no audio at all the analyzer never finishes — don't wait on it.
        guard lock.withLock({ receivedAudio }) else { cancel(); return "" }
        let work = Task { () -> String in
            try await self.setupTask?.value
            let (cont, analyzer, results) = self.lock.withLock { (self.continuation, self.analyzer, self.resultsTask) }
            cont?.finish()
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            return try await results?.value ?? ""
        }
        // Safety net: never leave the user stuck on "Transcribing…".
        let timeout = Task {
            try await Task.sleep(for: .seconds(15))
            work.cancel()
        }
        defer { timeout.cancel() }
        do {
            let text = try await work.value
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            let partial = lock.withLock { lastLive }
            cancel()
            if partial.isEmpty { throw error }
            return partial.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func cancel() {
        setupTask?.cancel()
        let (cont, analyzer, results) = lock.withLock { (continuation, self.analyzer, resultsTask) }
        cont?.finish()
        results?.cancel()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    }
}

// MARK: - OpenAI-compatible Whisper server

/// Sends the recorded clip to any OpenAI-compatible `/audio/transcriptions` endpoint,
/// e.g. a local whisper.cpp server (`whisper-server --inference-path /v1/audio/transcriptions`).
final class WhisperAPISession: TranscriptionSession {
    var onPartial: ((String) -> Void)?
    private let settings: Settings
    private var task: URLSessionDataTask?

    init(settings: Settings) { self.settings = settings }

    func append(_ buffer: AVAudioPCMBuffer) {}

    func finish(samples16k: [Float]) async throws -> String {
        guard samples16k.count > 1600 else { return "" }
        let base = settings.whisperBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/audio/transcriptions") else { throw TranscriberError.server("Invalid Whisper URL") }
        let boundary = "FreeFlow-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !settings.whisperAPIKey.isEmpty {
            req.setValue("Bearer \(settings.whisperAPIKey)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", settings.whisperModel)
        field("response_format", "json")
        let lang = Locale(identifier: settings.localeID).language.languageCode?.identifier ?? ""
        if !lang.isEmpty { field("language", lang) }
        let vocab = settings.dictionary.map(\.word).filter { !$0.isEmpty }
        if !vocab.isEmpty { field("prompt", vocab.joined(separator: ", ")) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(WAV.encode(samples16k))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscriberError.server("Whisper server error: \(String(data: data, encoding: .utf8) ?? "unknown")")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() { task?.cancel() }
}
