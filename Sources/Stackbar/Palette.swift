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
    private var flagsMonitor: Any?
    let session: PaletteSession

    /// How long a palette closed mid-way (the hot key again, or a click
    /// elsewhere) comes back where it was, as Raycast's "pop to root" does.
    static let resumeWindow: Duration = .seconds(60)
    private var resumable = false
    private var expiry: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        session = PaletteSession(model: model)
        session.dismiss = { [weak self] in self?.hide() }
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
        // ⌘ held shows the ⌘1…⌘9 hints on the first rows.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            MainActor.assumeIsolated {
                guard let self else { return }
                let showing = held && self.panel?.isKeyWindow == true
                if self.session.commandHeld != showing { self.session.commandHeld = showing }
            }
            return event
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible {
            suspend()
        } else {
            show(resume: true)
        }
    }

    /// Hides, keeping the open command and what was typed for
    /// `resumeWindow`; after that it is back at an empty root.
    func suspend() {
        panel?.orderOut(nil)
        noteLeft()
    }

    /// The palette lost focus or was hidden part-way through something.
    private func noteLeft() {
        session.commandHeld = false
        guard !session.isIdle else { return }
        resumable = true
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.resumeWindow)
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            self.resumable = false
            self.session.reset()
        }
    }

    /// Opens the palette on a command: its view, its argument fields, or
    /// (with everything it needs) runs it straight away.
    /// `context` is what the user was in when the command was triggered;
    /// without one, it is read now.
    func open(_ entry: CommandRegistry.Entry, arguments: [String: String] = [:], query: String = "", source: InvocationSource, context: InvocationContext? = nil) {
        if entry.spec.kind == .run, entry.spec.arguments.isEmpty || entry.spec.requiredArguments.allSatisfy({ !(arguments[$0.name] ?? "").isEmpty }) {
            hide()
            let context = context ?? model.commands.captureContext(for: entry.pluginID)
            Task { await model.commands.run(entry.key, arguments: arguments, source: source, context: context) }
            return
        }
        show(context: context)
        session.enter(entry, arguments: arguments, query: query, source: source)
    }

    func hide() {
        panel?.orderOut(nil)
        expiry?.cancel()
        resumable = false
        session.commandHeld = false
        session.reset()
    }

    private func show(context: InvocationContext? = nil, resume: Bool = false) {
        if !isVisible {
            expiry?.cancel()
            if !(resume && resumable) { session.reset() }
            resumable = false
            // Read before Stackbar activates, while the user's app is in front.
            session.context = context ?? model.commands.captureContext()
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Place the whole frame, size included, on the screen the user is
        // working on. Only setting the origin left the first open off center:
        // the window still had its pre-layout size then and was resized after
        // it was placed.
        if let screen = Self.activeScreen() {
            panel.setFrame(Self.frame(on: screen.visibleFrame), display: false)
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        session.shown()
    }

    /// The screen under the pointer, as Spotlight does; the main one otherwise.
    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Centered across, its top a quarter of the way down, in whole points.
    static func frame(on visible: NSRect) -> NSRect {
        let size = PaletteView.size
        return NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.maxY - visible.height * 0.24 - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }

    private func makePanel() -> KeyablePanel {
        // Borderless and clear, so the SwiftUI view's Liquid Glass is the
        // whole window, like Spotlight on macOS 26.
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: PaletteView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // A fixed size: SwiftUI must not resize the window after it is placed.
        let hosting = NSHostingView(rootView: PaletteView(session: session))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: PaletteView.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.session.back() ?? false }
        panel.onClose = { [weak self] in self?.hide() }
        panel.onResign = { [weak self] in self?.noteLeft() }
        return panel
    }
}

/// A panel that can take keyboard focus without a title bar. Esc asks
/// `onCancel` first (pop a stage), and closes when it says no.
final class KeyablePanel: NSPanel {
    var onCancel: (() -> Bool)?
    var onClose: (() -> Void)?
    /// Lost key status: clicked away, or hidden.
    var onResign: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        if let onClose { onClose() } else { orderOut(nil) }
    }
}

struct PaletteView: View {
    @Bindable var session: PaletteSession
    @FocusState private var focus: Field?

