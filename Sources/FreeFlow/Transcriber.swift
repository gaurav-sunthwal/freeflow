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
    /// Common tech words speech models often mishear ("GitHub" → "gator"), passed as recognition hints.
    /// Short, focused hint list for Whisper; long lists dilute its effect.
    static let whisperCoreTerms = ["FreeFlow", "GitHub", "README.md", "Vercel", "Next.js", "Node.js", "React",
                                   "TypeScript", "API", "JSON", "npm", "repo", "deploy", "app", "storage", "Cursor", "Claude"]

    static let techVocabulary = [
        "GitHub", "README", "README.md", "Markdown", "MD file", "API", "JSON", "YAML", "npm", "Node.js", "React",
        "Next.js", "TypeScript", "JavaScript", "Python", "Swift", "Xcode", "VS Code", "Cursor", "Claude", "ChatGPT",
        "OpenAI", "LLM", "repo", "pull request", "commit", "deploy", "localhost", "frontend", "backend", "UI", "UX",
        "Figma", "Slack", "Notion", "Vercel", "Supabase", "Firebase", "Docker", "Kubernetes", "macOS", "iOS", "Wi-Fi",
    ]

    static func makeSession(settings: Settings, inputFormat: AVAudioFormat) -> TranscriptionSession {
        switch settings.engine {
        case .apple:
            let vocab = settings.dictionary.map(\.word).filter { !$0.isEmpty } + techVocabulary
            return AppleSpeechSession(locale: Locale(identifier: settings.localeID), vocabulary: vocab, inputFormat: inputFormat)
        case .whisperLocal:
            let vocab = settings.dictionary.map(\.word).filter { !$0.isEmpty } + techVocabulary
            let preview = AppleSpeechSession(locale: Locale(identifier: settings.localeID), vocabulary: vocab, inputFormat: inputFormat)
            // Until the model is downloaded, fall back to Apple's engine so dictation keeps working.
            guard WhisperModel.isReady else { return preview }
            let language = Locale(identifier: settings.localeID).language.languageCode?.identifier ?? "en"
            // The user's own words come first; then a short core list.
            let personal = settings.dictionary.map(\.word).filter { !$0.isEmpty }
            let terms = Array((personal + whisperCoreTerms).prefix(30))
            return WhisperLocalSession(preview: preview, language: language,
                                       prompt: "Dictation mentioning " + terms.joined(separator: ", ") + ".")
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

// MARK: - Local Whisper (whisper.cpp)

/// Transcribes while you talk: audio is cut at natural pauses and each finished chunk is sent to local
/// Whisper in the background. When you release the key only the last chunk is left, so long dictations
/// finish about as fast as short ones. Apple's streaming engine still drives the live preview.
final class WhisperLocalSession: TranscriptionSession {
    private let preview: AppleSpeechSession
    private let language: String
    private let prompt: String

    private let lock = NSLock()
    private var samples: [Float] = []
    private var chunkStart = 0          // index where the next chunk begins
    private var lastChunk: Task<String, Error>?
    private var noiseFloor: Float = 0.01
    private var silentFrames = 0
    private var speechFrames = 0
    private var converter: AVAudioConverter?

    private let frame = 480                       // 30 ms at 16 kHz
    // Whisper's encode cost is the same for any clip up to ~18 s, so cut as rarely as possible:
    // most dictations become one clean pass, and only long ones are split (each cut is a seam in the text).
    private let minChunkSeconds = 12.0
    private let maxChunkSeconds = 18.0            // keep within the fast encoder window
    private let pauseFrames = 15                  // 450 ms of silence = a natural break

    var onPartial: ((String) -> Void)? {
        get { preview.onPartial }
        set { preview.onPartial = newValue }
    }

    init(preview: AppleSpeechSession, language: String, prompt: String) {
        self.preview = preview
        self.language = language
        self.prompt = prompt
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        preview.append(buffer)
        guard let mono = to16k(buffer) else { return }
        lock.withLock {
            let start = samples.count
            samples.append(contentsOf: mono)
            scanForPause(from: start - start % frame)
        }
    }

    /// Looks at new 30 ms frames; at a pause after enough speech (or when a chunk gets long), cut a chunk.
    private func scanForPause(from: Int) {
        var i = max(from, chunkStart)
        while i + frame <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += samples[j] * samples[j] }
            let rms = sqrt(sum / Float(frame))
            noiseFloor = rms < noiseFloor ? rms : noiseFloor * 0.999 + rms * 0.001
            if rms < max(0.006, noiseFloor * 3) { silentFrames += 1 } else { silentFrames = 0; speechFrames += 1 }

            let length = Double(i + frame - chunkStart) / 16_000
            let atPause = silentFrames >= pauseFrames && length >= minChunkSeconds && speechFrames > 20
            if atPause || length >= maxChunkSeconds {
                let cut = atPause ? i + frame - (pauseFrames / 2) * frame : i + frame
                submit(Array(samples[chunkStart..<cut]))
                chunkStart = cut
                silentFrames = 0
                speechFrames = 0
            }
            i += frame
        }
    }

    /// Chunks are transcribed in order; each one sees the end of the previous text for context.
    private func submit(_ chunk: [Float]) {
        let previous = lastChunk
        let language = language, prompt = prompt
        lastChunk = Task {
            let before = (try? await previous?.value) ?? ""
            let context = String(before.suffix(200))
            let text = try await WhisperEngine.shared.transcribe(
                chunk, language: language, prompt: context.isEmpty ? prompt : prompt + " " + context)
            return before.isEmpty ? text : before + " " + text
        }
    }

    func finish(samples16k: [Float]) async throws -> String {
        preview.cancel()
        let final: Task<String, Error>? = lock.withLock {
            let rest = Array(samples[min(chunkStart, samples.count)...])
            // Only transcribe the tail if it contains speech.
            // Skip a tail that's just trailing silence (needs ~0.5 s of speech).
            if rest.count > 8_000, speechFrames >= 17 || lastChunk == nil { submit(rest) }
            return lastChunk
        }
        guard let final else { return "" }
        return try await final.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        preview.cancel()
        lock.withLock { lastChunk?.cancel() }
    }

    private func to16k(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let target = AudioRecorder.whisperFormat
        if buffer.format == target, let ch = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
        }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter,
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity:
                AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 64) else { return nil }
        var fed = false
        converter.convert(to: out, error: nil) { _, st in
            if fed { st.pointee = .noDataNow; return nil }
            fed = true; st.pointee = .haveData; return buffer
        }
        guard let ch = out.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
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
