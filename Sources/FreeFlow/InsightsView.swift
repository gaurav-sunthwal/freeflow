import SwiftUI
import Charts

/// Personal speaking insights computed from the user's own (on-device) history.
struct SpeechInsights {
    struct Filler: Identifiable { let word: String; let count: Int; var id: String { word } }
    struct Phrase: Identifiable { let text: String; let count: Int; var id: String { text } }
    struct DaySpeed: Identifiable { let day: Date; let wpm: Int; var id: Date { day } }
    struct HourWords: Identifiable { let hour: Int; let words: Int; var id: Int { hour } }

    var fillers: [Filler] = []
    var fillersPer100 = 0.0
    /// Change in fillers per 100 words, this week vs. the week before (negative = improving).
    var fillerTrend: Double?
    var phrases: [Phrase] = []
    var speed: [DaySpeed] = []
    var hours: [HourWords] = []
    var uniqueWords = 0
    var questions = 0

    static let fillerWords = ["um", "uh", "like", "so", "right", "actually", "basically", "just", "really",
                              "okay", "you know", "i mean", "kind of", "sort of", "literally", "i guess"]
    private static let stopStarts: Set<String> = ["the", "a", "an", "of", "to", "and", "in", "is", "it", "that", "this", "on", "for"]

    init() {}

    init(items: [HistoryItem]) {
        let dictations = items.filter { !$0.isCommand }
        let cal = Calendar.current

        // Fillers are counted in what was actually said (before cleanup).
        func fillerCounts(_ list: [HistoryItem]) -> [String: Int] {
            var out: [String: Int] = [:]
            for item in list {
                // " so i was like really ... " — padded so every filler can be matched as " word ".
                let normalized = " " + item.raw.lowercased()
                    .replacingOccurrences(of: "[^a-z' ]", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: " +", with: " ", options: .regularExpression) + " "
                for f in Self.fillerWords {
                    let n = normalized.components(separatedBy: " \(f) ").count - 1
                    if n > 0 { out[f, default: 0] += n }
                }
            }
            return out
        }
        func words(_ list: [HistoryItem]) -> Int { list.reduce(0) { $0 + $1.raw.split(whereSeparator: \.isWhitespace).count } }

        let counts = fillerCounts(dictations)
        fillers = counts.map { Filler(word: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        let total = words(dictations)
        fillersPer100 = total > 0 ? Double(counts.values.reduce(0, +)) * 100 / Double(total) : 0

        let weekAgo = Date().addingTimeInterval(-7 * 86_400), twoWeeksAgo = Date().addingTimeInterval(-14 * 86_400)
        let thisWeek = dictations.filter { $0.date >= weekAgo }
        let lastWeek = dictations.filter { $0.date < weekAgo && $0.date >= twoWeeksAgo }
        if words(thisWeek) > 50, words(lastWeek) > 50 {
            let a = Double(fillerCounts(thisWeek).values.reduce(0, +)) * 100 / Double(words(thisWeek))
            let b = Double(fillerCounts(lastWeek).values.reduce(0, +)) * 100 / Double(words(lastWeek))
            fillerTrend = b > 0 ? (a - b) / b : nil
        }

        // Catchphrases: repeated 3–4 word sequences.
        var grams: [String: Int] = [:]
        var vocab = Set<String>()
        for item in dictations {
            let w = item.text.lowercased().replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression)
                .split(separator: " ").map(String.init)
            vocab.formUnion(w)
            for n in [3, 4] where w.count >= n {
                for i in 0...(w.count - n) where !Self.stopStarts.contains(w[i]) {
                    grams[w[i..<(i + n)].joined(separator: " "), default: 0] += 1
                }
            }
            questions += item.text.filter { $0 == "?" }.count
        }
        uniqueWords = vocab.count
        let ranked = grams.filter { $0.value >= 3 }.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.count > $1.key.count) }
        var picked: [Phrase] = []
        for (text, count) in ranked where !picked.contains(where: { $0.text.contains(text) || text.contains($0.text) }) {
            picked.append(Phrase(text: text, count: count))
            if picked.count == 6 { break }
        }
        phrases = picked

