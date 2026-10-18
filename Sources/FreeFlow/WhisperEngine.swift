import Foundation
import whisper

/// Downloads and stores the local Whisper model (OpenAI Whisper large-v3-turbo, ggml format, MIT).
@MainActor
final class WhisperModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = WhisperModel()

    enum State: Equatable { case missing, downloading(Double), ready, failed(String) }
    @Published private(set) var state: State = .missing

    nonisolated static let fileName = "ggml-large-v3-turbo-q5_0.bin"
    nonisolated static let downloadURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    /// Expected size in bytes; a partial or corrupted download is rejected.
    nonisolated static let expectedBytes: Int64 = 574_041_195
    static let sizeLabel = "550 MB"

    nonisolated static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeFlow/models", isDirectory: true).appendingPathComponent(fileName)
    }

    nonisolated static var isReady: Bool {
        ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int64) == expectedBytes
    }

    private var task: URLSessionDownloadTask?

    override init() {
        super.init()
        state = Self.isReady ? .ready : .missing
    }

    func download() {
        guard task == nil, !Self.isReady else { return }
        state = .downloading(0)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        task = session.downloadTask(with: Self.downloadURL)
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .missing
    }

    func delete() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        Task { await WhisperEngine.shared.unload() }
        state = .missing
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData _: Int64, totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
        let expected = total > 0 ? total : Self.expectedBytes
        let progress = Double(written) / Double(expected)
        MainActor.assumeIsolated { self.state = .downloading(progress) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Must move the file before this method returns.
        let dest = Self.fileURL
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dest)
        let moved = (try? fm.moveItem(at: location, to: dest)) != nil
        MainActor.assumeIsolated {
            self.task = nil
            if moved && Self.isReady {
                self.state = .ready
                Task { await WhisperEngine.shared.preload() }
            } else {
                try? fm.removeItem(at: dest)
                self.state = .failed("Download incomplete — please try again")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        MainActor.assumeIsolated {
            self.task = nil
            self.state = .failed(error.localizedDescription)
        }
    }
}

/// Runs whisper.cpp on-device (Metal GPU). The model stays loaded after first use so dictations are fast.
actor WhisperEngine {
    static let shared = WhisperEngine()
    private var ctx: OpaquePointer?

    func preload() {
        guard ctx == nil, WhisperModel.isReady else { return }
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        ctx = whisper_init_from_file_with_params(WhisperModel.fileURL.path, params)
    }

    func unload() {
        if let ctx { whisper_free(ctx) }
        ctx = nil
    }

    /// Transcribes 16 kHz mono Float32 audio. `prompt` biases spelling of names and jargon.
    func transcribe(_ samples: [Float], language: String, prompt: String) throws -> String {
        preload()
        guard let ctx else { throw TranscriberError.server("The Whisper model isn't downloaded yet") }
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.beam_search.beam_size = 3
        params.n_threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.no_timestamps = true
        params.no_context = true
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.temperature = 0

        // Whisper needs at least ~1 s; pad short clips with silence.
        var audio = samples
        if audio.count < 16_000 { audio += [Float](repeating: 0, count: 16_000 - audio.count + 1_600) }
        // Whisper always encodes a 30 s window (audio_ctx 1500). For short clips a smaller window is ~35% faster;
        // below ~1000 it starts looping and loses accuracy (measured on noisy and accented test clips).
        let seconds = Double(audio.count) / 16_000
        if seconds < 18 {
            params.audio_ctx = Int32(max(1000, Int((seconds / 30 * 1500).rounded(.up)) + 128))
        }
        // Loop guard: nobody speaks more than ~5 tokens/s, so cap output to what the clip could contain.
        params.single_segment = true
        params.max_tokens = Int32(seconds * 6) + 16

        let status: Int32 = language.withCString { lang in
            prompt.withCString { promptPtr in
                params.language = lang
                params.initial_prompt = prompt.isEmpty ? nil : promptPtr
                return audio.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }
        }
        guard status == 0 else { throw TranscriberError.server("Whisper failed (\(status))") }

        var parts: [String] = []
        for i in 0..<whisper_full_n_segments(ctx) {
            // Skip segments Whisper itself thinks are silence (where it tends to invent text).
            if whisper_full_get_segment_no_speech_prob(ctx, i) > 0.8 { continue }
            if let c = whisper_full_get_segment_text(ctx, i) { parts.append(String(cString: c)) }
        }
        return Self.clean(parts.joined())
    }

    /// Removes Whisper artifacts: bracketed non-speech tags and stock phrases it emits on silence.
    static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "\\[[^\\]]*\\]|\\([^)]*(music|silence|blank|inaudible|applause|laughs?)[^)]*\\)",
                                          with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hallucinations: Set<String> = ["thank you.", "thanks for watching!", "thank you for watching.", "you", "bye.", "."]
        if hallucinations.contains(t.lowercased()) { return "" }
        return collapseRepeats(t)
    }

    /// Collapses decoding loops ("A. B. A. B. A. B.") to one copy. Text without a loop is returned untouched.
    static func collapseRepeats(_ text: String) -> String {
        let ns = text as NSString
        // Sentence = text up to . ! ? that is followed by a space or the end (so "Node.js" stays intact).
        let re = try! NSRegularExpression(pattern: ".+?[.!?](?=\\s|$)\\s*|.+$")
        let parts = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        let keys = parts.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        var keep: [Int] = []
        var i = 0
        var changed = false
        while i < parts.count {
            var skipped = false
            for k in 1...4 where keep.count >= k && i + k <= parts.count {
                let prev = keep.suffix(k).map { keys[$0] }
                if Array(keys[i..<(i + k)]) == prev { i += k; skipped = true; changed = true; break }
            }
            if !skipped { keep.append(i); i += 1 }
        }
        return changed ? keep.map { parts[$0] }.joined().trimmingCharacters(in: .whitespaces) : text
    }
}