    static let size = CGSize(width: 680, height: 440)
    static let cornerRadius: CGFloat = 26

    enum Field: Hashable {
        case search
        case argument(String)
        case actionSearch
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .frame(height: 58)
            LoadingBar(active: session.isLoading)
            ZStack(alignment: .bottomTrailing) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if session.showingActions {
                    ActionsPanel(session: session, focus: $focus)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
                }
            }
            .animation(.snappy(duration: 0.18), value: session.showingActions)
            Divider().opacity(0.6)
            ActionBar(session: session)
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(height: 44)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onAppear { focusFirst() }
        .onChange(of: session.shownCount) { _, _ in focusFirst() }
        .onChange(of: session.stack.map(\.id)) { _, _ in focusFirst() }
        .onChange(of: session.showingActions) { _, showing in
            if showing {
                DispatchQueue.main.async { focus = .actionSearch }
            } else {
                focusFirst()
            }
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            if session.stack.isEmpty {
                Image(systemName: "magnifyingglass").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                searchField(text: $session.query, prompt: "Search commands and plugin actions")
            } else {
                Button {
                    _ = session.back()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Back (Esc)")
                ForEach(Array(session.stack.enumerated()), id: \.element.id) { index, stage in
                    Text(stage.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(index == session.stack.count - 1 ? .regular.tint(.accentColor.opacity(0.35)) : .regular, in: .capsule)
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
        }
        .font(.title2)
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
        let modifiers = press.modifiers.intersection([.command, .shift, .option, .control])
        if modifiers == .command, press.key == .return, session.submitSecondary() {
            return .handled
        }
        if modifiers == .command, let digit = Int(String(press.characters)), (1...9).contains(digit), session.activate(line: digit) {
            return .handled
        }
        if modifiers == [.command, .shift], String(press.key.character).lowercased() == "f", session.toggleFavoriteOfSelection() {
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
        let sections = session.sections
        let selected = session.selectedEntry?.id
        // ⌘1…⌘9 count the lines as drawn.
        let numbers = session.commandHeld
            ? Dictionary(session.results.prefix(9).enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { first, _ in first })
            : [:]
        ScrollViewReader { proxy in
            ScrollView {
                // One identity per row, the entry's: the highlight and the
                // scroll follow the entry, not its position in the list.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        SectionHeader(title: section.title)
                        ForEach(section.entries) { entry in
                            PaletteRow(entry: entry, accent: session.accent(of: entry.pluginID), pluginSymbol: session.manifest(of: entry.pluginID)?.symbol,
                                       selected: entry.id == selected, number: numbers[entry.id])
                                .contentShape(Rectangle())
                                .onTapGesture { session.activate(entry) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .onChange(of: selected) { _, newValue in
                if let newValue { proxy.scrollTo(newValue) }
            }
        }
        .overlay {
            if sections.isEmpty {
                Text(session.model.palette.all.isEmpty ? "No plugin has any commands or actions yet." : "No matches")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A group's title over its rows, as in Raycast's root list.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

struct PaletteRow: View {
    let entry: PaletteIndex.Entry
    let accent: Accent?
    let pluginSymbol: String?
    let selected: Bool
    /// Its ⌘ number while ⌘ is held.
    var number: Int?

    var body: some View {
        HStack(spacing: 10) {
            // The entry's symbol on a tile in its plugin's colour, so each
            // plugin is told apart at a glance.
            SettingsIconTile(symbol: iconName, color: PluginIcon.color(accent), size: 24)
            Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let alias = entry.alias {
                Text(alias)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 5))
            }
            if let number {
                Keycap("⌘\(number)")
            } else {
                Text(kindLabel).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 8)
    }

    /// The entry's own symbol, the plugin's, or one for its kind.
    private var iconName: String {
        for name in [entry.symbol, pluginSymbol].compactMap({ $0 }) where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return symbol
    }

    /// A command without its own subtitle names its plugin, as Raycast does.
    private var subtitle: String? {
        switch entry.kind {
        case .command, .showPanel: return entry.subtitle ?? entry.pluginName
        case .navigate, .action, .open: return entry.subtitle
        }
    }

    /// Raycast's right-hand label: what the entry is, and whose.
    private var kindLabel: String {
        switch entry.kind {
        case .command: return "Command"
        case .showPanel: return "Panel"
        case .navigate, .action, .open: return entry.pluginName
        }
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
            if let items = RowFilter.items(in: root, query: view.query) {
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

    private func list(_ items: [RowFilter.Item]) -> some View {
        let rows = items.compactMap { if case .row(let row) = $0 { return row } else { return nil } }
        let selectedKey = session.selectedRow(of: view)?.key
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(let title):
                            Text(title.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
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
            .onChange(of: selectedKey) { _, newValue in
                if let newValue { proxy.scrollTo(newValue) }
            }
            .overlay {
                if rows.isEmpty {
                    Text(view.isSearching ? "Searching…" : "No results").foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// ⌘K: what can be done with the selection, in groups, with its own search
/// field at the bottom as in Raycast.
struct ActionsPanel: View {
    @Bindable var session: PaletteSession
    var focus: FocusState<PaletteView.Field?>.Binding

    var body: some View {
        let actions = session.filteredActions
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        // A new group: a line, then its title.
                        if action.section != (index > 0 ? actions[index - 1].section : nil) {
                            if index > 0 { Divider().padding(.vertical, 4).padding(.horizontal, 6) }
                            if let section = action.section {
                                Text(section)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 2)
                            }
                        }
                        row(action, selected: index == session.actionSelection)
                            .onTapGesture { session.runAction(index) }
                    }
                    if actions.isEmpty {
                        Text("No matching actions")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(6)
            Divider()
            TextField("Search for actions…", text: $session.actionQuery)
                .textFieldStyle(.plain)
                .focused(focus, equals: .actionSearch)
                .onSubmit { session.submit() }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .frame(width: 300)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func row(_ action: PaletteSession.Action, selected: Bool) -> some View {
        HStack {
            Text(action.title).foregroundStyle(action.role == .critical ? Color.red : Color.primary)
            Spacer(minLength: 16)
            if let shortcut = action.shortcut {
                Keycap(Self.glyphs(shortcut))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(Rectangle())
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

/// A key in the action bar and ⌘K, drawn as a small keycap.
struct Keycap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 5))
    }
}

/// Raycast's bottom bar: the plugin in charge (or what went wrong) on the
/// left; Return's action and ⌘K as buttons on the right.
struct ActionBar: View {
    @Bindable var session: PaletteSession

    var body: some View {
        HStack(spacing: 8) {
            if let problem = session.problem {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(problem).font(.callout).lineLimit(1).help(problem)
            } else if let pluginID = session.currentPluginID, let name = pluginName {
                PluginIcon(symbol: session.manifest(of: pluginID)?.symbol, accent: session.accent(of: pluginID), size: 18)
                Text(name).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Stackbar").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let primary = session.primaryTitle {
                BarButton(title: primary, key: "↩", emphasized: true) { session.submit() }
            }
            if let secondary = session.secondaryTitle {
                BarButton(title: secondary, key: "⌘↩", emphasized: false) { _ = session.submitSecondary() }
            }
            if !session.actions.isEmpty {
                Divider().frame(height: 16)
                BarButton(title: "Actions", key: "⌘K", emphasized: false) { session.toggleActions() }
            }
        }
    }

    private var pluginName: String? {
        switch session.top {
        case .view(let view): return view.entry.pluginName
        case .arguments(let entry, _): return entry.pluginName
        case .none: return session.selectedEntry?.pluginName
        }
    }
}

/// A clickable action-bar item: its title and its key.
struct BarButton: View {
    let title: String
    let key: String
    let emphasized: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.callout.weight(emphasized ? .semibold : .regular))
                    .foregroundStyle(emphasized ? Color.primary : Color.secondary)
                Keycap(key)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A hairline under the search field that sweeps while a plugin works, in
/// place of a spinner.
struct LoadingBar: View {
    let active: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08))
                if active {
                    TimelineView(.animation) { timeline in
                        let width = geometry.size.width
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .accentColor, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: width * 0.35)
                            .offset(x: -width * 0.35 + (width * 1.35) * phase)
                    }
                }
            }
        }
        .frame(height: active ? 2 : 1)
        .clipped()
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
