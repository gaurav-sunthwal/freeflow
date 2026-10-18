import SwiftUI

/// FreeFlow's visual language: calm neutral surfaces, one violet accent (from the app icon), green for activity.
enum Theme {
    static let accent = Color(red: 0.49, green: 0.42, blue: 1.0)
    static let accentSoft = Color(red: 0.49, green: 0.42, blue: 1.0).opacity(0.14)
    static let green = Color(red: 0.16, green: 0.73, blue: 0.40)
    static let flame = Color(red: 1.0, green: 0.55, blue: 0.20)
    static let corner: CGFloat = 10

    /// GitHub-style activity levels (0 = no dictation that day).
    static func heat(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.07)
        case 1: return green.opacity(0.35)
        case 2: return green.opacity(0.55)
        case 3: return green.opacity(0.78)
        default: return green
        }
    }
}

/// A quiet rounded surface used for every block on screen.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

/// Small uppercase label above a section.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Page title + subtitle used at the top of every pane.
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.bold))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Int {
    /// 1234 → "1,234", 12345 → "12.3k"
    var compact: String {
        if self >= 100_000 { return String(format: "%.0fk", Double(self) / 1000) }
        if self >= 10_000 { return String(format: "%.1fk", Double(self) / 1000) }
        return formatted(.number)
    }
}
