import AppKit
import CoreGraphics

/// Global hotkey handling via a CGEventTap — the same mechanism Wispr Flow's Swift helper uses.
///
/// - Hold the hotkey: push-to-talk (release to insert).
/// - Double-tap the hotkey: hands-free mode (tap again to finish).
/// - Hold Control together with the hotkey: Command Mode (edit selected text by voice).
/// - Escape while recording: cancel.
final class HotkeyMonitor {
    enum Event {
        case pushStart(command: Bool)
        case pushEnd
        case handsFreeStart(command: Bool)
        case handsFreeEnd
        case cancel
    }

    var onEvent: ((Event) -> Void)?
    var isRecording: () -> Bool = { false }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hotkeyDown = false
    private var pressTime = Date.distantPast
    private var lastTapTime = Date.distantPast
    private var handsFree = false
    private var pushActive = false

    private let tapThreshold: TimeInterval = 0.25
    private let doubleTapWindow: TimeInterval = 0.45

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Called by the coordinator when a session ends for reasons other than the hotkey.
    func reset() {
        handsFree = false
        pushActive = false
    }

    private func keyCodeAndFlag(for hotkey: HotkeyChoice) -> (Int64, CGEventFlags) {
        switch hotkey {
        case .fn: return (63, .maskSecondaryFn)
        case .rightOption: return (61, .maskAlternate)
        case .rightCommand: return (54, .maskCommand)
        case .rightControl: return (62, .maskControl)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown {
            // Escape cancels an active recording.
            if keyCode == 53, isRecording() {
                handsFree = false
                pushActive = false
                emit(.cancel)
                return nil
            }
            // Another key pressed right after the hotkey went down → it's a normal shortcut, not dictation.
            if hotkeyDown, pushActive, Date().timeIntervalSince(pressTime) < 0.4 {
                pushActive = false
                emit(.cancel)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let (hkCode, hkFlag) = keyCodeAndFlag(for: Settings.shared.hotkey)
        guard keyCode == hkCode else { return Unmanaged.passUnretained(event) }

        let down = event.flags.contains(hkFlag)
        let command = Settings.shared.hotkey != .rightControl && event.flags.contains(.maskControl)
        guard down != hotkeyDown else { return Unmanaged.passUnretained(event) }
        hotkeyDown = down
        let now = Date()

        if down {
            pressTime = now
            if handsFree {
                handsFree = false
                emit(.handsFreeEnd)
            } else if now.timeIntervalSince(lastTapTime) < doubleTapWindow {
                lastTapTime = .distantPast
                handsFree = true
                emit(.handsFreeStart(command: command))
            } else {
                pushActive = true
                emit(.pushStart(command: command))
            }
        } else if pushActive {
            pushActive = false
            if now.timeIntervalSince(pressTime) < tapThreshold {
                lastTapTime = now
                emit(.cancel)
            } else {
                emit(.pushEnd)
            }
        }
        // Swallow Fn so macOS doesn't pop the emoji picker / system dictation.
        return Settings.shared.hotkey == .fn ? nil : Unmanaged.passUnretained(event)
    }

    private func emit(_ e: Event) {
        DispatchQueue.main.async { self.onEvent?(e) }
    }
}