        // Speaking speed per day.
        var perDay: [Date: (words: Int, seconds: Double)] = [:]
        for item in dictations where item.duration > 2 {
            let day = cal.startOfDay(for: item.date)
            perDay[day, default: (0, 0)].words += item.wordCount
            perDay[day, default: (0, 0)].seconds += item.duration
        }
        speed = perDay.map { DaySpeed(day: $0.key, wpm: Int(Double($0.value.words) / ($0.value.seconds / 60))) }
            .sorted { $0.day < $1.day }

        // Words by hour of day.
        var byHour = [Int](repeating: 0, count: 24)
        for item in dictations { byHour[cal.component(.hour, from: item.date)] += item.wordCount }
        hours = byHour.enumerated().map { HourWords(hour: $0.offset, words: $0.element) }
    }
}

struct InsightsView: View {
    @ObservedObject var history = HistoryStore.shared
    @ObservedObject var settings = Settings.shared
    @State private var insights = SpeechInsights()
    @State private var selectedDay: Date?
    @State private var selectedHour: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Insights", subtitle: "How you speak, from your last \(settings.historyRetentionDays == 0 ? "" : "\(settings.historyRetentionDays) days of ")dictation. Private to this Mac.")
                HStack(alignment: .top, spacing: 14) {
                    goalCard
                    summaryCard
                }
                .fixedSize(horizontal: false, vertical: true)
                fillersCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], spacing: 14) {
                    speedCard
                    hoursCard
                }
                phrasesCard
            }
            .padding(20)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { insights = SpeechInsights(items: history.items) }
        .onChange(of: history.items.count) { insights = SpeechInsights(items: history.items) }
    }

    // MARK: Daily goal

    private var goalCard: some View {
        let today = history.wordsToday, goal = max(1, settings.dailyGoal)
        let progress = min(1, Double(today) / Double(goal))
        return Card {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 12)
                    Circle().trim(from: 0, to: progress)
                        .stroke(AngularGradient(colors: [Theme.accent.opacity(0.7), Theme.accent], center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.8), value: progress)
                    VStack(spacing: 0) {
                        Text("\(Int(progress * 100))%").font(.system(size: 18, weight: .bold, design: .rounded))
                        if progress >= 1 { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Theme.green) }
                    }
                }
                .frame(width: 76, height: 76)
                .padding(6)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Daily goal")
                    Text("\(today.compact) / \(goal.compact) words").font(.title3.weight(.semibold)).monospacedDigit()
                    Text(progress >= 1 ? "Goal reached — nice work! 🎉" : "\((goal - today).compact) words to go today")
                        .font(.callout).foregroundStyle(.secondary)
                    Menu("Goal: \(goal.compact) words") {
                        ForEach([250, 500, 1_000, 2_000, 3_000], id: \.self) { g in
                            Button("\(g.compact) words a day") { settings.dailyGoal = g }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.caption)
                }
            }
        }
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Your voice at a glance")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        metric("\(insights.uniqueWords.compact)", "different words")
                        metric("\(history.averageWPM)", "words per minute")
                    }
                    GridRow {
                        metric(String(format: "%.1f", insights.fillersPer100), "fillers per 100 words")
                        metric("\(insights.questions)", "questions asked")
                    }
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Fillers

    private var fillersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Filler words")
                    Spacer()
                    if let t = insights.fillerTrend {
                        Label("\(Int(abs(t) * 100))% \(t <= 0 ? "fewer" : "more") than last week",
                              systemImage: t <= 0 ? "arrow.down.right" : "arrow.up.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(t <= 0 ? Theme.green : .orange)
                    }
                }
                if insights.fillers.isEmpty {
                    Text("No filler words yet — impressive.").font(.callout).foregroundStyle(.secondary)
                } else {
                    let maxCount = insights.fillers.map(\.count).max() ?? 1
                    FlowLayout(spacing: 8) {
                        ForEach(insights.fillers.prefix(10)) { f in
                            FillerChip(word: f.word, count: f.count, fraction: Double(f.count) / Double(maxCount),
                                       removing: settings.autoRemoveFillers.contains(f.word)) {
                                if let i = settings.autoRemoveFillers.firstIndex(of: f.word) {
                                    settings.autoRemoveFillers.remove(at: i)
                                } else {
                                    settings.autoRemoveFillers.append(f.word)
                                }
                            }
                        }
                    }
                    Text("Click a word to remove it automatically from future dictations.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Speed

    private var speedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "Speaking speed")
                    Spacer()
                    if let d = selectedDay, let s = insights.speed.first(where: { Calendar.current.isDate($0.day, inSameDayAs: d) }) {
                        Text("\(s.day.formatted(.dateTime.month(.abbreviated).day())) · \(s.wpm) wpm")
                            .font(.caption.weight(.medium)).monospacedDigit()
                    } else if let best = insights.speed.max(by: { $0.wpm < $1.wpm }) {
                        Text("Best: \(best.wpm) wpm").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if insights.speed.count < 2 {
                    placeholder("Dictate on a few more days to see your trend.")
                } else {
                    Chart(insights.speed) { s in
                        AreaMark(x: .value("Day", s.day, unit: .day), y: .value("WPM", s.wpm))
                            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", s.day, unit: .day), y: .value("WPM", s.wpm))
                            .foregroundStyle(Theme.accent)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        if let d = selectedDay, Calendar.current.isDate(s.day, inSameDayAs: d) {
                            PointMark(x: .value("Day", s.day, unit: .day), y: .value("WPM", s.wpm))
                                .foregroundStyle(Theme.accent).symbolSize(80)
                        }
                        RuleMark(y: .value("Typing", 40))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("typing ≈ 40").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                    .chartXSelection(value: $selectedDay)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 150)
                }
            }
        }
    }

    // MARK: Time of day

    private var hoursCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "When you dictate")
                    Spacer()
                    if let h = selectedHour, let v = insights.hours.first(where: { $0.hour == h }) {
                        Text("\(hourLabel(h)) · \(v.words.formatted()) words").font(.caption.weight(.medium)).monospacedDigit()
                    } else if let peak = insights.hours.max(by: { $0.words < $1.words }), peak.words > 0 {
                        Text("Most active: \(hourLabel(peak.hour))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if insights.hours.allSatisfy({ $0.words == 0 }) {
                    placeholder("Your daily rhythm will show here.")
                } else {
                    Chart(insights.hours) { h in
                        BarMark(x: .value("Hour", h.hour), y: .value("Words", h.words), width: .fixed(9))
                            .foregroundStyle(selectedHour == nil || selectedHour == h.hour ? Theme.green : Theme.green.opacity(0.3))
                            .cornerRadius(3)
                    }
                    .chartXSelection(value: $selectedHour)
                    .chartXScale(domain: -0.5...23.5)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                            AxisValueLabel { Text(hourLabel(v.as(Int.self) ?? 0)) }
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 150)
                }
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h - 12) PM"
    }

    // MARK: Phrases

    private var phrasesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Your catchphrases")
                if insights.phrases.isEmpty {
                    placeholder("Phrases you say often will appear here.")
                } else {
                    let maxCount = insights.phrases.map(\.count).max() ?? 1
                    ForEach(insights.phrases) { p in
                        HStack(spacing: 10) {
                            Text("“\(p.text)”").font(.callout).lineLimit(1)
                            Spacer()
                            Capsule().fill(Theme.accent.opacity(0.7))
                                .frame(width: max(8, 120 * CGFloat(p.count) / CGFloat(maxCount)), height: 6)
                            Text("×\(p.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
    }
}

/// A tappable filler-word pill with a small usage bar.
struct FillerChip: View {
    let word: String, count: Int, fraction: Double, removing: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                if removing { Image(systemName: "nosign").font(.caption2) }
                Text("“\(word)”").strikethrough(removing)
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                ZStack(alignment: .leading) {
                    Capsule().fill(removing ? Color.orange.opacity(0.12) : Color.primary.opacity(hovering ? 0.08 : 0.05))
                    GeometryReader { g in
                        Capsule().fill((removing ? Color.orange : Theme.accent).opacity(0.18))
                            .frame(width: g.size.width * fraction)
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(removing ? "FreeFlow removes “\(word)” — click to keep it" : "Click to auto-remove “\(word)”")
    }
}

/// Wraps children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
