#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import StackbarHostCore
import StackbarProtocol

import StackbarUI

/// The command palette: ⌃⌥Space from anywhere, type, return. It lists every
/// plugin's commands first, then every action plugins show on their panels
/// (see `PaletteIndex`), and hosts command views and argument fields.
@MainActor
final class PaletteController {
    private let model: AppModel
    private var panel: KeyablePanel?
    private var hotKey: HotKey?
    let session: PaletteSession

    init(model: AppModel) {
        self.model = model
        session = PaletteSession(model: model)
        session.dismiss = { [weak self] in self?.hide() }
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Opens the palette on a command: its view, its argument fields, or
    /// (with everything it needs) runs it straight away.
    func open(_ entry: CommandRegistry.Entry, arguments: [String: String] = [:], source: InvocationSource) {
        if entry.spec.kind == .run, entry.spec.arguments.isEmpty || entry.spec.requiredArguments.allSatisfy({ !(arguments[$0.name] ?? "").isEmpty }) {
            hide()
            Task { await model.commands.run(entry.key, arguments: arguments, source: source) }
            return
        }
        show()
        session.enter(entry, arguments: arguments, source: source)
    }

    func hide() {
        panel?.orderOut(nil)
        session.reset()
    }

    private func show() {
        if !isVisible { session.reset() }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - frame.height * 0.24 - panel.frame.height))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        session.shown()
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
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
        panel.contentViewController = NSHostingController(rootView: PaletteView(session: session))
        panel.onCancel = { [weak self] in self?.session.back() ?? false }
        panel.onClose = { [weak self] in self?.hide() }
        return panel
    }
}

/// A panel that can take keyboard focus without a title bar. Esc asks
/// `onCancel` first (pop a stage), and closes when it says no.
final class KeyablePanel: NSPanel {
    var onCancel: (() -> Bool)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        if let onClose { onClose() } else { orderOut(nil) }
    }
}

struct PaletteView: View {
    @Bindable var session: PaletteSession
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case search
        case argument(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            if let problem = session.problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            Divider()
            ZStack(alignment: .bottomTrailing) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if session.showingActions {
                    ActionsPanel(session: session)
                        .padding(10)
                }
            }
            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .frame(width: 640, height: 420)
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onAppear { focusFirst() }
        .onChange(of: session.shownCount) { _, _ in focusFirst() }
        .onChange(of: session.stack.map(\.id)) { _, _ in focusFirst() }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            if session.stack.isEmpty {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                searchField(text: $session.query, prompt: "Search commands and plugin actions")
            } else {
                Button {
                    _ = session.back()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back (Esc)")
                ForEach(Array(session.stack.enumerated()), id: \.element.id) { index, stage in
                    Text(stage.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(index == session.stack.count - 1 ? 0.2 : 0.08), in: Capsule())
                }
                switch session.top {
                case .view(let view):
                    ViewHeader(view: view, focus: $focus, onSubmit: { session.submit() })
                case .arguments(let entry, _):
                    ArgumentFields(arguments: entry.spec.arguments, values: $session.argumentValues, focus: $focus, onSubmit: { session.submitArguments() })
                    Spacer(minLength: 0)
                case .none:
                    EmptyView()
                }
            }
            if session.opening {
                ProgressView().controlSize(.small)
            }
        }
        .font(.title3)
    }

    private func searchField(text: Binding<String>, prompt: String) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .focused($focus, equals: .search)
            .onSubmit { session.submit() }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch session.top {
        case .none:
            RootResults(session: session)
        case .arguments(let entry, _):
            VStack(spacing: 6) {
                Image(systemName: entry.spec.symbol ?? "command").font(.largeTitle).foregroundStyle(.secondary)
                Text(entry.spec.title).font(.headline)
                Text("Fill in the fields above and press Return. Tab moves between them.").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .view(let view):
            CommandViewBody(session: session, view: view)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Text(footerName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let primary = session.primaryTitle {
                KeyHint(key: "↩", title: primary)
            }
            if !session.actions.isEmpty {
                KeyHint(key: "⌘K", title: "Actions")
            }
            KeyHint(key: "esc", title: session.stack.isEmpty ? "Close" : "Back")
        }
    }

    private var footerName: String {
        switch session.top {
        case .view(let view): return view.entry.pluginName
        case .arguments(let entry, _): return entry.pluginName
        case .none:
            let results = session.results
            return results.indices.contains(session.selection) ? results[session.selection].pluginName : "Stackbar"
        }
    }

    // MARK: Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let plain = press.modifiers.isDisjoint(with: [.command, .option, .control])
        switch press.key {
        case .downArrow where plain:
            session.move(1)
            return .handled
        case .upArrow where plain:
            session.move(-1)
            return .handled
        default:
            break
        }
        if press.modifiers.intersection([.command, .shift, .option, .control]) == .command, press.key.character == "k" {
            session.toggleActions()
            return .handled
        }
        if session.shortcut(matching: { KeyShortcut($0)?.matches(press) ?? false }) {
            return .handled
        }
        if session.top == nil, press.modifiers.intersection([.command, .shift, .option, .control]) == [.command, .shift], String(press.key.character).lowercased() == "c" {
            let actions = session.actions
            if let index = actions.firstIndex(where: { $0.shortcut == "cmd+shift+c" }) { session.runAction(index) }
            return .handled
        }
        return .ignored
    }

    private func focusFirst() {
        // After the window is key, or focus doesn't take.
        DispatchQueue.main.async {
            switch session.top {
            case .arguments(let entry, _):
                let empty = entry.spec.arguments.first { (session.argumentValues[$0.name] ?? "").isEmpty && $0.options == nil }
                focus = (empty ?? entry.spec.arguments.first).map { .argument($0.name) }
            case .view, .none:
                focus = .search
            }
        }
    }
}

