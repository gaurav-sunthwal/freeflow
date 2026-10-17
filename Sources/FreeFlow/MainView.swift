import SwiftUI
import AppKit
import ServiceManagement

enum Pane: String, CaseIterable, Identifiable {
    case home = "Home", dictionary = "Dictionary", snippets = "Snippets", style = "Style", settings = "Settings", setup = "Setup"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .style: return "paintbrush"
        case .settings: return "gearshape"
        case .setup: return "checkmark.shield"
        }
    }
}

struct MainView: View {
    @State var pane: Pane
    @ObservedObject var permissions = Permissions.shared

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            Group {
                switch pane {
                case .home: HomeView()
                case .dictionary: DictionaryView()
                case .snippets: SnippetsView()
                case .style: StyleView()
                case .settings: SettingsView()
                case .setup: SetupView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { permissions.refresh() }
    }
}

// MARK: Home

struct HomeView: View {
    @ObservedObject var history = HistoryStore.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var coordinator = Coordinator.shared
    @State private var search = ""

    var filtered: [HistoryItem] {
        search.isEmpty ? history.items : history.items.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to FreeFlow").font(.largeTitle.bold())
            Text("Hold **\(settings.hotkey.label)** and speak in any app. Double-tap for hands-free. Add **Control** for Command Mode.")
                .foregroundStyle(.secondary)
            if let err = coordinator.lastError {
                Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                StatCard(title: "Words dictated", value: "\(history.totalWords)")
                StatCard(title: "Average WPM", value: "\(history.averageWPM)")
                StatCard(title: "Day streak", value: "\(history.streakDays)")
            }
            HStack {
                Text("History").font(.title2.bold())
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                Button("Clear") { history.clear() }.disabled(history.items.isEmpty)
            }
            if filtered.isEmpty {
                Text("Nothing yet — try dictating something.").foregroundStyle(.secondary).padding(.top, 20)
            }
            List(filtered) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text).textSelection(.enabled)
                        Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(item.app)\(item.isCommand ? " · Command" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { copy(item.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                    Button { history.delete(item) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
        .padding(24)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

struct StatCard: View {
    let title: String, value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
    }
}

// MARK: Dictionary

struct DictionaryView: View {
    @ObservedObject var settings = Settings.shared
    @State private var word = ""
    @State private var heardAs = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dictionary").font(.largeTitle.bold())
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
            Text("Snippets").font(.largeTitle.bold())
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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
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
                if settings.engine == .apple {
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
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

// MARK: Setup

struct SetupView: View {
    @ObservedObject var permissions = Permissions.shared
    @ObservedObject var settings = Settings.shared
    let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup").font(.largeTitle.bold())
            Text("FreeFlow needs a few permissions. Nothing ever leaves your Mac.").foregroundStyle(.secondary)
            PermissionRow(title: "Microphone", detail: "To hear you.", granted: permissions.microphone) { permissions.requestMicrophone() }
            PermissionRow(title: "Accessibility", detail: "To detect the hotkey and paste text into apps.", granted: permissions.accessibility) {
                permissions.requestAccessibility()
            }
            PermissionRow(title: "Speech Recognition", detail: "For Apple's on-device speech model.", granted: permissions.speech) { permissions.requestSpeech() }
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
