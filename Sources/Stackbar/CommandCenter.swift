#if os(macOS)
import AppKit
import Observation
import StackbarHostCore
import StackbarProtocol

/// Every plugin's commands, as the app uses them: the registry and the
/// user's preferences on disk, per-command hotkeys, running commands for the
/// palette, hotkeys and links, and the open command views.
@MainActor
@Observable
final class CommandCenter {
    @ObservationIgnored let registry: CommandRegistry
    @ObservationIgnored let preferences: CommandPreferences
    @ObservationIgnored let usage: PaletteUsage
    @ObservationIgnored let runner: CommandRunner
    /// Changes whenever the commands or their preferences change, so views
    /// that read the registry redraw.
    private(set) var revision = 0
    /// Commands a plugin declared that were dropped, and why, by plugin id.
    private(set) var problems: [String: [String]] = [:]
    /// Hotkeys the system would not take, by command.
    private(set) var hotKeyProblems: [CommandKey: String] = [:]

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var hotKeys: [CommandKey: (spec: String, hotKey: HotKey)] = [:]
    @ObservationIgnored private var views: [Int: CommandViewModel] = [:]
    @ObservationIgnored private var nextSession = 1

    /// The palette's own shortcut, which no command may take.
    static let paletteHotKey = "ctrl+option+space"

    init(model: AppModel, services: HostServices) {
        let directory = StackbarPaths.dataDirectory
        registry = CommandRegistry(file: directory.appendingPathComponent("commands.json"))
        preferences = CommandPreferences(file: directory.appendingPathComponent("command-preferences.json"))
        usage = PaletteUsage(file: directory.appendingPathComponent("palette-usage.json"))
        let lookup = CommandLookup()
        runner = CommandRunner(registry: registry, services: services) { id in await lookup.target(for: id) }
        self.model = model
        lookup.center = self
    }

    /// Commands known from the last run, so the palette, aliases and hotkeys
    /// work before every plugin has started.
    func start() {
        changed()
    }

    // MARK: - Plugins' commands

    func commandsChanged(_ controller: PluginController, _ specs: [CommandSpec]) {
        let dropped = registry.update(pluginID: controller.pluginID, pluginName: controller.name, specs: specs)
        problems[controller.pluginID] = dropped.isEmpty ? nil : dropped
        changed()
    }

    /// The plugin was uninstalled: its commands go, its preferences stay in
    /// case it comes back.
    func forget(pluginID: String) {
        registry.remove(pluginID: pluginID)
        problems[pluginID] = nil
        for view in views.values where view.entry.pluginID == pluginID { view.close() }
        changed()
    }

    func setOrder(_ pluginIDs: [String]) {
        registry.setOrder(pluginIDs)
        changed()
    }

    /// Saves one command's preference, checking its alias and hotkey.
    func set(_ preference: CommandPreference, for key: CommandKey) throws {
        var others = [Self.paletteHotKey: "the command palette"]
        for controller in model?.controllers ?? [] {
            if let hotkey = controller.manifest?.hotkey { others[hotkey] = controller.name }
        }
        try preferences.set(preference, for: key, otherHotkeys: others)
        changed()
    }

    private func changed() {
        model?.commandsChanged()
        syncHotKeys()
        revision += 1
    }

    // MARK: - Hotkeys

    private func syncHotKeys() {
        var wanted: [CommandKey: String] = [:]
        for entry in registry.entries {
            let preference = preferences[entry.key]
            if preference.enabled, let hotkey = preference.hotkey { wanted[entry.key] = hotkey }
        }
        for (key, registered) in hotKeys where wanted[key] != registered.spec {
            registered.hotKey.unregister()
            hotKeys[key] = nil
        }
        hotKeyProblems = hotKeyProblems.filter { wanted[$0.key] != nil }
        for (key, spec) in wanted where hotKeys[key] == nil {
            guard let parsed = HotKeySpec(spec), let hotKey = HotKey(spec: parsed, action: { [weak self] in self?.hotKeyPressed(key) }) else {
                hotKeyProblems[key] = "\(spec) can't be used as a shortcut"
                continue
            }
            hotKeys[key] = (spec, hotKey)
            hotKeyProblems[key] = nil
        }
    }

