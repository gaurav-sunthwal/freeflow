import SwiftUI
import AppKit
import ServiceManagement

enum Pane: String, CaseIterable, Identifiable {
    case home = "Home", insights = "Insights", dictionary = "Dictionary", snippets = "Snippets", style = "Style", account = "Account", settings = "Settings", setup = "Setup"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .style: return "wand.and.stars"
        case .account: return "person.crop.circle"
        case .settings: return "gearshape"
        case .setup: return "checkmark.shield"
        }
    }
    static let main: [Pane] = [.home, .insights, .dictionary, .snippets, .style]
    static let system: [Pane] = [.account, .settings, .setup]
}

struct MainView: View {
    @State var pane: Pane
    @ObservedObject var permissions = Permissions.shared
    @ObservedObject var history = HistoryStore.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section {
                    ForEach(Pane.main) { p in Label(p.rawValue, systemImage: p.icon).tag(p) }
                }
                Section {
                    ForEach(Pane.system) { p in
                        Label {
                            HStack {
                                Text(p.rawValue)
                                if p == .setup && !permissions.allGranted {
                                    Spacer()
                                    Circle().fill(.orange).frame(width: 7, height: 7)
                                }
                            }
                        } icon: { Image(systemName: p.icon) }
                        .tag(p)
                    }
                }
            }
            .safeAreaInset(edge: .top) { brand }
            .safeAreaInset(edge: .bottom) { streakBadge }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 230)
        } detail: {
            Group {
                switch pane {
                case .home: HomeView(openAccount: { pane = .account })
                case .insights: InsightsView()
                case .dictionary: DictionaryView()
                case .snippets: SnippetsView()
                case .style: StyleView()
                case .account: AccountView()
                case .settings: SettingsView()
                case .setup: SetupView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear { permissions.refresh() }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
            Text("FreeFlow").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
    }

    private var streakBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill").foregroundStyle(history.streakDays > 0 ? Theme.flame : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(history.streakDays)-day streak").font(.callout.weight(.semibold))
                Text(history.wordsToday > 0 ? "Done for today ✓" : "Dictate today to keep it")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .padding(12)
    }
}

// MARK: Dictionary

struct DictionaryView: View {
    @ObservedObject var settings = Settings.shared
    @State private var word = ""
    @State private var heardAs = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Dictionary")
            Text("Teach FreeFlow names, jargon and acronyms. Words are used as recognition hints; add a \"heard as\" spelling to auto-correct a common mistake.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Word (e.g. Kubernetes)", text: $word)
                TextField("Heard as (optional, e.g. cooper netties)", text: $heardAs)
                Button("Add") {
                    settings.dictionary.append(DictionaryEntry(word: word.trimmingCharacters(in: .whitespaces),
                                                               heardAs: heardAs.trimmingCharacters(in: .whitespaces)))
                    word = ""; heardAs = ""
                }.disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
            }.textFieldStyle(.roundedBorder)
            List {
                ForEach(settings.dictionary) { e in
                    HStack {
                        Text(e.word).bold()
                        if !e.heardAs.isEmpty { Text("← \(e.heardAs)").foregroundStyle(.secondary) }
                        Spacer()
                        Button { settings.dictionary.removeAll { $0.id == e.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }.listStyle(.inset)
        }.padding(24)
    }
}

// MARK: Snippets

struct SnippetsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Snippets")
            Text("Say a short cue and FreeFlow types the full text — e.g. say \"my calendar link\" to insert your booking URL.")
                .foregroundStyle(.secondary)
            TextField("Cue phrase (e.g. my calendar link)", text: $trigger).textFieldStyle(.roundedBorder)
            TextEditor(text: $expansion).font(.body).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Button("Add snippet") {
                settings.snippets.append(Snippet(trigger: trigger.trimmingCharacters(in: .whitespaces), expansion: expansion))
                trigger = ""; expansion = ""
            }.disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            List {
                ForEach(settings.snippets) { s in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text("“\(s.trigger)”").bold()
                            Text(s.expansion).foregroundStyle(.secondary).lineLimit(3)
                        }
                        Spacer()
                        Button { settings.snippets.removeAll { $0.id == s.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }.listStyle(.inset)
        }.padding(24)
    }
}

