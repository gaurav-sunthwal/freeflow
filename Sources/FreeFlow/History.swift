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
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var items: [HistoryItem] = []

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
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        if items.count > 2000 { items.removeLast(items.count - 2000) }
        save()
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() { items = []; save() }

    private func save() {
        let snapshot = items
        let url = url
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    var totalWords: Int { items.reduce(0) { $0 + $1.wordCount } }

    var averageWPM: Int {
        let timed = items.filter { $0.duration > 1 }
        let minutes = timed.reduce(0) { $0 + $1.duration } / 60
        guard minutes > 0 else { return 0 }
        return Int(Double(timed.reduce(0) { $0 + $1.wordCount }) / minutes)
    }

    /// Consecutive days (ending today or yesterday) with at least one dictation.
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(items.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }
}
