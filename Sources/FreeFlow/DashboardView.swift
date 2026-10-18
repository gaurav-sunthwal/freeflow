import SwiftUI
import AppKit

/// The Home screen: what you see when you open FreeFlow from the menu bar.
/// Minimal, data-first, and built to make you want to keep your streak going.
struct HomeView: View {
    @ObservedObject var history = HistoryStore.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var coordinator = Coordinator.shared
    var openAccount: () -> Void = {}
    @State private var showAll = false
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let err = coordinator.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                statsRow
                ActivityHeatmap(history: history)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], spacing: 14) {
                    milestone
                    topApps
                }
                recent
            }
            .padding(20)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Working late" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return firstName.isEmpty ? part : "\(part), \(firstName)"
    }

    private var motivation: String {
        let today = history.wordsToday, streak = history.streakDays
        if today == 0 && streak > 0 { return "Dictate today to keep your \(streak)-day streak alive 🔥" }
        if today == 0 { return "Hold \(settings.hotkey.label) anywhere and start talking." }
        if streak >= 7 { return "\(streak) days in a row. You're on fire 🔥" }
        return "You've spoken \(today.compact) words today. Keep the flow going."
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) {
                titleBlock
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 6) {
                    AccountChip(open: openAccount)
                    hotkeyPill
                }
            }
            HStack(alignment: .top) {
                titleBlock
                Spacer(minLength: 8)
                AccountChip(open: openAccount)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(greeting).font(.title.weight(.bold))
            Text(motivation).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var hotkeyPill: some View {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                Text("Hold").foregroundStyle(.secondary)
                Text(settings.hotkey == .fn ? "fn" : settings.hotkey.label)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                Text("to dictate").foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .fixedSize()
    }

    // MARK: Stats

    private var statsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { streakTile; todayTile; speedTile; savedTile }
            VStack(spacing: 12) {
                HStack(spacing: 12) { streakTile; todayTile }
                HStack(spacing: 12) { speedTile; savedTile }
            }
        }
    }

    private var streakTile: some View {
        StatTile(icon: "flame.fill", tint: Theme.flame, value: "\(history.streakDays)",
                 unit: history.streakDays == 1 ? "day" : "days", label: "Streak",
                 footnote: "Best: \(max(history.bestStreak, history.streakDays)) days")
    }
    private var todayTile: some View {
        StatTile(icon: "text.word.spacing", tint: Theme.accent, value: history.wordsToday.compact,
                 unit: "words", label: "Today", footnote: "\(history.totalWords.compact) all time")
    }
    private var speedTile: some View {
        StatTile(icon: "speedometer", tint: .blue, value: "\(history.averageWPM)",
                 unit: "wpm", label: "Speed", footnote: "Typing ≈ 40 wpm")
    }
    private var savedTile: some View {
        StatTile(icon: "clock.arrow.circlepath", tint: Theme.green, value: timeSaved.value,
                 unit: timeSaved.unit, label: "Time saved", footnote: "vs. typing")
    }

    private var timeSaved: (value: String, unit: String) {
        let m = history.minutesSaved
        return m >= 120 ? (String(format: "%.1f", Double(m) / 60), "hours") : ("\(m)", "min")
    }

    // MARK: Milestone

    private var milestone: some View {
        let goals = [500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000]
        let total = history.totalWords
        let next = goals.first { $0 > total } ?? (total + 100_000)
        let previous = goals.last { $0 <= total } ?? 0
        let progress = Double(total - previous) / Double(max(1, next - previous))
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Next milestone")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(next.compact).font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("words").foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.7)],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 8)
                Text("\((next - total).compact) words to go · \(Int(progress * 100))%")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Top apps

    private var topApps: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Where you dictate")
                let apps = history.topApps
                if apps.isEmpty {
                    Text("Your most-used apps will appear here.").font(.callout).foregroundStyle(.secondary)
                } else {
                    let maxWords = apps.map(\.words).max() ?? 1
                    ForEach(apps, id: \.name) { app in
                        HStack(spacing: 10) {
                            AppIconView(name: app.name)
                            Text(app.name).font(.callout).lineLimit(1).frame(width: 96, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(Theme.accent.opacity(0.75))
                                    .frame(width: max(6, geo.size.width * CGFloat(app.words) / CGFloat(maxWords)))
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 8)
                            Text(app.words.compact).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: Recent

    private var filtered: [HistoryItem] {
        let all = search.isEmpty ? history.items : history.items.filter { $0.text.localizedCaseInsensitiveContains(search) }
        return showAll || !search.isEmpty ? all : Array(all.prefix(5))
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Recent")
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search).textFieldStyle(.plain).frame(width: 150)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                if history.items.count > 5 && search.isEmpty {
                    Button(showAll ? "Show less" : "Show all \(history.items.count)") { showAll.toggle() }
                        .buttonStyle(.link)
                }
            }
            if filtered.isEmpty {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform").font(.title2).foregroundStyle(Theme.accent)
                        Text(search.isEmpty ? "Nothing yet. Hold fn in any app and say something." : "No matches.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                            RecentRow(item: item)
                            if index < filtered.count - 1 { Divider().padding(.leading, 12) }
                        }
                    }
                }
                Text("Dictations are kept for \(settings.historyRetentionDays == 0 ? "ever" : "\(settings.historyRetentionDays) days") on this Mac. Stats are kept forever.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Pieces

struct StatTile: View {
    let icon: String, tint: Color, value: String, unit: String, label: String, footnote: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(label).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.caption)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
                Text(footnote).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(minWidth: 128)
    }
}

struct RecentRow: View {
    let item: HistoryItem
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(name: item.app).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text).lineLimit(3).textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(item.app)
                    Text("·")
                    Text(item.date, style: .relative) + Text(" ago")
                    if item.isCommand { Text("· Command").foregroundStyle(Theme.accent) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if hovering || copied {
                HStack(spacing: 4) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .help("Copy")
                    Button { HistoryStore.shared.delete(item) } label: { Image(systemName: "trash") }
                        .help("Delete")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Color.primary.opacity(0.04) : .clear))
        .onHover { hovering = $0 }
    }
}

