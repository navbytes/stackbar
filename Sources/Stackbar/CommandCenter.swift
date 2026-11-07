#if os(macOS)
import AppIntents
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
    /// What the palette learned: use, picks and pins.
    @ObservationIgnored let memory: PaletteMemory
    var usage: PaletteUsage { memory.usage }
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
    @ObservationIgnored private let indexer = CommandSpotlightIndexer()
    /// How quickly each root search answers; a slow one sits out a while.
    @ObservationIgnored let rootBudget = RootSearchBudget()

    /// The palette's own shortcut, which no command may take.
    static let paletteHotKey = "ctrl+option+space"

    init(model: AppModel, services: HostServices) {
        let directory = StackbarPaths.dataDirectory
        registry = CommandRegistry(file: directory.appendingPathComponent("commands.json"))
        preferences = CommandPreferences(file: directory.appendingPathComponent("command-preferences.json"))
        memory = PaletteMemory(directory: directory)
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
        // A plugin that replaces others takes over their shortcuts, once,
        // as soon as it says which commands it has.
        if let manifest = controller.manifest, manifest.replaces?.isEmpty == false {
            model?.handOver(to: manifest, commands: registry.commands(for: manifest.id))
        }
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

    /// The switch for all of Spotlight and Shortcuts; off empties the index.
    func setSpotlightEnabled(_ enabled: Bool) {
        preferences.spotlightEnabled = enabled
        changed()
    }

    /// Preferences changed underneath (a plugin handover moved some):
    /// register the hotkeys again and redraw.
    func reloadPreferences() {
        changed()
    }

    private func changed() {
        model?.commandsChanged()
        syncHotKeys()
        indexer.sync(CommandIndexing.items(registry: registry, preferences: preferences, usage: usage))
        revision += 1
    }

    // MARK: - Hotkeys

    private func syncHotKeys() {
        // A plugin may give its manifest hotkey to one of its commands
        // (Clipboard History's ⌘⇧V opens its palette view).
        var manifests: [String: Manifest] = [:]
        for controller in model?.controllers ?? [] {
            if let manifest = controller.manifest { manifests[controller.pluginID] = manifest }
        }
        let wanted = CommandHotKeys.wanted(entries: registry.entries, preference: { self.preferences[$0] }, manifests: manifests)
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
        // Pressed again while its view is open: close it, like a panel.
        if let palette = AppDelegate.shared?.palette, palette.isShowing(key) {
            palette.hide()
            return
        }
        start(entry, source: .hotkey)
    }

    // MARK: - Starting

    /// The plan for starting a command, with the user's settings for it.
    func plan(_ entry: CommandRegistry.Entry, source: InvocationSource, arguments: [String: String] = [:], input: String = "") -> CommandStart.Plan {
        CommandStart.plan(entry, preference: preferences[entry.key], source: source, arguments: arguments, input: input)
    }

    /// Starts a command from outside the palette: runs it here, or opens
    /// the palette on its fields or view, or says why it can't start.
    /// `context` is what the user was in; without one, it is read now.
    func start(_ entry: CommandRegistry.Entry, arguments: [String: String] = [:], input: String = "", source: InvocationSource, context: InvocationContext? = nil) {
        carryOut(plan(entry, source: source, arguments: arguments, input: input), for: entry, source: source, context: context)
    }

    func carryOut(_ plan: CommandStart.Plan, for entry: CommandRegistry.Entry, source: InvocationSource, context: InvocationContext? = nil) {
        // Read before the palette takes focus.
        let context = context ?? captureContext(for: entry.pluginID)
        switch plan {
        case .refuse(let message):
            HUD.shared.show(message, isError: true)
        case .run(let arguments):
            Task { await run(entry.key, arguments: arguments, source: source, context: context) }
        case .ask, .openView:
            AppDelegate.shared?.palette.open(entry, plan: plan, source: source, context: context)
        }
    }

    // MARK: - Context

    /// What the user is in, read the moment a command is triggered (before
    /// the palette takes focus), when a plugin that may read it could get
    /// it: the one given, or any, for the palette. Supervisors drop it for
    /// plugins without `.context`.
    func captureContext(for pluginID: String? = nil) -> InvocationContext? {
        guard let model else { return nil }
        let readers = model.controllers.filter(\.readsContext)
        guard pluginID.map({ id in readers.contains { $0.pluginID == id } }) ?? !readers.isEmpty else { return nil }
        return MacContext.capture()
    }

    // MARK: - Running

    /// Runs a run command, records the use, and shows what happened.
    func run(_ key: CommandKey, arguments: [String: String] = [:], source: InvocationSource, context: InvocationContext? = nil) async {
        memory.used(key)
        donate(key)
        let outcome = await runner.run(key, arguments: arguments, source: source, context: context)
        if let message = outcome.message { HUD.shared.show(message, isError: outcome.isError) }
    }

    /// A keyword typed in some app (text expansion): starts its command
    /// there, as a hotkey does.
    func runFromExpansion(_ key: CommandKey) {
        guard let entry = registry.entry(key) else { return }
        start(entry, source: .hotkey)
    }

    /// Tells Spotlight the user ran this, so it suggests it.
    private func donate(_ key: CommandKey) {
        guard let entry = registry.entry(key), CommandIndexing.isExposed(entry, preferences: preferences) else { return }
        let item = CommandIndexing.item(entry, preferences: preferences, usage: usage)
        Task {
            _ = try? await IntentDonationManager.shared.donate(intent: RunCommandIntent(command: CommandEntity(item)))
        }
    }

    // MARK: - Spotlight and Shortcuts

    /// The command and its plan, or the reason it can't start, as an error
    /// Spotlight and Shortcuts show. `input` fills the first argument, or a
    /// view's search.
    private func intentPlan(_ id: String, input: String?) throws -> (CommandRegistry.Entry, CommandStart.Plan) {
        guard let key = CommandKey(id), let entry = registry.entry(key) else { throw CommandIntentError("That command is no longer installed") }
        let started = self.plan(entry, source: .spotlight, input: input ?? "")
        if case .refuse(let message) = started { throw CommandIntentError(message) }
        return (entry, started)
    }

    /// Spotlight's or Shortcuts' Run: a run command with what it needs runs
    /// here and says what happened; anything else opens in the palette.
    func runFromIntent(_ id: String, input: String?) async throws -> String {
        let (entry, plan) = try intentPlan(id, input: input)
        // Spotlight is an overlay: the user's app is still frontmost.
        let context = captureContext(for: entry.pluginID)
        guard case .run(let arguments) = plan else {
            carryOut(plan, for: entry, source: .spotlight, context: context)
            return "Opened \(entry.spec.title) in Stackbar"
        }
        memory.used(entry.key)
        let outcome = await runner.run(entry.key, arguments: arguments, source: .spotlight, context: context)
        if outcome.isError { throw CommandIntentError(outcome.message ?? "\(entry.spec.title) failed") }
        return outcome.message ?? "Done"
    }

    /// Spotlight opened an indexed command: the palette at that command, or
    /// it runs when it has what it needs.
    func openFromIntent(_ id: String, input: String?) async throws {
        let (entry, plan) = try intentPlan(id, input: input)
        carryOut(plan, for: entry, source: .spotlight)
    }

    /// Opens a view command: waits for its plugin, then starts the session.
    /// `recordUse` is false for the palette's root search, which opens views
    /// the user didn't choose.
    func openView(_ key: CommandKey, query: CommandQuery = CommandQuery(), context: InvocationContext? = nil, recordUse: Bool = true) async -> Result<CommandViewModel, CommandRunner.Outcome> {
        guard let entry = registry.entry(key) else { return .failure(.failure("\(key) is not a command")) }
        guard entry.spec.kind == .view else { return .failure(.failure("\(entry.spec.title) is not a view")) }
        let supervisor: PluginSupervisor
        switch await runner.supervisor(for: key.pluginID) {
        case .success(let found): supervisor = found
        case .failure(let outcome): return .failure(outcome)
        }
        if recordUse { memory.used(key) }
        let session = nextSession
        nextSession += 1
        let view = CommandViewModel(session: session, entry: entry, supervisor: supervisor, query: query, context: context) { [weak self] in
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

    /// The plugin's process changed state. Restarting: its views are gone
    /// with the old process, so they wait and open again once it runs.
    /// Failed or stopped: they say so, instead of spinning forever.
    func pluginStateChanged(_ pluginID: String, _ state: PluginSupervisor.State) {
        let affected = views.values.filter { $0.entry.pluginID == pluginID }
        switch state {
        case .restarting:
            rootBudget.forget(pluginID: pluginID)
            affected.forEach { $0.pluginRestarted() }
        case .running:
            affected.forEach { $0.pluginRunning() }
        case .failed(let reason):
            affected.forEach { $0.pluginStopped("\($0.entry.pluginName) stopped: \(reason)") }
        case .stopped:
            affected.forEach { $0.pluginStopped("\($0.entry.pluginName) is turned off") }
        case .starting:
            break
        }
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
            return .ready(.unavailable("\(controller.name) is waiting for you to approve what it asks for. Open its page in Settings."))
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
    /// Counts the trees shown, so root search filters rows once per answer.
    /// Observed: a list that reads only this redraws when an answer arrives.
    private(set) var answers = 0
    /// When the newest tree arrived, to time root search's answers.
    @ObservationIgnored private(set) var answeredAt: Date?

    /// Runs when a submitted form comes back without errors.
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored private var state: ViewSessionState
    @ObservationIgnored private let supervisor: PluginSupervisor
    /// What the user was in when the view was opened.
    @ObservationIgnored private let context: InvocationContext?
    @ObservationIgnored private let onClose: () -> Void
    @ObservationIgnored private var submitting = false
    @ObservationIgnored private var closed = false
    /// Closed: the plugin has dropped the view, so nothing more goes to it.
    var isClosed: Bool { closed }
    /// Messages to the plugin go out in order: an action before the close
    /// that follows it.
    @ObservationIgnored private var chain: Task<Void, Never>?

    init(session: Int, entry: CommandRegistry.Entry, supervisor: PluginSupervisor, query: CommandQuery, context: InvocationContext? = nil, onClose: @escaping () -> Void) {
        id = session
        self.entry = entry
        self.supervisor = supervisor
        self.context = context
        self.onClose = onClose
        self.query = query.text
        let arguments = CommandStart.filled(entry.spec, query.arguments)
        self.arguments = arguments
        state = ViewSessionState(session: session, query: CommandQuery(text: query.text, arguments: arguments))
    }

    func start() {
        deliver(state.open())
    }

    private func changed() {
        // Waiting for a restart or stopped: the newest text goes out when
        // the session opens again.
        guard !waitingForPlugin, !stopped else { return }
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
        let context = context
        enqueue {
            switch send {
            case .open(let seq, let query):
                await supervisor.openView(session: session, command: command, query: query, seq: seq, context: context)
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
            answers += 1
            answeredAt = Date()
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
        // After closeView the plugin has no handler for the view's actions.
        guard canAct else { return }
        if case .fields = value { submitting = true }
        let supervisor = supervisor
        enqueue { await supervisor.event(action, value: value) }
    }

    /// Whether an action can reach the plugin now.
    var canAct: Bool { !closed && !waitingForPlugin && !stopped }
    /// Stopped or failed: nothing will answer.
    var isStopped: Bool { stopped }
    @ObservationIgnored private var waitingForPlugin = false
    @ObservationIgnored private var stopped = false

    func pluginRestarted() {
        guard !closed else { return }
        waitingForPlugin = true
        stopped = false
        problem = "\(entry.pluginName) restarted; reconnecting…"
        isSearching = true
    }

    /// Running again after a restart: the session opens again with what is
    /// typed now, so the list comes back without reopening the command.
    func pluginRunning() {
        guard !closed, waitingForPlugin || stopped else { return }
        waitingForPlugin = false
        stopped = false
        problem = nil
        deliver(state.reopen(CommandQuery(text: query, arguments: arguments)))
    }

    func pluginStopped(_ message: String) {
        guard !closed else { return }
        waitingForPlugin = false
        stopped = true
        problem = message
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

extension CommandViewModel: RootSearchView {}
#endif
