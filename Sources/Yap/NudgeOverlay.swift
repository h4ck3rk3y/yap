import AppKit
import SwiftUI
import YapCore

/// A floating pill at the top of the screen. It never takes focus, shows on
/// every Space (including over full-screen Zoom), and is hidden from screen
/// sharing so the people on the call don't see it.
@MainActor
final class NudgeOverlay {
    private weak var engine: YapEngine?
    private var panel: NSPanel?
    private let size = NSSize(width: 380, height: 76)

    init(engine: YapEngine) {
        self.engine = engine
    }

    func show() {
        guard let engine else { return }
        let panel = self.panel ?? makePanel(engine: engine)
        self.panel = panel
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 10))
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel(engine: YapEngine) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: NudgeView().environmentObject(engine))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return panel
    }
}

struct NudgeView: View {
    @EnvironmentObject var engine: YapEngine

    var body: some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                engine.dismissNudge()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .help("Dismiss until this turn ends")
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
                )
        )
        .padding(2)
    }

    private var monologue: String { formatDuration(engine.snapshot.monologue) }

    private var emoji: String {
        switch engine.nudge {
        case .askQuestion: return "🤐"
        case .dominating: return "👂"
        default: return "🫁"
        }
    }

    private var title: String {
        switch engine.nudge {
        case .askQuestion: return "Pause. Ask them a question."
        case .dominating: return "Time to listen"
        default: return "Take a breath"
        }
    }

    private var subtitle: String {
        switch engine.nudge {
        case .dominating(let ratio):
            return "You've had \(Int(ratio * 100))% of the airtime in the last 5 min."
        case .askQuestion:
            return "You've been talking for \(monologue) straight."
        default:
            return "You've been talking for \(monologue). Leave some space."
        }
    }

    private var tint: Color {
        switch engine.nudge {
        case .askQuestion: return .red
        case .dominating: return .purple
        default: return .orange
        }
    }
}