/// The root: every command and panel action that matches, best first.
struct RootResults: View {
    @Bindable var session: PaletteSession

    var body: some View {
        let results = session.results
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        PaletteRow(entry: entry, selected: index == session.selection)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { session.activate(entry) }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: session.selection) { _, newValue in proxy.scrollTo(newValue) }
        }
        .overlay {
            if results.isEmpty {
                Text(session.model.palette.all.isEmpty ? "No plugin has any commands or actions yet." : "No matches")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PaletteRow: View {
    let entry: PaletteIndex.Entry
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol ?? symbol).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let alias = entry.alias {
                Text(alias)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
            Text(entry.pluginName).font(.caption).foregroundStyle(.secondary)
            if case .command = entry.kind {
                Text("Command").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.2) : .clear)
    }

    private var symbol: String {
        switch entry.kind {
        case .command(let spec): return spec.kind == .view ? "list.bullet.rectangle" : "command"
        case .navigate: return "arrow.right.circle"
        case .showPanel: return "macwindow"
        case .action, .open: return "bolt"
        }
    }
}

/// A view command's search field and argument fields, in the header.
struct ViewHeader: View {
    @Bindable var view: CommandViewModel
    var focus: FocusState<PaletteView.Field?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField("Search \(view.entry.spec.title)", text: $view.query)
            .textFieldStyle(.plain)
            .focused(focus, equals: .search)
            .onSubmit(onSubmit)
        ArgumentFields(arguments: view.entry.spec.arguments, values: $view.arguments, focus: focus, onSubmit: onSubmit)
        if view.isSearching {
            ProgressView().controlSize(.small).help("Searching…")
        }
    }
}

/// A command's arguments as small inline fields, a menu for a fixed choice.
struct ArgumentFields: View {
    let arguments: [ArgumentSpec]
    @Binding var values: [String: String]
    var focus: FocusState<PaletteView.Field?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        ForEach(arguments, id: \.name) { argument in
            if let options = argument.options {
                Picker(argument.placeholder, selection: binding(argument.name)) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .font(.callout)
            } else {
                TextField(argument.placeholder + (argument.required && argument.defaultValue == nil ? "" : " (optional)"), text: binding(argument.name))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .frame(width: 150)
                    .focused(focus, equals: .argument(argument.name))
                    .onSubmit(onSubmit)
            }
        }
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }
}

/// A command view's tree: a list of rows driven by the palette's keyboard,
/// or anything else (a detail, a form) drawn as on a panel.
struct CommandViewBody: View {
    @Bindable var session: PaletteSession
    let view: CommandViewModel

    var body: some View {
        if let problem = view.problem {
            ContentUnavailableView(problem, systemImage: "exclamationmark.triangle")
        } else if let root = view.root {
            if let items = PaletteSession.items(root, query: view.query) {
                list(items)
            } else {
                ScrollView {
                    NodeView(node: root) { action, value in session.send(action, value, in: view) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func list(_ items: [PaletteSession.ListItem]) -> some View {
        let rows = items.compactMap { if case .row(let row) = $0 { return row } else { return nil } }
        let selectedKey = rows.indices.contains(session.selection) ? rows[session.selection].key : nil
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(let title):
                            Text(title.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        case .row(let row):
                            RowView(row: row) { action, _ in
                                if let ref = row.actions.first(where: { $0.id == action }) { session.perform(ref, in: view) }
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .environment(\.stackbarSelectedRow, selectedKey)
            .onChange(of: session.selection) { _, _ in
                if let selectedKey { proxy.scrollTo(selectedKey) }
            }
            .overlay {
                if rows.isEmpty {
                    Text(view.isSearching ? "Searching…" : "No results").foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// ⌘K: what can be done with the selection.
struct ActionsPanel: View {
    @Bindable var session: PaletteSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(session.actions.enumerated()), id: \.element.id) { index, action in
                HStack {
                    Text(action.title).foregroundStyle(action.role == .critical ? Color.red : Color.primary)
                    Spacer(minLength: 16)
                    if let shortcut = action.shortcut {
                        Text(Self.glyphs(shortcut)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(index == session.actionSelection ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .onTapGesture { session.runAction(index) }
            }
        }
        .padding(6)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    /// `cmd+shift+c` as ⌘⇧C.
    static func glyphs(_ shortcut: String) -> String {
        shortcut.lowercased().split(separator: "+").map { part -> String in
            switch part {
            case "cmd", "command": return "⌘"
            case "shift": return "⇧"
            case "opt", "option", "alt": return "⌥"
            case "ctrl", "control": return "⌃"
            case "return", "enter": return "↩"
            case "delete", "backspace": return "⌫"
            default: return part.uppercased()
            }
        }.joined()
    }
}

struct KeyHint: View {
    let key: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(key)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
        }
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
