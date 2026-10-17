import Foundation
import Combine

enum HotkeyChoice: String, CaseIterable, Identifiable, Codable {
    case fn, rightOption, rightCommand, rightControl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: return "Fn / Globe"
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .rightControl: return "Right Control ⌃"
        }
    }
}

enum TranscriptionEngine: String, CaseIterable, Identifiable, Codable {
    case apple, whisperAPI
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple On-Device (free, private)"
        case .whisperAPI: return "Whisper-compatible server (whisper.cpp, LocalAI, …)"
        }
    }
}

enum CleanupProvider: String, CaseIterable, Identifiable, Codable {
    case apple, openAICompatible, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple Intelligence On-Device (free)"
        case .openAICompatible: return "OpenAI-compatible (Ollama, LM Studio, …)"
        case .off: return "Off (rules only)"
        }
    }
}

enum AIScope: String, CaseIterable, Identifiable, Codable {
    case corrections, full
    var id: String { rawValue }
    var label: String {
        switch self {
        case .corrections: return "Smart — instant rules, AI only for self-corrections"
        case .full: return "Full AI rewrite of every dictation (slower; best with a strong local model)"
        }
    }
}

struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

struct DictionaryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    /// The correct spelling (also fed to the recognizer as a vocabulary hint).
    var word: String
    /// Optional misheard variant that should be replaced with `word`.
    var heardAs: String = ""
}

/// All user preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hotkey: HotkeyChoice { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var engine: TranscriptionEngine { didSet { d.set(engine.rawValue, forKey: "engine") } }
    @Published var localeID: String { didSet { d.set(localeID, forKey: "localeID") } }
    @Published var whisperBaseURL: String { didSet { d.set(whisperBaseURL, forKey: "whisperBaseURL") } }
    @Published var whisperAPIKey: String { didSet { d.set(whisperAPIKey, forKey: "whisperAPIKey") } }
    @Published var whisperModel: String { didSet { d.set(whisperModel, forKey: "whisperModel") } }
    @Published var cleanup: CleanupProvider { didSet { d.set(cleanup.rawValue, forKey: "cleanup") } }
    @Published var aiScope: AIScope { didSet { d.set(aiScope.rawValue, forKey: "aiScope") } }
    @Published var llmBaseURL: String { didSet { d.set(llmBaseURL, forKey: "llmBaseURL") } }
    @Published var llmAPIKey: String { didSet { d.set(llmAPIKey, forKey: "llmAPIKey") } }
    @Published var llmModel: String { didSet { d.set(llmModel, forKey: "llmModel") } }
    @Published var contextAwareStyles: Bool { didSet { d.set(contextAwareStyles, forKey: "contextAwareStyles") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    @Published var restoreClipboard: Bool { didSet { d.set(restoreClipboard, forKey: "restoreClipboard") } }
    @Published var customInstructions: String { didSet { d.set(customInstructions, forKey: "customInstructions") } }
    @Published var dictionary: [DictionaryEntry] { didSet { save(dictionary, "dictionary") } }
    @Published var snippets: [Snippet] { didSet { save(snippets, "snippets") } }

    private init() {
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .fn
        engine = TranscriptionEngine(rawValue: d.string(forKey: "engine") ?? "") ?? .apple
        localeID = d.string(forKey: "localeID") ?? Locale.current.identifier
        whisperBaseURL = d.string(forKey: "whisperBaseURL") ?? "http://127.0.0.1:8080/v1"
        whisperAPIKey = d.string(forKey: "whisperAPIKey") ?? ""
        whisperModel = d.string(forKey: "whisperModel") ?? "whisper-1"
        cleanup = CleanupProvider(rawValue: d.string(forKey: "cleanup") ?? "") ?? .apple
        aiScope = AIScope(rawValue: d.string(forKey: "aiScope") ?? "") ?? .corrections
        llmBaseURL = d.string(forKey: "llmBaseURL") ?? "http://127.0.0.1:11434/v1"
        llmAPIKey = d.string(forKey: "llmAPIKey") ?? ""
        llmModel = d.string(forKey: "llmModel") ?? "llama3.2"
        contextAwareStyles = d.object(forKey: "contextAwareStyles") as? Bool ?? true
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        restoreClipboard = d.object(forKey: "restoreClipboard") as? Bool ?? true
        customInstructions = d.string(forKey: "customInstructions") ?? ""
        dictionary = Settings.load("dictionary") ?? []
        snippets = Settings.load("snippets") ?? []
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        d.set(try? JSONEncoder().encode(v), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
