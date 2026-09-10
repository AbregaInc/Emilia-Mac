import AppKit
import SwiftUI
import Combine
import EmiliaCore

@main
enum EmiliaApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var overlay = WarningOverlay()
    private var subscription: AnyCancellable?
    private var mainWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Emilia ready. Audio capture is paused.")
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = ApplicationMenus.make()
        statusItem = Self.makeStatusItem()
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        statusItem.button?.toolTip = "Emilia — a second opinion for what you hear"
        model.onWarning = { [weak self] evidence in
            self?.overlay.show(evidence: evidence, dismiss: { [weak self] in self?.model.dismissWarning() })
        }
        model.onDismiss = { [weak self] in self?.overlay.hide() }
        subscription = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusItem.button?.contentTintColor = self.model.warning != nil ? .systemRed : self.model.listening ? .systemOrange : nil
                self.statusItem.button?.toolTip = "Emilia · \(self.model.status)"
            }
        }
        showMainWindow()
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let renderer = ImageRenderer(content: EmiliaView(model: model))
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            NSApp.terminate(nil)
        }
        #endif
    }
    static func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "ear", accessibilityDescription: "Emilia")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.setAccessibilityLabel("Emilia")
        item.isVisible = true
        return item
    }
    @objc private func toggle() {
        showMainWindow()
    }
    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if mainWindow == nil {
            let host = NSHostingView(rootView: EmiliaView(model: model))
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Emilia"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.075, green: 0.08, blue: 0.075, alpha: 1)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.center()
            // Presentation-only layout: inference and capture use the normal path.
            if CommandLine.arguments.contains("--demo-layout"), let screen = NSScreen.screens.first {
                window.setFrameOrigin(NSPoint(x: screen.frame.minX + 740, y: screen.frame.maxY - window.frame.height - 170))
                window.level = .floating
            }
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

enum Palette {
    static let background = Color(red: 0.075, green: 0.08, blue: 0.075)
    static let card = Color(red: 0.12, green: 0.125, blue: 0.115)
    static let ink = Color(red: 0.94, green: 0.93, blue: 0.87)
    static let muted = Color(red: 0.58, green: 0.60, blue: 0.55)
    static let accent = Color(red: 1, green: 0.48, blue: 0.26)
}

struct EmiliaView: View {
    @ObservedObject var model: AppModel
    @State private var keyDraft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("emilia").font(.system(size: 34, weight: .medium, design: .serif)).tracking(-1.5)
                Spacer()
                Text("ON YOUR SIDE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                Button { model.settingsVisible.toggle() } label: { Image(systemName: "gearshape").font(.system(size: 14)) }.buttonStyle(.plain).help("Settings")
            }
            if model.settingsVisible { settings }
            else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.warning != nil ? "Pause before\nyou act." : model.listening ? "A second ear.\nA little more clarity." : "Some calls deserve\na second opinion.")
                        .font(.system(size: 27, weight: .regular, design: .serif)).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
                    Text(model.listening ? "Listening for requests that put you at risk." : "Listen for the pressure behind the words.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 4) {
                        ForEach(CaptureMode.allCases) { mode in
                            Button { model.captureMode = mode } label: {
                                Label(mode.rawValue, systemImage: mode == .microphone ? "mic" : "speaker.wave.2")
                                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundStyle(model.captureMode == mode ? Palette.ink : Palette.muted)
                                    .background(model.captureMode == mode ? Palette.muted.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).accessibilityAddTraits(model.captureMode == mode ? .isSelected : [])
                        }
                    }.padding(4).background(Palette.card, in: RoundedRectangle(cornerRadius: 10)).disabled(model.listening || model.preparing)
                    Text(model.captureMode.detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    HStack(spacing: 3) {
                        ForEach(0..<40, id: \.self) { i in
                            Capsule().fill(Float(i) / 40 < model.level ? Palette.accent : Palette.muted.opacity(0.2)).frame(height: 15)
                        }
                    }.accessibilityLabel("Audio level \(Int(model.level * 100)) percent")
                    HStack(spacing: 6) {
                        Circle().fill(model.degraded || model.errorMessage != nil ? Color.yellow : model.listening ? Palette.accent : Palette.muted).frame(width: 5, height: 5)
                        Text(model.status).font(.system(size: 10, weight: .medium)).lineLimit(2)
                        Spacer()
                        if model.listening { Text(duration).monospacedDigit().font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted) }
                    }
                }
                if let warning = model.warning {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("SCAM WARNING SIGNS", systemImage: "exclamationmark.shield.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
                        Text(warning.assessment.reason).font(.system(size: 13, weight: .medium))
                        Text("Verify through a contact method you already trust.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Button("Dismiss warning") { model.dismissWarning() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("WHAT WE’RE HEARING").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                            Spacer()
                            Text(model.transcriptionMode == .local ? "WHISPER · LOCAL" : "OPENAI · REALTIME").font(.system(size: 8, design: .monospaced))
                        }.foregroundStyle(Palette.muted)
                        ScrollView {
                            Text(model.transcript.isEmpty ? "Your live transcript will appear here. Nothing is recorded to disk." : model.transcript)
                                .font(.system(size: 12)).foregroundStyle(model.transcript.isEmpty ? Palette.muted : Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }.frame(height: 66)
                    }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(model.synthetic ? Palette.accent : Palette.muted)
                        Text(model.voiceStatus).lineLimit(2)
                    }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                    if let error = model.errorMessage { Text(error).font(.system(size: 11)).foregroundStyle(.yellow).fixedSize(horizontal: false, vertical: true) }
                    Button {
                        if model.listening || model.preparing { model.stop() } else { model.start() }
                    } label: {
                        HStack {
                            if model.preparing { ProgressView().controlSize(.small) }
                            Image(systemName: model.listening || model.preparing ? "pause.fill" : "ear.badge.waveform")
                            Text(model.preparing ? "Cancel" : model.listening ? "Pause listening" : "Start listening").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: model.listening ? "stop.circle" : "arrow.up.right")
                        }.font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 13)
                            .foregroundStyle(Palette.background).background(Palette.accent, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                    Text(model.transcriptionMode == .local ? "Transcripts analyzed with OpenAI Astra." : "Audio transcribed with OpenAI. Astra analyzes the text.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            HStack {
                Text("A SECOND OPINION. NOT A GUARANTEE.").font(.system(size: 8, design: .monospaced)).tracking(0.4)
                Spacer()
                Button("Quit") { model.stop(); NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 10))
            }.foregroundStyle(Palette.muted)
        }
        .padding(24).frame(width: 390).foregroundStyle(Palette.ink).background(Palette.background).preferredColorScheme(.dark)
    }
    private var duration: String { String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60) }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A little setup.").font(.system(size: 26, design: .serif))
            Text(model.keyConfigured ? "OpenAI API key configured." : "Add your OpenAI API key to enable Astra analysis.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            SecureField("API key", text: $keyDraft).textFieldStyle(.roundedBorder)
            Button("Save key") { model.saveKey(keyDraft); keyDraft = "" }.disabled(keyDraft.isEmpty)
            Text("Saved securely on this Mac.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            Divider()
            Text("TRANSCRIPTION").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.muted)
            ForEach(TranscriptionMode.allCases) { mode in
                Button { model.transcriptionMode = mode } label: {
                    HStack {
                        Image(systemName: model.transcriptionMode == mode ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.rawValue).font(.system(size: 13, weight: .medium))
                            Text(mode == .local ? "Audio stays on this Mac." : "Live captions. Audio is sent to OpenAI.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }
                }.buttonStyle(.plain).disabled(model.listening || model.preparing)
            }
            if model.listening || model.preparing { Text("Pause listening to change transcription.").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            Text("Astra analyzes transcript excerpts in either mode.").font(.system(size: 12))
            Text("Voice-origin evidence is separate from scam warnings. A synthetic voice alone never triggers a red alert.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            if let latency = model.apiLatency { Text(String(format: "Last Astra response: %.1fs · %d requests", latency, model.assessments)).font(.system(size: 11, design: .monospaced)) }
            Button("Done") { model.settingsVisible = false }.buttonStyle(.borderedProminent).tint(Palette.accent)
        }
    }
}

@MainActor
final class WarningOverlay {
    private var borders: [NSWindow] = []
    private var panel: NSPanel?
    func show(evidence: WarningEvidence, dismiss: @escaping () -> Void) {
        hide()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.level = .statusBar; window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: BorderWash())
            window.orderFrontRegardless(); borders.append(window)
        }
        guard let screen = CommandLine.arguments.contains("--demo-layout") ? NSScreen.screens.first : NSScreen.main else { return }
        let frame = NSRect(x: screen.visibleFrame.maxX - 412, y: screen.visibleFrame.maxY - 278, width: 390, height: 250)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WarningCard(evidence: evidence, dismiss: dismiss))
        panel.orderFrontRegardless(); self.panel = panel
    }
    func hide() { borders.forEach { $0.orderOut(nil) }; borders.removeAll(); panel?.orderOut(nil); panel = nil }
}

struct BorderWash: View {
    @State private var wash = true
    var body: some View {
        ZStack {
            Color.red.opacity(wash && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.16 : 0)
            RoundedRectangle(cornerRadius: 16).stroke(Color(red: 1, green: 0.25, blue: 0.19), lineWidth: 7).padding(3)
        }.ignoresSafeArea().onAppear { withAnimation(.easeOut(duration: 1.2)) { wash = false } }
    }
}

struct WarningCard: View {
    let evidence: WarningEvidence
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("EMILIA · SCAM WARNING SIGNS", systemImage: "exclamationmark.shield.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss warning")
            }
            Text("Pause before you act.").font(.system(size: 27, design: .serif))
            Text(evidence.assessment.reason).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text("“\(evidence.assessment.quotes.joined(separator: "” · “"))”").font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(3)
            Text("Verify through a contact method you already trust.").font(.system(size: 12)).foregroundStyle(Palette.accent)
        }.padding(22).frame(width: 390, alignment: .leading).foregroundStyle(Palette.ink)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.accent.opacity(0.6), lineWidth: 1))
            .preferredColorScheme(.dark)
    }
}