/// The real app icon when we can find the app, otherwise a neutral glyph.
struct AppIconView: View {
    let name: String
    var body: some View {
        Group {
            if let icon = Self.icon(for: name) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary).padding(2)
            }
        }
        .frame(width: 18, height: 18)
    }

    private static var cache: [String: NSImage] = [:]
    static func icon(for name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let candidates = ["/Applications/\(name).app", "/System/Applications/\(name).app",
                          "/System/Applications/Utilities/\(name).app", "\(NSHomeDirectory())/Applications/\(name).app"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[name] = icon
        return icon
    }
}

/// GitHub-style contribution graph: one square per day, greener = more words dictated.
struct ActivityHeatmap: View {
    @ObservedObject var history: HistoryStore
    private let maxWeeks = 53
    @State private var hovered: Date?
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    private func days(_ weeks: Int) -> [[Date]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - 1          // 0 = Sunday
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today)!
        return (0..<weeks).map { w in
            (0..<7).compactMap { d in
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                return date <= today ? date : nil
            }
        }
    }

    private func level(_ words: Int) -> Int {
        switch words {
        case 0: return 0
        case 1..<50: return 1
        case 50..<200: return 2
        case 200..<500: return 3
        default: return 4
        }
    }

    /// "Sat, Oct 18 · 1,738 words · 24 dictations · 16 min"
    private func hoverInfo(_ day: Date) -> some View {
        let words = history.words(on: day)
        let count = history.dictations(on: day)
        let minutes = Int((history.seconds(on: day) / 60).rounded())
        return HStack(spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).fontWeight(.semibold)
            if words == 0 {
                Text("· No dictation").foregroundStyle(.secondary)
            } else {
                Text("· \(words.formatted()) words").foregroundStyle(Theme.green)
                if count > 0 { Text("· \(count) dictation\(count == 1 ? "" : "s")").foregroundStyle(.secondary) }
                if minutes > 0 { Text("· \(minutes) min").foregroundStyle(.secondary) }
            }
        }
        .font(.caption)
        .monospacedDigit()
    }

    private var activeDaysCount: Int {
        days(maxWeeks).flatMap { $0 }.filter { history.words(on: $0) > 0 }.count
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Activity")
                    Spacer()
                    if let day = hovered {
                        hoverInfo(day)
                    } else {
                        Text("\(activeDaysCount) active days · hover a day for details")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                GeometryReader { geo in
                    // As many whole weeks as fit the card, up to a year.
                    let weeks = max(8, min(maxWeeks, Int((geo.size.width - 30) / (cell + gap))))
                    HStack(alignment: .top, spacing: 6) {
                        dayLabels
                        grid(days(weeks))
                    }
                }
                .frame(height: 16 + 7 * cell + 6 * gap + 4)
                legend
            }
        }
    }

    private var dayLabels: some View {
                    VStack(alignment: .trailing, spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            Text(["", "Mon", "", "Wed", "", "Fri", ""][d])
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .fixedSize()
                                .frame(width: 24, height: cell, alignment: .trailing)
                        }
                    }
                    .padding(.top, 16)
    }

    private func grid(_ days: [[Date]]) -> some View {
                    VStack(alignment: .leading, spacing: 4) {
                        monthLabels(days)
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(Array(days.enumerated()), id: \.offset) { _, week in
                                VStack(spacing: gap) {
                                    ForEach(week, id: \.self) { day in
                                        let words = history.words(on: day)
                                        let isHovered = hovered == day
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Theme.heat(level(words)))
                                            .frame(width: cell, height: cell)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 3)
                                                    .strokeBorder(Color.primary.opacity(isHovered ? 0.9 : Calendar.current.isDateInToday(day) ? 0.45 : 0),
                                                                  lineWidth: isHovered ? 1.5 : 1)
                                            )
                                            .scaleEffect(isHovered ? 1.25 : 1)
                                            .animation(.easeOut(duration: 0.08), value: isHovered)
                                            .contentShape(Rectangle())
                                            .onHover { inside in
                                                if inside { hovered = day } else if hovered == day { hovered = nil }
                                            }
                                    }
                                }
                            }
                        }
                    }
    }

    private var legend: some View {
                HStack(spacing: 4) {
                    Spacer()
                    Text("Less").font(.caption2).foregroundStyle(.secondary)
                    ForEach(0..<5, id: \.self) { l in
                        RoundedRectangle(cornerRadius: 2).fill(Theme.heat(l)).frame(width: 10, height: 10)
                    }
                    Text("More").font(.caption2).foregroundStyle(.secondary)
                }
    }

    private func monthLabels(_ days: [[Date]]) -> some View {
        let cal = Calendar.current
        return HStack(spacing: gap) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, week in
                let first = week.first ?? Date()
                // Label the first full week of each month (GitHub-style); skip a month that starts in the first column.
                let showsMonth = i > 0 && i < days.count - 2
                    && cal.component(.month, from: first) != cal.component(.month, from: days[i - 1].first ?? first)
                Text(showsMonth ? first.formatted(.dateTime.month(.abbreviated)) : "")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: cell, height: 12, alignment: .leading)
            }
        }
    }
}