    private func hotKeyPressed(_ key: CommandKey) {
        guard let entry = registry.entry(key) else { return }
        if entry.spec.kind == .run, entry.spec.requiredArguments.isEmpty {
            Task { await run(key, source: .hotkey) }
        } else {
            AppDelegate.shared?.palette.open(entry, source: .hotkey)
        }
    }

    // MARK: - Running

    /// Runs a run command, records the use, and shows what happened.
    func run(_ key: CommandKey, arguments: [String: String] = [:], source: InvocationSource, context: InvocationContext? = nil) async {
        usage.record(key.description)
        let outcome = await runner.run(key, arguments: arguments, source: source, context: context)
        if let message = outcome.message { HUD.shared.show(message, isError: outcome.isError) }
    }

    /// Opens a view command: waits for its plugin, then starts the session.
    func openView(_ key: CommandKey, query: CommandQuery = CommandQuery()) async -> Result<CommandViewModel, CommandRunner.Outcome> {
        guard let entry = registry.entry(key) else { return .failure(.failure("\(key) is not a command")) }
        guard entry.spec.kind == .view else { return .failure(.failure("\(entry.spec.title) is not a view")) }
        let supervisor: PluginSupervisor
        switch await runner.supervisor(for: key.pluginID) {
        case .success(let found): supervisor = found
        case .failure(let outcome): return .failure(outcome)
        }
        usage.record(key.description)
        let session = nextSession
        nextSession += 1
        let view = CommandViewModel(session: session, entry: entry, supervisor: supervisor, query: query) { [weak self] in
            self?.views[session] = nil
        }
        views[session] = view
        view.start()
        return .success(view)
    }

    /// A plugin sent a tree for one of its views.
    func received(session: Int, seq: Int, root: ViewNode) {
        views[session]?.received(seq: seq, root: root)
    }

    /// The plugin restarted: its views are gone with the old process.
    func pluginRestarted(_ pluginID: String) {
        for view in views.values where view.entry.pluginID == pluginID { view.pluginRestarted() }
    }

    // MARK: - Looking plugins up

    enum Lookup: Sendable {
        case missing
        case starting
        case ready(CommandRunner.Target)
    }

    func lookup(_ pluginID: String) -> Lookup {
        guard let model else { return .missing }
        guard let controller = model.controller(for: pluginID) else {
            // At launch, plugins are found by file and only then by id.
            return model.controllers.contains(where: \.building) ? .starting : .missing
        }
        if controller.isWaitingForApproval {
            return .ready(.unavailable("\(controller.name) is waiting for you to approve what it asks for. Open it from Settings → Plugins."))
        }
        if let supervisor = controller.supervisor { return .ready(.supervisor(supervisor)) }
        if controller.building { return .starting }
        return .ready(.unavailable(controller.problem.map { "\(controller.name) could not start: \($0)" } ?? "\(controller.name) is not running"))
    }
}

/// Finds a plugin's supervisor for the runner, waiting while it builds.
final class CommandLookup: @unchecked Sendable {
    @MainActor weak var center: CommandCenter?

