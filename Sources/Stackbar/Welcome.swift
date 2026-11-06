#if os(macOS)
import AppKit
import Combine
import ServiceManagement
import StackbarHostCore
import StackbarProtocol
import StackbarUI
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
/// in the palette. Drawn with the Settings pieces (`SettingsGroup`,
/// `SettingsRow`, `PluginIcon`) so it looks like the rest of Stackbar.
struct WelcomeView: View {
    static let seenKey = "welcomeSeen"
    static let width: CGFloat = 600
    static let height: CGFloat = 640

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
        VStack(spacing: 0) {
            // The groups scroll, so a long starter list or the Spotlight note
            // never pushes the buttons out of the window.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsPageHeader(title: "Welcome to Stackbar", subtitle: "Apps, files, sums and every plugin's commands, one keystroke away.") {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .accessibilityHidden(true)
                    } trailing: {
                        EmptyView()
                    }
                    SettingsGroup("Command Palette", footer: "Most people coming from Raycast or Alfred use ⌘Space.") {
                        SettingsRow(title: "Open the palette", caption: "Click to record another hotkey.") {
                            PaletteHotKeyPicker()
                        }
                    }
                    if !starters.isEmpty {
                        SettingsGroup("Start With These Plugins", footer: "Applications, Calculator and File Search are already in. Find more in the Store.") {
                            ForEach(starters, id: \.id) { manifest in
                                starterRow(manifest)
                            }
                        }
                    }
                    SettingsGroup("Startup") {
                        Toggle("Open Stackbar at login", isOn: $openAtLogin)
                            .toggleStyle(TrailingSwitchStyle())
                        if CrashReports.isAvailable {
                            Toggle(isOn: $sendCrashReports) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Send crash reports")
                                    Text("Only when Stackbar itself crashes. No plugin names, logs or files.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(TrailingSwitchStyle())
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            Divider()
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
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: Self.width)
        .frame(minHeight: 360, maxHeight: .infinity)
    }

    private func starterRow(_ manifest: Manifest) -> some View {
        Toggle(isOn: binding(manifest.id)) {
            HStack(spacing: 10) {
                PluginIcon(manifest: manifest, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(manifest.name)
                    if let summary = manifest.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .toggleStyle(TrailingSwitchStyle())
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { picked.contains(id) }, set: { on in if on { picked.insert(id) } else { picked.remove(id) } })
    }
}

extension AppDelegate {
    /// Shows the welcome window once per user.
    func welcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: WelcomeView.seenKey) else { return }
        showWelcome()
    }

    func showWelcome() {
        // A plain titled window at a fixed size; its groups scroll inside.
        // Measuring the SwiftUI content instead came back near zero (the
        // root is height-flexible), so 0.27.0 showed a clipped strip. A
        // transparent full-size title bar with `.preferredContentSize`
        // sizing made AppKit throw (0.22.0 crash), so neither is used.
        let screen = NSScreen.main?.visibleFrame.height ?? WelcomeView.height + 120
        let height = min(WelcomeView.height, max(360, screen - 120))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: WelcomeView.width, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Stackbar"
        window.isReleasedWhenClosed = false
        let starters = model.bundledStore.starters()
        let view = WelcomeView(starters: starters) { [weak self, weak window] picked, openAtLogin, openPalette in
            window?.close()
            guard let self else { return }
            if !picked.isEmpty { self.model.installStarters(picked) }
            if openAtLogin { try? SMAppService.mainApp.register() }
            if openPalette { self.palette.toggle() }
        }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: WelcomeView.width, height: height))
        window.center()
        window.delegate = windows
        // Seen however it is dismissed: a button, ⎋ or the close button.
        // Only the buttons used to count, so closing it brought it back on
        // every launch.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            UserDefaults.standard.set(true, forKey: WelcomeView.seenKey)
        }
        welcomeWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        windows.updatePresence()
    }
}
#endif
