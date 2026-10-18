import Foundation

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var raw: String
    var text: String
    var app: String
    var duration: TimeInterval
    var isCommand: Bool = false

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// Local, on-disk dictation history (~/Library/Application Support/FreeFlow/history.json).
/// Entries older than the retention period (default 15 days) are deleted automatically.
/// Lifetime stats (words, speaking time, active days) are kept separately so they survive cleanup.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var lifetimeWords = 0
    private var lifetimeSeconds: Double = 0
    private var lifetimeTimedWords = 0
    /// Words dictated per day ("yyyy-MM-dd"), for the streak and the activity heatmap. Kept ~400 days.
    @Published private(set) var dayWords: [String: Int] = [:]
    @Published private(set) var lifetimeDictations = 0
    /// Dictations and speaking seconds per day, for the heatmap tooltip.
    private(set) var dayCounts: [String: Int] = [:]
    private(set) var daySeconds: [String: Double] = [:]
    private var activeDays: Set<String> { Set(dayWords.keys) }

    private let d = UserDefaults.standard
    private let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private var cleanupTimer: Timer?

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
        }
        loadLifetimeStats()
        pruneExpired()
        // Re-check a few times a day so a Mac that's never restarted still cleans up.
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.pruneExpired()
        }
    }

    // MARK: Lifetime stats

    private func loadLifetimeStats() {
        if d.object(forKey: "lifetimeWords") == nil {
            // First run with lifetime stats: seed them from the existing history.
            for item in items { count(item) }
            saveLifetimeStats()
        } else {
            lifetimeWords = d.integer(forKey: "lifetimeWords")
            lifetimeSeconds = d.double(forKey: "lifetimeSeconds")
            lifetimeTimedWords = d.integer(forKey: "lifetimeTimedWords")
            lifetimeDictations = d.integer(forKey: "lifetimeDictations")
            dayCounts = d.dictionary(forKey: "dayCounts") as? [String: Int] ?? [:]
            daySeconds = d.dictionary(forKey: "daySeconds") as? [String: Double] ?? [:]
            if dayCounts.isEmpty {
                // Rebuild from the history we still have.
                for item in items {
                    let key = dayFormat.string(from: item.date)
                    dayCounts[key, default: 0] += 1
                    daySeconds[key, default: 0] += item.duration
                }
            }
            if let saved = d.dictionary(forKey: "dayWords") as? [String: Int] {
                dayWords = saved
                // Lifetime words can never be less than the words in the daily log.
                lifetimeWords = max(lifetimeWords, saved.values.reduce(0, +))
            } else {
                // Older versions only stored which days were active; rebuild counts from history.
                for day in d.stringArray(forKey: "activeDays") ?? [] { dayWords[day] = 1 }
                for item in items { dayWords[dayFormat.string(from: item.date), default: 0] += item.wordCount }
                if lifetimeDictations == 0 { lifetimeDictations = items.count }
                lifetimeWords = max(lifetimeWords, dayWords.values.reduce(0, +))
                saveLifetimeStats()
            }
        }
    }

    private func count(_ item: HistoryItem) {
        lifetimeWords += item.wordCount
        if item.duration > 1 {
            lifetimeSeconds += item.duration
            lifetimeTimedWords += item.wordCount
        }
        let key = dayFormat.string(from: item.date)
        dayWords[key, default: 0] += item.wordCount
        dayCounts[key, default: 0] += 1
        daySeconds[key, default: 0] += item.duration
        lifetimeDictations += 1
    }

    private func saveLifetimeStats() {
        // Streaks only need recent days; keep the set small.
        let cutoff = dayFormat.string(from: Date().addingTimeInterval(-400 * 86_400))
        dayWords = dayWords.filter { $0.key >= cutoff }
        dayCounts = dayCounts.filter { $0.key >= cutoff }
        daySeconds = daySeconds.filter { $0.key >= cutoff }
        d.set(dayCounts, forKey: "dayCounts")
        d.set(daySeconds, forKey: "daySeconds")
        d.set(lifetimeWords, forKey: "lifetimeWords")
        d.set(lifetimeDictations, forKey: "lifetimeDictations")
        d.set(dayWords, forKey: "dayWords")
        d.set(lifetimeSeconds, forKey: "lifetimeSeconds")
        d.set(lifetimeTimedWords, forKey: "lifetimeTimedWords")
    }

    // MARK: Backup (aggregates only — never dictated text)

    func backupSnapshot() -> [String: Any] {
        let settings = Settings.shared
        let fillers = SpeechInsights(items: items).fillers.reduce(into: [String: Int]()) { $0[$1.word] = $1.count }
        return [
            "version": 1,
            "lifetimeWords": lifetimeWords, "lifetimeSeconds": lifetimeSeconds,
            "lifetimeTimedWords": lifetimeTimedWords, "lifetimeDictations": lifetimeDictations,
            "dayWords": dayWords, "dayCounts": dayCounts, "daySeconds": daySeconds,
            "fillerCounts": fillers, "dailyGoal": settings.dailyGoal, "autoRemoveFillers": settings.autoRemoveFillers,
            "dictionary": settings.dictionary.map { ["word": $0.word, "heardAs": $0.heardAs] },
            "snippets": settings.snippets.map { ["trigger": $0.trigger, "expansion": $0.expansion] },
        ]
    }

    /// Merges a backup into local stats, keeping the larger value so nothing is ever lost or double counted.
    func mergeBackup(_ b: [String: Any]) {
        lifetimeWords = max(lifetimeWords, b["lifetimeWords"] as? Int ?? 0)
        lifetimeSeconds = max(lifetimeSeconds, b["lifetimeSeconds"] as? Double ?? 0)
        lifetimeTimedWords = max(lifetimeTimedWords, b["lifetimeTimedWords"] as? Int ?? 0)
        lifetimeDictations = max(lifetimeDictations, b["lifetimeDictations"] as? Int ?? 0)
        for (k, v) in b["dayWords"] as? [String: Int] ?? [:] { dayWords[k] = max(dayWords[k] ?? 0, v) }
        for (k, v) in b["dayCounts"] as? [String: Int] ?? [:] { dayCounts[k] = max(dayCounts[k] ?? 0, v) }
        for (k, v) in b["daySeconds"] as? [String: Double] ?? [:] { daySeconds[k] = max(daySeconds[k] ?? 0, v) }
        let settings = Settings.shared
        if let goal = b["dailyGoal"] as? Int, settings.dailyGoal == 500 { settings.dailyGoal = goal }
        for f in b["autoRemoveFillers"] as? [String] ?? [] where !settings.autoRemoveFillers.contains(f) {
            settings.autoRemoveFillers.append(f)
        }
        for e in b["dictionary"] as? [[String: String]] ?? [] {
            if let w = e["word"], !w.isEmpty, !settings.dictionary.contains(where: { $0.word == w }) {
                settings.dictionary.append(DictionaryEntry(word: w, heardAs: e["heardAs"] ?? ""))
            }
        }
        for e in b["snippets"] as? [[String: String]] ?? [] {
            if let t = e["trigger"], let x = e["expansion"], !settings.snippets.contains(where: { $0.trigger == t }) {
                settings.snippets.append(Snippet(trigger: t, expansion: x))
            }
        }
        saveLifetimeStats()
    }

    // MARK: Editing

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        count(item)
        saveLifetimeStats()
        pruneExpired(save: false)
        save()
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() { items = []; save() }

    /// Deletes history older than the retention setting (0 = keep forever).
    func pruneExpired(save shouldSave: Bool = true) {
        let days = Settings.shared.historyRetentionDays
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let before = items.count
        items.removeAll { $0.date < cutoff }
        if items.count > 5000 { items.removeLast(items.count - 5000) }
        if shouldSave && items.count != before { save() }
    }

    private func save() {
        let snapshot = items
        let url = url
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: Stats (lifetime, unaffected by cleanup)

    var totalWords: Int { lifetimeWords }

    var averageWPM: Int {
        let minutes = lifetimeSeconds / 60
        guard minutes > 0 else { return 0 }
        return Int(Double(lifetimeTimedWords) / minutes)
    }

    func words(on date: Date) -> Int { dayWords[dayFormat.string(from: date)] ?? 0 }
    func dictations(on date: Date) -> Int { dayCounts[dayFormat.string(from: date)] ?? 0 }
    func seconds(on date: Date) -> Double { daySeconds[dayFormat.string(from: date)] ?? 0 }

    var wordsToday: Int { words(on: Date()) }

    /// Minutes saved versus typing at an average 40 words per minute.
    var minutesSaved: Int {
        max(0, Int(Double(lifetimeWords) / 40 - lifetimeSeconds / 60))
    }

    /// Longest run of consecutive active days in the stored window.
    var bestStreak: Int {
        let cal = Calendar.current
        let days = dayWords.keys.compactMap { dayFormat.date(from: $0) }.sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let p = previous, cal.dateComponents([.day], from: p, to: day).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// Apps dictated into most often (from the retained history).
    var topApps: [(name: String, words: Int)] {
        var totals: [String: Int] = [:]
        for item in items where !item.isCommand { totals[item.app, default: 0] += item.wordCount }
        return totals.sorted { $0.value > $1.value }.prefix(4).map { ($0.key, $0.value) }
    }

    /// Consecutive days (ending today or yesterday) with at least one dictation.
    var streakDays: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if !activeDays.contains(dayFormat.string(from: day)) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while activeDays.contains(dayFormat.string(from: day)) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }
}
