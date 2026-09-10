import AppKit
import SwiftUI

// Recording backdrop only. It has no connection to inference or warning state.
struct Backdrop: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.045, green: 0.05, blue: 0.047)
            VStack(alignment: .leading, spacing: 28) {
                Text("emilia").font(.system(size: 66, weight: .semibold, design: .serif))
                Text("A convincing voice.\nA dangerous request.").font(.system(size: 40, weight: .medium, design: .serif))
                Rectangle().fill(Color.orange).frame(width: 60, height: 3)
                Text("A second opinion\nbefore a costly mistake.").font(.system(size: 27)).foregroundStyle(.white.opacity(0.65))
                Text("LIVE APP · SIMULATED CALL").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Color.orange)
            }.padding(.leading, 65).padding(.top, 200)
            VStack(alignment: .leading, spacing: 12) {
                Text("OPENAI REALTIME  →  GPT-6 ASTRA  →  WARNING").font(.system(size: 18, weight: .semibold, design: .monospaced))
                Text("Also: local OpenAI Whisper · Built with Astra in Codex · AI voices: OpenAI speech API").font(.system(size: 16)).foregroundStyle(.white.opacity(0.65))
                Text("Hackathon: native Mac app + live integrations. Pretrained models and Emilia research predate the event.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
                Text("Current voice detector: AASIST-L placeholder. Emilia research detector integration pending. Edited demo; not a latency benchmark.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
            }.padding(.leading, 65).padding(.top, 895)
        }.foregroundStyle(Color(red: 0.94, green: 0.93, blue: 0.88))
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0]
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.contentView = NSHostingView(rootView: Backdrop())
window.isReleasedWhenClosed = false
window.level = .normal
window.orderFrontRegardless()
app.run()
