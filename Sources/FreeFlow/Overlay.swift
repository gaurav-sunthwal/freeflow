import AppKit
import SwiftUI

final class OverlayModel: ObservableObject {
    enum Phase: Equatable { case hidden, listening, processing, message(String) }
    @Published var phase: Phase = .hidden
    @Published var levels: [CGFloat] = Array(repeating: 0.05, count: 18)
    @Published var handsFree = false
    @Published var commandMode = false

    func push(level: Float) {
        levels.removeFirst()
        levels.append(max(0.05, CGFloat(level)))
    }
}

/// The small floating pill at the bottom of the screen (Wispr's "Flow bar").
final class OverlayController {
    let model = OverlayModel()
    private var panel: NSPanel!
    private var hideWork: DispatchWorkItem?

    init() {
        let size = NSSize(width: 220, height: 44)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    func set(_ phase: OverlayModel.Phase) {
        hideWork?.cancel()
        model.phase = phase
        switch phase {
        case .hidden:
            panel.orderOut(nil)
        case .message:
            show()
            let work = DispatchWorkItem { [weak self] in self?.set(.hidden) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        default:
            show()
        }
    }

    private func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 24))
        panel.orderFrontRegardless()
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .listening:
                Circle().fill(model.commandMode ? Color.purple : Color.red).frame(width: 8, height: 8)
                HStack(spacing: 2) {
                    ForEach(model.levels.indices, id: \.self) { i in
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: 3, height: 4 + model.levels[i] * 22)
                    }
                }
                .animation(.linear(duration: 0.08), value: model.levels)
                if model.handsFree { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)) }
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
                Text(model.commandMode ? "Thinking…" : "Transcribing…").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            case .message(let m):
                Text(m).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(2)
            case .hidden:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