// MARK: Style

struct StyleView: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        Form {
            Section {
                Picker("AI cleanup", selection: $settings.cleanup) {
                    ForEach(CleanupProvider.allCases) { Text($0.label).tag($0) }
                }
                Picker("AI scope", selection: $settings.aiScope) {
                    ForEach(AIScope.allCases) { Text($0.label).tag($0) }
                }.disabled(settings.cleanup == .off)
                Toggle("Adapt style to the app I'm typing in (email, chat, code, docs)", isOn: $settings.contextAwareStyles)
            } header: { Text("Formatting") } footer: {
                Text("Always on: filler-word removal, \"new line\" / \"new paragraph\", \"scratch that\". Smart mode asks the AI only when you correct yourself (\"…actually no, make it 3pm\"). Full mode also adapts tone to the app you're in. Everything runs on your Mac.")
            }
            if settings.cleanup == .openAICompatible {
                Section("OpenAI-compatible endpoint") {
                    TextField("Base URL", text: $settings.llmBaseURL)
                    TextField("Model", text: $settings.llmModel)
                    SecureField("API key (optional)", text: $settings.llmAPIKey)
                    Text("Ollama: http://127.0.0.1:11434/v1 · LM Studio: http://127.0.0.1:1234/v1").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Personal instructions") {
                TextEditor(text: $settings.customInstructions).frame(height: 90)
                Text("e.g. \"Use British spelling. Never use exclamation marks.\"").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

// MARK: Settings

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var whisperModel = WhisperModel.shared
    @ObservedObject var updater = Updater.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var mics: [AudioInputDevice] = []
    @State private var assetStatus = ""

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Push-to-talk key", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) }
                }
                Text("Hold to dictate · double-tap for hands-free · hold Control as well for Command Mode · Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Speech recognition") {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(TranscriptionEngine.allCases) { Text($0.label).tag($0) }
                }
                TextField("Language (locale ID, e.g. en_US, de_DE)", text: $settings.localeID)
                if settings.engine == .whisperLocal {
                    switch whisperModel.state {
                    case .ready:
                        HStack {
                            Label("Whisper model ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Delete model", role: .destructive) { whisperModel.delete() }
                        }
                    case .downloading(let p):
                        HStack {
                            ProgressView(value: p)
                            Text("\(Int(p * 100))%").monospacedDigit().foregroundStyle(.secondary)
                            Button("Cancel") { whisperModel.cancel() }
                        }
                    case .missing, .failed:
                        HStack {
                            Button("Download Whisper model (\(WhisperModel.sizeLabel))") { whisperModel.download() }
                            if case .failed(let m) = whisperModel.state { Text(m).foregroundStyle(.red) }
                        }
                        Text("One-time download, then works offline. Until it's ready, FreeFlow uses Apple's engine.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if settings.engine == .apple {
                    HStack {
                        Button("Download language model") {
                            assetStatus = "Downloading…"
                            let id = settings.localeID
                            Task {
                                do { try await Transcribers.prepareAppleAssets(localeID: id); assetStatus = "Ready ✓" }
                                catch { assetStatus = error.localizedDescription }
                            }
                        }
                        Text(assetStatus).foregroundStyle(.secondary)
                    }
                } else {
                    TextField("Base URL", text: $settings.whisperBaseURL)
                    TextField("Model", text: $settings.whisperModel)
                    SecureField("API key (optional)", text: $settings.whisperAPIKey)
                    Text("Run whisper.cpp locally: whisper-server -m ggml-large-v3-turbo.bin --port 8080 --inference-path /v1/audio/transcriptions")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Section {
                Picker("Microphone", selection: $settings.micDevice) {
                    Text("Automatic (current system mic)").tag("")
                    ForEach(mics) { Text($0.name).tag($0.uid) }
                }
                Toggle("Mute other audio while dictating", isOn: $settings.muteWhileDictating)
                Toggle("Show live preview in the Flow bar", isOn: $settings.livePreview)
            } header: { Text("Microphone") } footer: {
                Text("A headset or earbud mic is closest to your mouth and works best in noisy places. Pick your Mac's built-in mic instead if you'd rather keep Bluetooth headphones in full audio quality while dictating.")
            }
            .onAppear { mics = AudioDevices.inputDevices() }
            Section {
                Picker("Keep history for", selection: $settings.historyRetentionDays) {
                    Text("7 days").tag(7)
                    Text("15 days").tag(15)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }
                .onChange(of: settings.historyRetentionDays) { HistoryStore.shared.pruneExpired() }
                Button("Delete all history now", role: .destructive) { HistoryStore.shared.clear() }
            } header: { Text("Privacy & storage") } footer: {
                Text("Older dictations are deleted automatically. Your stats are kept. Everything stays on this Mac.")
            }
            Section("Updates") {
                Toggle("Install updates automatically", isOn: $settings.autoUpdate)
                HStack {
                    Text("Version \(updater.currentVersion)")
                    Spacer()
                    Text(updateStatus).foregroundStyle(.secondary)
                    Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.status == .checking)
                }
            }
            Section("Behaviour") {
                Toggle("Launch FreeFlow at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {}
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                Toggle("Play sounds", isOn: $settings.playSounds)
                Toggle("Restore clipboard after pasting", isOn: $settings.restoreClipboard)
            }
            Section {
                HStack(spacing: 16) {
                    Link("Website", destination: Links.website)
                    Link("Help", destination: Links.help)
                    Link("Privacy", destination: Links.privacy)
                    Link("GitHub", destination: Links.github)
                    Link("Report an issue", destination: Links.issues)
                }
            } header: { Text("About") } footer: {
                Text("FreeFlow \(updater.currentVersion) · Free and open source (MIT)")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

extension SettingsView {
    var updateStatus: String {
        switch updater.status {
        case .idle: return ""
        case .checking: return "Checking…"
        case .upToDate: return "Up to date ✓"
        case .building(let v): return "Preparing \(v)…"
        case .ready(let v): return "\(v) installs when you stop dictating"
        case .failed(let m): return m
        }
    }
}

// MARK: Setup

struct SetupView: View {
    @ObservedObject var permissions = Permissions.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var whisperModel = WhisperModel.shared
    let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Setup")
            Text("FreeFlow needs a few permissions. Nothing ever leaves your Mac.").foregroundStyle(.secondary)
            PermissionRow(title: "Microphone", detail: "To hear you.", granted: permissions.microphone) { permissions.requestMicrophone() }
            PermissionRow(title: "Accessibility", detail: "To detect the hotkey and paste text into apps.", granted: permissions.accessibility) {
                permissions.requestAccessibility()
            }
            PermissionRow(title: "Speech Recognition", detail: "For Apple's on-device speech model.", granted: permissions.speech) { permissions.requestSpeech() }
            if settings.engine == .whisperLocal {
                switch whisperModel.state {
                case .ready:
                    PermissionRow(title: "Whisper model", detail: "Most accurate speech recognition, on-device.", granted: true) {}
                case .downloading(let p):
                    HStack {
                        Text("Downloading Whisper model…").bold()
                        ProgressView(value: p)
                        Text("\(Int(p * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
                case .missing, .failed:
                    PermissionRow(title: "Whisper model (\(WhisperModel.sizeLabel), recommended)",
                                  detail: "Much better with accents, tech words and background noise. One-time download; works offline.",
                                  granted: false) { whisperModel.download() }
                }
            }
            if settings.hotkey == .fn {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Using the Fn / Globe key").bold()
                        Text("In System Settings → Keyboard, set “Press 🌐 key to” → “Do Nothing” so macOS doesn't open the emoji picker or system dictation.")
                            .foregroundStyle(.secondary)
                        Button("Open Keyboard Settings") { permissions.openKeyboardSettings() }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }
        .padding(24)
        .onReceive(timer) { _ in
            let had = permissions.accessibility
            permissions.refresh()
            if !had && permissions.accessibility { Coordinator.shared.retryHotkeys() }
        }
    }
}

struct PermissionRow: View {
    let title: String, detail: String, granted: Bool, action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .green : .secondary).font(.title2)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant", action: action) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
