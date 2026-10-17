import AppKit
import AVFoundation

/// Orchestrates hotkey → record → transcribe → clean up → insert.
@MainActor
final class Coordinator: ObservableObject {
    static let shared = Coordinator()

    enum State { case idle, recording, processing }
    @Published private(set) var state: State = .idle
    @Published var lastError: String?

    let settings = Settings.shared
    let history = HistoryStore.shared
    let hotkeys = HotkeyMonitor()
    let overlay = OverlayController()
    private let recorder = AudioRecorder()
    private var session: TranscriptionSession?
    private var commandMode = false
    private var targetApp: NSRunningApplication?
    private var pendingSelection: Task<String?, Never>?

    func start() {
        hotkeys.isRecording = { [weak self] in
            // Read from the event-tap thread; a stale value is harmless here.
            MainActor.assumeIsolated { self?.state == .recording }
        }
        hotkeys.onEvent = { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
        }
        if !hotkeys.start() {
            lastError = "Grant Accessibility permission so FreeFlow can listen for the hotkey."
        }
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.overlay.model.push(level: level) }
        }
        if settings.engine == .apple {
            let locale = settings.localeID
            Task.detached { try? await Transcribers.prepareAppleAssets(localeID: locale) }
        }
    }

    /// Retry installing the event tap (e.g. after Accessibility was granted).
    func retryHotkeys() {
        if hotkeys.start() { lastError = nil }
    }

    private func handle(_ e: HotkeyMonitor.Event) {
        switch e {
        case .pushStart(let cmd): beginRecording(command: cmd, handsFree: false)
        case .handsFreeStart(let cmd): beginRecording(command: cmd, handsFree: true)
        case .pushEnd, .handsFreeEnd: finishRecording()
        case .cancel: cancelRecording()
        }
    }

    func toggleHandsFree() {
        if state == .recording { finishRecording() } else { beginRecording(command: false, handsFree: true) }
    }

    private func beginRecording(command: Bool, handsFree: Bool) {
        guard state == .idle else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            Permissions.shared.requestMicrophone()
            overlay.set(.message("Microphone access needed"))
            return
        }
        commandMode = command
        targetApp = NSWorkspace.shared.frontmostApplication
        pendingSelection = command ? Task { await TextInserter.selectedText() } : nil
        TextProcessor.prewarm(appBundleID: targetApp?.bundleIdentifier, command: command, settings: settings)

        let s = Transcribers.makeSession(settings: settings, inputFormat: recorder.inputFormat)
        session = s
        recorder.onBuffer = { [weak s] buf in s?.append(buf) }
        do {
            try recorder.start()
        } catch {
            session = nil
            overlay.set(.message("Mic error: \(error.localizedDescription)"))
            hotkeys.reset()
            return
        }
        state = .recording
        overlay.model.commandMode = command
        overlay.model.handsFree = handsFree
        overlay.set(.listening)
        if settings.playSounds { NSSound(named: "Tink")?.play() }
    }

    private func cancelRecording() {
        guard state == .recording else { return }
        recorder.stop()
        recorder.onBuffer = nil
        session?.cancel()
        session = nil
        pendingSelection?.cancel()
        state = .idle
        overlay.set(.hidden)
        hotkeys.reset()
    }

    private func finishRecording() {
        guard state == .recording, let session else { return }
        recorder.stop()
        recorder.onBuffer = nil
        let duration = recorder.duration
        let samples = recorder.takeSamples()
        self.session = nil
        state = .processing
        overlay.set(.processing)
        if settings.playSounds { NSSound(named: "Pop")?.play() }
        hotkeys.reset()

        let command = commandMode
        let app = targetApp
        let selectionTask = pendingSelection
        Task { @MainActor in
            defer { self.state = .idle }
            do {
                let raw = try await session.finish(samples16k: samples)
                guard !raw.isEmpty else { overlay.set(.hidden); return }

                let output: String
                if command {
                    let selection = await selectionTask?.value
                    output = try await TextProcessor.command(instruction: raw, selection: selection, settings: settings)
                } else {
                    output = await TextProcessor.process(raw, appBundleID: app?.bundleIdentifier, settings: settings)
                }
                guard !output.isEmpty else { overlay.set(.hidden); return }

                if let app, app != NSWorkspace.shared.frontmostApplication { app.activate() }
                TextInserter.insert(output, restoreClipboard: settings.restoreClipboard)
                history.add(HistoryItem(date: Date(), raw: raw, text: output,
                                        app: app?.localizedName ?? "Unknown", duration: duration, isCommand: command))
                overlay.set(.hidden)
            } catch {
                lastError = error.localizedDescription
                overlay.set(.message(error.localizedDescription))
            }
        }
    }

    func pasteLast() {
        guard let last = history.items.first else { return }
        TextInserter.insert(last.text, restoreClipboard: settings.restoreClipboard)
    }
}
