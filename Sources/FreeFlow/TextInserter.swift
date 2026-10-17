import AppKit
import ApplicationServices

/// Inserts text into the focused app the same way Wispr Flow does:
/// snapshot the clipboard → put text on it → simulate ⌘V → restore the clipboard.
enum TextInserter {
    private static let vKey: CGKeyCode = 9
    private static let cKey: CGKeyCode = 8

    static func insert(_ text: String, restoreClipboard: Bool) {
        let pb = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(pb) : nil
        pb.clearContents()
        pb.setString(text, forType: .string)
        let changeCount = pb.changeCount
        pressCommand(vKey)
        if let saved {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // Only restore if nobody else touched the clipboard in the meantime.
                guard pb.changeCount == changeCount else { return }
                restore(saved, to: pb)
            }
        }
    }

    /// Reads the selected text in the focused app: Accessibility first, ⌘C fallback.
    static func selectedText() async -> String? {
        if let ax = axSelectedText(), !ax.isEmpty { return ax }
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        pressCommand(cKey)
        try? await Task.sleep(for: .milliseconds(180))
        defer { restore(saved, to: pb) }
        guard pb.changeCount != before else { return nil }
        return pb.string(forType: .string)
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func pressCommand(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { dict[t] = d } }
            return dict
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pb: NSPasteboard) {
        pb.clearContents()
        let restored = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in dict { item.setData(d, forType: t) }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }
}
