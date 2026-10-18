import AppKit
import SwiftUI
import AVFoundation
import CoreAudio

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        Permissions.shared.refresh()
        Coordinator.shared.start()
        if !Permissions.shared.allGranted { showWindow(.setup) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(.home)
        return true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "FreeFlow")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared
        let header = NSMenuItem(title: "Hold \(s.hotkey.label) to dictate", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("Open FreeFlow", #selector(openHome), "o"))
        let recording = Coordinator.shared.state == .recording
        menu.addItem(item(recording ? "Stop Hands-free Dictation" : "Start Hands-free Dictation", #selector(toggleHandsFree), ""))
        menu.addItem(item("Paste Last Transcript", #selector(pasteLast), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Setup & Permissions", #selector(openSetup), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit FreeFlow", #selector(quit), "q"))
    }

    private func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openHome() { showWindow(.home) }
    @objc private func openSettings() { showWindow(.settings) }
    @objc private func openSetup() { showWindow(.setup) }
    @objc private func toggleHandsFree() { Coordinator.shared.toggleHandsFree() }
    @objc private func pasteLast() {
        // Give the menu time to close so focus returns to the previous app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Coordinator.shared.pasteLast() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showWindow(_ pane: Pane) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "FreeFlow"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: MainView(pane: pane))
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}

/// `FreeFlow --selftest <audio file> [bundle id]` runs the dictation pipeline on a file and prints the result.
func runSelfTest(path: String, bundleID: String?) async {
    let settings = Settings.shared
    do {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        let session = Transcribers.makeSession(settings: settings, inputFormat: format)
        TextProcessor.prewarm(appBundleID: bundleID, command: false, settings: settings)
        // Simulate the user speaking: the model warms up while audio arrives.
        try await Task.sleep(for: .seconds(Double(file.length) / format.sampleRate))
        while file.framePosition < file.length {
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
            try file.read(into: buf)
            session.append(buf)
        }
        let start = Date()
        let raw = try await session.finish(samples16k: [])
        print("RAW (\(String(format: "%.2f", Date().timeIntervalSince(start)))s after end of audio): \(raw)")
        let t = Date()
        let out = await TextProcessor.process(raw, appBundleID: bundleID, settings: settings)
        print("CLEAN (\(String(format: "%.2f", Date().timeIntervalSince(t)))s, provider: \(settings.cleanup.rawValue)): \(out)")
    } catch {
        print("ERROR: \(error.localizedDescription)")
    }
    exit(0)
}

/// `FreeFlow --mic-test` records 2 s like a dictation and reports which microphone was used,
/// whether Bluetooth headphones stayed in high-quality mode, and whether other audio was muted.
if CommandLine.arguments.contains("--mic-test") {
    func outputRate() -> Double {
        guard let dev = AudioDevices.defaultOutput else { return 0 }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate = Float64(0); var size = UInt32(8)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &rate)
        return rate
    }
    func muted() -> Bool {
        guard let dev = AudioDevices.defaultOutput else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var v = UInt32(0); var size = UInt32(4)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v)
        return v != 0
    }
    let pref = Settings.shared.micDevice
    let uid = AudioDevices.inputDeviceUID(for: pref)
    let name = AudioDevices.inputDevices().first { uid != nil ? $0.uid == uid : $0.id == AudioDevices.defaultInput }?.name ?? "unknown"
    print("Microphone preference: \(pref.isEmpty ? "automatic" : pref) → using \(name)")
    print("Output before:    \(outputRate()) Hz, muted: \(muted())")
    let recorder = AudioRecorder()
    do {
        try recorder.start(deviceUID: uid)
        AudioDevices.muteOutput()
        Thread.sleep(forTimeInterval: 2)
        print("While recording:  \(outputRate()) Hz, muted: \(muted())")
        recorder.stop()
        AudioDevices.restoreOutput()
        Thread.sleep(forTimeInterval: 2)
        print("After recording:  \(outputRate()) Hz, muted: \(muted())")
        print("Peak input level: \(String(format: "%.3f", recorder.peakLevel))")
    } catch {
        print("ERROR: \(error.localizedDescription)")
    }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--process"), i + 1 < CommandLine.arguments.count {
    let text = CommandLine.arguments[i + 1]
    Task {
        let t = Date()
        let out = await TextProcessor.process(text, appBundleID: nil, settings: Settings.shared)
        print(String(format: "[%.2fs] ", Date().timeIntervalSince(t)) + out)
        exit(0)
    }
    RunLoop.main.run()
}

if let i = CommandLine.arguments.firstIndex(of: "--selftest"), i + 1 < CommandLine.arguments.count {
    let args = CommandLine.arguments
    Task { await runSelfTest(path: args[i + 1], bundleID: i + 2 < args.count ? args[i + 2] : nil) }
    RunLoop.main.run()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
