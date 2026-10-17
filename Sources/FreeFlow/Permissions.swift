import AppKit
import AVFoundation
import ApplicationServices
import Speech

final class Permissions: ObservableObject {
    static let shared = Permissions()
    @Published var microphone = false
    @Published var accessibility = false
    @Published var speech = false

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = AXIsProcessTrusted()
        speech = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    var allGranted: Bool { microphone && accessibility }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.refresh() } }
    }

    func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { self.refresh() } }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