    func target(for pluginID: String) async -> CommandRunner.Target? {
        let deadline = Date().addingTimeInterval(60)
        while true {
            let found = await MainActor.run { center?.lookup(pluginID) ?? .missing }
            switch found {
            case .missing:
                return nil
            case .ready(let target):
                return target
            case .starting:
                guard Date() < deadline else { return .unavailable("the plugin is taking too long to start") }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

/// One open command view in the palette: its query and arguments, the
/// newest tree, and whether a search is still running.
@MainActor
@Observable
final class CommandViewModel: Identifiable {
    let id: Int
    let entry: CommandRegistry.Entry
    var query: String {
        didSet { if query != oldValue { changed() } }
    }
    var arguments: [String: String] {
        didSet { if arguments != oldValue { changed() } }
    }
    private(set) var root: ViewNode?
    private(set) var isSearching = true
    private(set) var problem: String?

    /// Runs when a submitted form comes back without errors.
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored private var state: ViewSessionState
    @ObservationIgnored private let supervisor: PluginSupervisor
    @ObservationIgnored private let onClose: () -> Void
    @ObservationIgnored private var submitting = false
    @ObservationIgnored private var closed = false
    /// Messages to the plugin go out in order: an action before the close
    /// that follows it.
    @ObservationIgnored private var chain: Task<Void, Never>?

    init(session: Int, entry: CommandRegistry.Entry, supervisor: PluginSupervisor, query: CommandQuery, onClose: @escaping () -> Void) {
        id = session
        self.entry = entry
        self.supervisor = supervisor
        self.onClose = onClose
        self.query = query.text
        var arguments = query.arguments
        for argument in entry.spec.arguments where arguments[argument.name] == nil {
            arguments[argument.name] = argument.defaultValue ?? argument.options?.first ?? ""
        }
        self.arguments = arguments
        state = ViewSessionState(session: session, query: CommandQuery(text: query.text, arguments: arguments))
    }

    func start() {
        deliver(state.open())
    }

    private func changed() {
        guard !closed, let next = state.change(CommandQuery(text: query, arguments: arguments)) else {
            isSearching = state.isSearching
            return
        }
        deliver(next)
    }

    private func deliver(_ send: ViewSessionState.Send) {
        isSearching = true
        let session = id
        let command = entry.spec.id
        let supervisor = supervisor
        enqueue {
            switch send {
            case .open(let seq, let query):
                await supervisor.openView(session: session, command: command, query: query, seq: seq)
            case .update(let seq, let query):
                await supervisor.updateView(session: session, query: query, seq: seq)
            }
        }
    }

    func received(seq: Int, root: ViewNode) {
        guard !closed else { return }
        let (show, next) = state.received(seq: seq, root: root)
        if show {
            self.root = root
            problem = nil
        }
        if let next { deliver(next) }
        isSearching = state.isSearching
        if submitting, show {
            submitting = false
            if !root.hasFormErrors { onFinished?() }
        }
    }

    /// Sends an action inside the view to the plugin. A submitted form waits
    /// for its answer: the palette closes once it comes back without errors.
    func perform(_ action: ActionID, _ value: EventValue? = nil) {
        if case .fields = value { submitting = true }
        let supervisor = supervisor
        enqueue { await supervisor.event(action, value: value) }
    }

    func pluginRestarted() {
        guard !closed else { return }
        problem = "\(entry.pluginName) restarted; open the command again"
        isSearching = false
    }

    func close() {
        guard !closed else { return }
        closed = true
        let session = id
        let supervisor = supervisor
        enqueue { await supervisor.closeView(session: session) }
        onClose()
    }

    private func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        let previous = chain
        chain = Task {
            await previous?.value
            await operation()
        }
    }
}

extension ViewNode {
    /// Whether a form in the tree shows a problem with a field.
    var hasFormErrors: Bool {
        switch self {
        case .form(let form): return form.fields.contains { $0.error != nil }
        case .stack(_, _, let children), .list(_, let children), .section(_, let children): return children.contains(where: \.hasFormErrors)
        default: return false
        }
    }
}

/// A short message near the top of the screen: what a command did.
@MainActor
final class HUD {
    static let shared = HUD()
    private var panel: NSPanel?
    private var hide: Task<Void, Never>?

    func show(_ message: String, isError: Bool = false) {
        let panel = self.panel ?? make()
        self.panel = panel
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = isError ? .systemRed : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
        panel.contentView = effect
        let width = min(500, label.intrinsicContentSize.width + 36)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(NSRect(x: screen.midX - width / 2, y: screen.maxY - screen.height * 0.18, width: width, height: 44), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hide?.cancel()
        hide = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(isError ? 3 : 1.6))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}
#endif
