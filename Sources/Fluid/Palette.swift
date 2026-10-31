#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import FluidHostCore
import FluidProtocol

/// The command palette: ⌃⌥Space from anywhere, type, return. It lists every
/// action every plugin shows on its panel (see `PaletteIndex`).
@MainActor
final class PaletteController {
    private let model: AppModel
    private var panel: NSPanel?
    private var hotKey: HotKey?

    init(model: AppModel) {
        self.model = model
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(rootView: PaletteView(model: model) { [weak self] in self?.panel?.orderOut(nil) })
        panel.center()
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - frame.height * 0.28))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

/// A panel that can take keyboard focus without a title bar.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

struct PaletteView: View {
    let model: AppModel
    let dismiss: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var results: [PaletteIndex.Entry] { model.palette.search(query, limit: 30) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search plugin actions", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(14)
                .focused($focused)
                .onSubmit { run(selection) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onChange(of: query) { _, _ in selection = 0 }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                            PaletteRow(entry: entry, selected: index == selection)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { run(index) }
                        }
                    }
                }
                .onChange(of: selection) { _, newValue in proxy.scrollTo(newValue) }
            }
            if results.isEmpty {
                Text(model.palette.entries.isEmpty ? "No plugin has any actions yet." : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 560, height: 380)
        .onAppear { focused = true }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        selection = min(max(selection + delta, 0), results.count - 1)
        return .handled
    }

    private func run(_ index: Int) {
        guard results.indices.contains(index) else { return }
        let entry = results[index]
        switch entry.kind {
        case .action(let action, let value):
            model.controller(for: entry.pluginID)?.send(action, value)
        case .open(let url):
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        }
        dismiss()
    }
}

struct PaletteRow: View {
    let entry: PaletteIndex.Entry
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol ?? "bolt").frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(entry.pluginName).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.2) : .clear)
    }
}

/// A system-wide hot key through Carbon, which needs no Accessibility
/// permission (unlike a global event monitor).
@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private static var handlerInstalled = false
    private nonisolated(unsafe) static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandler()
        let id = Self.nextID
        self.id = id
        Self.nextID += 1
        Self.actions[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x464C_5544), id: id) // 'FLUD'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
    }

    private let id: UInt32

    /// For a manifest's `hotkey`; `nil` when the key has no Carbon key code.
    convenience init?(spec: HotKeySpec, action: @escaping () -> Void) {
        guard let code = Self.keyCodes[spec.key] else { return nil }
        var modifiers = 0
        if spec.modifiers.contains(.command) { modifiers |= cmdKey }
        if spec.modifiers.contains(.control) { modifiers |= controlKey }
        if spec.modifiers.contains(.option) { modifiers |= optionKey }
        if spec.modifiers.contains(.shift) { modifiers |= shiftKey }
        self.init(keyCode: UInt32(code), modifiers: UInt32(modifiers), action: action)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[id] = nil
    }

    private static let keyCodes: [String: Int] = {
        var codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
            "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
            "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
            "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "space": kVK_Space,
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() { codes["f\(index + 1)"] = code }
        return codes
    }()

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKey.actions[id]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
#endif
