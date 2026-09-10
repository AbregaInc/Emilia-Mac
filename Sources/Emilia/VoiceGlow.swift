import AppKit
import SwiftUI

@MainActor
final class VoiceGlow {
    private(set) var windows: [NSWindow] = []
    static func shouldShow(listening: Bool, synthetic: Bool, scamWarning: Bool) -> Bool {
        listening && synthetic && !scamWarning
    }
    func update(listening: Bool, synthetic: Bool, scamWarning: Bool) {
        let visible = Self.shouldShow(listening: listening, synthetic: synthetic, scamWarning: scamWarning)
        guard visible != !windows.isEmpty else { return }
        hide()
        if visible {
            for screen in NSScreen.screens {
                let window = Self.makeWindow(frame: screen.frame)
                window.orderFrontRegardless(); windows.append(window)
            }
        }
    }
    static func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = .statusBar; window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: AmberEdges())
        return window
    }
    func hide() { windows.forEach { $0.orderOut(nil) }; windows.removeAll() }
}

struct AmberEdges: View {
    private let amber = Color(red: 1, green: 0.65, blue: 0.12)
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16).stroke(amber.opacity(0.55), lineWidth: 20).blur(radius: 13).padding(4)
            RoundedRectangle(cornerRadius: 16).stroke(amber.opacity(0.85), lineWidth: 3).padding(2)
            Text("EMILIA · SYNTHETIC VOICE EVIDENCE")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(amber)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.black.opacity(0.85), in: Capsule()).padding(.top, 38)
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
