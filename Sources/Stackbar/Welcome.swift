#if os(macOS)
import AppKit
import Combine
import ServiceManagement
import StackbarHostCore
import StackbarProtocol
import SwiftUI

/// The palette's hotkey: a recorder, a one-click ⌘Space, and help for
/// freeing ⌘Space from Spotlight. In Settings › General and the welcome
/// window.
struct PaletteHotKeyPicker: View {
    @State private var spec = PaletteController.chosenHotKey
    @State private var spotlightHolds = PaletteController.spotlightHoldsCommandSpace

    private var wantsCommandSpace: Bool { HotKeySpec(spec) == HotKeySpec(PaletteHotKey.spotlight) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                if !wantsCommandSpace {
                    Button("Use ⌘Space") { choose(PaletteHotKey.spotlight) }
                }
                HotKeyRecorder(spec: spec) { choose($0 ?? PaletteHotKey.standard) }
            }
            if wantsCommandSpace && spotlightHolds {
                Text("Spotlight still answers ⌘Space, so \(ActionsPanel.glyphs(PaletteHotKey.standard)) opens the palette until you turn Spotlight's shortcut off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 320, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn Off Spotlight's Shortcut…") {
                    if let url = URL(string: SpotlightShortcut.settingsURL) { NSWorkspace.shared.open(url) }
                }
                .controlSize(.small)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            spotlightHolds = PaletteController.spotlightHoldsCommandSpace
        }
    }

    private func choose(_ new: String) {
        PaletteController.chosenHotKey = new
        spec = PaletteController.chosenHotKey
        spotlightHolds = PaletteController.spotlightHoldsCommandSpace
        AppDelegate.shared?.palette.applyHotKey()
    }
}

/// The first launch: pick the palette's hotkey and a few plugins, then land
/// in the palette.
struct WelcomeView: View {
    static let seenKey = "welcomeSeen"

    let starters: [Manifest]
    let finish: (_ picked: Set<String>, _ openAtLogin: Bool, _ openPalette: Bool) -> Void
    @State private var picked: Set<String>
    @State private var openAtLogin = true
    @State private var sendCrashReports = false

    init(starters: [Manifest], finish: @escaping (Set<String>, Bool, Bool) -> Void) {
        self.starters = starters
        self.finish = finish
        _picked = State(initialValue: Set(starters.map(\.id)).intersection(BundledStore.starterPluginIDs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Stackbar").font(.title2.weight(.semibold))
                    Text("Apps, files, sums and every plugin's commands, one keystroke away.")
                        .foregroundStyle(.secondary)
                }
            }
            step(1, "Choose the palette's hotkey") {
                HStack(alignment: .top) {
                    Text("Most people coming from Raycast or Alfred use ⌘Space.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    PaletteHotKeyPicker()
                }
            }
            if !starters.isEmpty {
                step(2, "Start with these plugins") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(starters, id: \.id) { manifest in
                            Toggle(isOn: binding(manifest.id)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(manifest.name)
                                    if let summary = manifest.summary {
                                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                        }
                        Text("Applications, Calculator and File Search are already in. More in the Store.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            step(starters.isEmpty ? 2 : 3, "Keep it running") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Open Stackbar at login", isOn: $openAtLogin)
                    if CrashReports.isAvailable {
                        Toggle("Send a crash report if Stackbar crashes (no plugin names, logs or files)", isOn: $sendCrashReports)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Skip") { finish([], false, false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open the Palette") {
                    if CrashReports.isAvailable { CrashReports.isAllowed = sendCrashReports }
                    finish(picked, openAtLogin, true)
                }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 560)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { picked.contains(id) }, set: { on in if on { picked.insert(id) } else { picked.remove(id) } })
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))
            }
            content()
                .padding(.leading, 28)
        }
    }
}

extension AppDelegate {
    private static let welcomeNoteRoom: CGFloat = 72

    /// Shows the welcome window once per user.
    func welcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: WelcomeView.seenKey) else { return }
        showWelcome()
    }

    func showWelcome() {
        // A plain titled window sized once. A transparent full-size title bar
        // with `.preferredContentSize` sizing made the safe area and the
        // window frame resize each other until AppKit threw (0.22.0 crash).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Stackbar"
        window.isReleasedWhenClosed = false
        let starters = model.bundledStore.starters()
        let view = WelcomeView(starters: starters) { [weak self, weak window] picked, openAtLogin, openPalette in
            UserDefaults.standard.set(true, forKey: WelcomeView.seenKey)
            window?.close()
            guard let self else { return }
            if !picked.isEmpty { self.model.installStarters(picked) }
            if openAtLogin { try? SMAppService.mainApp.register() }
            if openPalette { self.palette.toggle() }
        }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        // Room for the note the hotkey picker adds when Spotlight still
        // holds ⌘Space; the window never resizes itself.
        let fitting = host.view.fittingSize
        window.setContentSize(NSSize(width: 560, height: fitting.height + Self.welcomeNoteRoom))
        window.center()
        window.delegate = windows
        welcomeWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        windows.updatePresence()
    }
}
#endif
