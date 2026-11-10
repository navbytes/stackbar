#if os(macOS)
import AppKit
import Observation
import StackbarHostCore
import StackbarProtocol

/// What the palette is showing: the search over everything at the root, and
/// a stack above it of a command's argument fields or its live view. Esc pops
/// the stack; at the root it closes the palette.
@MainActor
@Observable
final class PaletteSession {
    enum Stage: Identifiable {
        /// A run command's argument fields, filled before it runs.
        case arguments(CommandRegistry.Entry, source: InvocationSource)
        /// A view command, live.
        case view(CommandViewModel)
        /// The command's plugin waits for the user to allow what it asks
        /// for: Return allows it and carries on with `plan`.
        case approval(CommandRegistry.Entry, plan: CommandStart.Plan, source: InvocationSource)

        var id: String {
            switch self {
            case .arguments(let entry, _): return "arguments|\(entry.key)"
            case .view(let view): return "view|\(view.id)"
            case .approval(let entry, _, _): return "approval|\(entry.key)"
            }
        }

        var title: String {
            switch self {
            case .arguments(let entry, _): return entry.spec.title
            case .view(let view): return view.entry.spec.title
            case .approval(let entry, _, _): return entry.spec.title
            }
        }
    }

    /// Something ⌘K offers for the selection.
    struct Action: Identifiable {
        var title: String
        var shortcut: String?
        var role: Role = .primary
        /// The group ⌘K lists it under; nil for the first, untitled one.
        var section: String?
        var perform: @MainActor () -> Void
        var id: String { title }
    }

    let model: AppModel
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            selection.reset()
            feedRootSearch()
        }
    }
    /// The selected root entry, or the selected row of a list view, by id:
    /// it stays on its line while the list reorders under it.
    private(set) var selection = ListSelection()
    private(set) var stack: [Stage] = []
    /// The argument fields' values while a run command waits for them.
    var argumentValues: [String: String] = [:]
    var showingActions = false
    var actionSelection = 0
    /// What is typed in ⌘K's own search field.
    var actionQuery = "" {
        didSet { if actionQuery != oldValue { actionSelection = 0 } }
    }
    /// Why the last thing didn't work, shown in the action bar.
    private(set) var problem: String?
    /// A view command is waiting for its plugin.
    private(set) var opening = false
    /// What the user was in when the palette opened; commands started from
    /// it get this.
    var context: InvocationContext?
    /// Changes each time the palette opens, to take focus again.
    private(set) var shownCount = 0
    /// ⌘ is held: the first rows show their ⌘1…⌘9.
    var commandHeld = false
    /// The plugin search the palette is inside: its name, then Tab, as in
    /// Spotlight. Only its rows show until Esc, or Delete in an empty field.
    private(set) var scope: CommandRegistry.Entry?
    /// Nothing to come back to: no open command, no plugin search, nothing typed.
    var isIdle: Bool { stack.isEmpty && query.isEmpty && scope == nil }

    /// The Settings key for compact mode: only the search field shows until
    /// the user types, like Spotlight.
    nonisolated static let compactKey = "paletteCompact"
    /// Set from Settings; the palette reads it each time it is shown.
    var compact = UserDefaults.standard.bool(forKey: PaletteSession.compactKey)
    /// Compact and nothing to show yet: just the search field.
    var collapsed: Bool { compact && isIdle && !showingActions }
    /// Told when `collapsed` flips, so the window can grow or shrink.
    @ObservationIgnored var onCollapsedChange: (Bool) -> Void = { _ in }
    @ObservationIgnored var dismiss: () -> Void = {}
    /// Bumped by each view open and by reset and back, so an open that
    /// finishes late knows it was abandoned.
    @ObservationIgnored private var openToken = 0

    init(model: AppModel) {
        self.model = model
        rootSearch = RootSearchSession(budget: model.commands.rootBudget)
        rootSearch.onChange = { [weak self] in self?.rootViewsRevision += 1 }
    }

    var top: Stage? { stack.last }

    func shown() {
        shownCount += 1
        // The Store window loads its indexes when it opens; the suggestions
        // need them before that. Once per launch, in the background.
        if !storeRequested, let store = model.store, store.catalogs.isEmpty {
            storeRequested = true
            Task { await store.load() }
        }
    }

    /// Back to an empty root, closing every open view.
    func reset() {
        for stage in stack.reversed() {
            if case .view(let view) = stage { view.close() }
        }
        stack = []
        scope = nil
        query = ""
        closeRootSearch()
        selection.reset()
        cache.clear()
        argumentValues = [:]
        showingActions = false
        actionQuery = ""
        problem = nil
        opening = false
        openToken += 1
        context = nil
    }

    /// Esc: hides ⌘K, then pops a stage. False at the root (close).
    func back() -> Bool {
        if showingActions {
            showingActions = false
            actionQuery = ""
            return true
        }
        // Esc while an action asks for its second press forgets it.
        if case .view(let view)? = top, view.cancelConfirmation() { return true }
        // Esc while a command is still opening cancels it.
        if opening {
            openToken += 1
            opening = false
            return true
        }
        // Esc inside a plugin's search goes back to the main search.
        if stack.isEmpty, scope != nil {
            leaveScope()
            return true
        }
        guard let last = stack.popLast() else { return false }
        if case .view(let view) = last { view.close() }
        selection.reset()
        problem = nil
        argumentValues = [:]
        return true
    }

    private func finish() {
        dismiss()
    }

    // MARK: - The root

    /// The root's search, kept until the query or the index changes: the
    /// view, the footer, ⌘K and every arrow press ask for it.
    @ObservationIgnored private var cache = PaletteRootCache()
    /// The Store's suggestions for a query, so a plugin answering (which
    /// rebuilds the root) doesn't scan every catalog again.
    @ObservationIgnored private var storeSuggestions: (query: String, catalogs: Int, installed: StoreListing.Installed, entries: [PaletteIndex.Entry])?
    /// The Store's indexes were asked for once, for its suggestions.
    @ObservationIgnored private var storeRequested = false

    /// The root's results in titled groups, as drawn, and what each row is.
    var root: PaletteRoot {
        _ = revision
        return load()
    }

    var sections: [PaletteSection] { root.sections }

    /// The same results in the order drawn, which the arrows walk.
    var results: [PaletteIndex.Entry] { root.entries }

    private func load() -> PaletteRoot {
        let palette = model.palette
        // Read every time, so the list redraws once the Store's indexes arrive.
        let storeCount = model.store?.catalogs.count ?? 0
        // Plugins' rows arrive after the query does, so they are read every
        // time and their stamp is part of the cache's key. It moves with each
        // answer, not with each row's id: a row's id stays put while its title
        // changes (a sum's answer is always the row `answer`), so keying on
        // ids kept the answer to the text before the last keystroke on screen.
        // Comparing the rows themselves cost a pass over every row, each read.
        let plugins = rootSearchRows()
        let rowsStamp = rootSearch.rowsStamp
        // What the palette learned is part of the key too: a reset, a pin or
        // Settings' Clear Search History reorders the root.
        let memory = model.commands.memory
        let key = PaletteRootCache.Key(query: query, index: palette.revision, memory: memory.revision, store: storeCount, rows: rowsStamp,
                                       scope: scope?.key)
        if let scope {
            return cache.root(for: key) { PaletteRoot.scoped(plugins.first { $0.command.key == scope.key }) }
        }
        return cache.root(for: key) {
            PaletteRoot.build(query: query, index: palette, ranker: memory.ranker(for: query),
                              usage: memory.usage, favorites: memory.favorites.ids,
                              remembered: memory.favorites.ids.compactMap { memory.rows.row($0)?.entry },
                              frequent: query.isEmpty ? memory.frequentApps() : [], store: storeEntries(), plugins: plugins,
                              fallbacks: fallbackCommands(), scoped: scopedRootSearch()?.entry.key) { memory.isRecent($0) }
        }
    }

    /// The Store's suggestions for the query, scanned again only when the
    /// query, the catalogs or what is installed change.
    private func storeEntries() -> [PaletteIndex.Entry] {
        guard let store = model.store else { return [] }
        let installed = store.installed
        if let known = storeSuggestions, known.query == query, known.catalogs == store.catalogs.count, known.installed == installed {
            return known.entries
        }
        let entries = StoreListing.paletteSuggestions(store.catalogs, query: query, installed: installed)
        storeSuggestions = (query, store.catalogs.count, installed, entries)
        return entries
    }

    /// A plugin's manifest, for its icon and colour.
    func manifest(of pluginID: String) -> Manifest? {
        model.controller(for: pluginID)?.manifest
    }

    /// A plugin's colour: its manifest's, or its Store listing's when it
    /// isn't installed (a Store suggestion).
    func accent(of pluginID: String) -> Accent? {
        if let manifest = manifest(of: pluginID) { return manifest.accent }
        return model.store?.find(pluginID)?.entry.accent.flatMap(Accent.init(rawValue:))
    }

    // MARK: - Plugins in the root

    /// The views of `.rootSearch()` commands, open while the user types at
    /// the root and fed the same text. Their top rows are a section each.
    @ObservationIgnored private let rootSearch: RootSearchSession<CommandViewModel>
    /// Bumped when a root view opens or closes, so the list reads it.
    private(set) var rootViewsRevision = 0

    /// Opens or updates the root views. Only running plugins are asked: the
    /// palette never starts one to search it.
    private func feedRootSearch() {
        let commands: CommandCenter = model.commands
        // An alias before the text (`gs stackbar`) asks only that command,
        // with the rest, even when it is out of the main search.
        let scoped = scopedRootSearch()
        // Inside a plugin's search an empty field still asks it, for what it
        // lists before anything is typed; after an alias it waits for text.
        let text = scoped.map { $0.text.isEmpty && scope == nil ? nil : $0.text } ?? RootSearchSession<CommandViewModel>.searchText(query, atRoot: stack.isEmpty)
        rootSearch.feed(text, commands: scoped.map { [$0.entry] } ?? commands.registry.entries,
                        accepts: { entry, text in
                            if let scoped { return entry.key == scoped.entry.key }
                            return RootSearchGate.accepts(entry, text: text, preference: commands.preferences[entry.key])
                        },
                        canOpen: { [model] in model.controller(for: $0.pluginID)?.supervisor != nil },
                        open: { [weak self] entry, text in
                            guard let self else { return nil }
                            let opened = await commands.openView(entry.key, query: CommandQuery(text: text), context: self.context, recordUse: false)
                            if case .success(let view) = opened { return view }
                            return nil
                        })
    }

    private func closeRootSearch() {
        rootSearch.closeAll()
    }

    /// What each root view shows now. Also times the views that answered.
    private func rootSearchRows() -> [PaletteRoot.PluginRows] {
        _ = rootViewsRevision
        return rootSearch.rows()
    }

    /// The root-search command an alias at the start of the text names
    /// (`gs stackbar`), and the rest of the text.
    private func scopedRootSearch() -> (entry: CommandRegistry.Entry, text: String)? {
        guard stack.isEmpty else { return nil }
        if let scope { return (scope, query.trimmingCharacters(in: .whitespaces)) }
        guard let match = model.palette.aliasMatch(query), let key = match.entry.commandKey,
              let entry = model.commands.registry.entry(key),
              RootSearchGate.searches(entry.spec, preference: model.commands.preferences[key]) else { return nil }
        return (entry, match.rest)
    }

    /// Every `.fallback()` command the user hasn't disabled.
    private func availableFallbacks() -> [CommandRegistry.Entry] {
        let preferences = model.commands.preferences
        return model.commands.registry.entries.filter { RootSearchGate.offersFallback($0.spec, preference: preferences[$0.key]) }
    }

    /// The fallbacks to offer for whatever was typed: the user's list.
    private func fallbackCommands() -> [CommandRegistry.Entry] {
        guard stack.isEmpty else { return [] }
        let preferences = model.commands.preferences
        return PaletteFallbacks.offered(availableFallbacks(), chosen: preferences.fallbacks) { preferences[$0] }
    }

    /// The plugin search Tab on the selected row would enter: the row is a
    /// plugin's root-search command or its Open row.
    var scopeTarget: CommandRegistry.Entry? {
        guard stack.isEmpty, scope == nil, let entry = selectedEntry else { return nil }
        let commands: CommandCenter = model.commands
        return PaletteScope.target(of: entry, commands: commands.registry.entries) { commands.preferences[$0] }
    }

    /// Tab at the root: searches inside the selected row's plugin when it
    /// has a search, otherwise hands the text to the fallback.
    func tab() -> Bool {
        if let target = scopeTarget {
            enterScope(target)
            return true
        }
        return tabToFallback()
    }

    /// Searches only inside `command`, from an empty field.
    func enterScope(_ command: CommandRegistry.Entry) {
        scope = command
        if query.isEmpty { feedRootSearch() } else { query = "" }
        selection.reset()
        problem = nil
    }

    /// Back to the main search, from an empty field.
    func leaveScope() {
        guard scope != nil else { return }
        scope = nil
        if query.isEmpty { feedRootSearch() } else { query = "" }
        selection.reset()
    }

    /// Tab at the root: hands the typed text to the chosen fallback (Ask AI
    /// by default), whether or not the root lists it now. False when there's
    /// nothing to hand or no one to take it, so Tab moves focus as usual.
    func tabToFallback() -> Bool {
        guard stack.isEmpty, scope == nil, !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let command = PaletteTabTarget.command(saved: UserDefaults.standard.string(forKey: PaletteTabTarget.defaultsKey), fallbacks: availableFallbacks()) else { return false }
        if let entry = PaletteTabTarget.entry(for: command, in: root), root.role(of: entry) == .fallback {
            activate(entry)
        } else {
            enter(command, input: query, source: .palette)
        }
        return true
    }

    /// The live view behind a plugin's row on the root, and the row.
    private func rootRow(_ entry: PaletteIndex.Entry) -> (view: CommandViewModel, row: PaletteRoot.PluginRow)? {
        guard let row = root.pluginRow(entry), let view = rootSearch.views[row.command] else { return nil }
        return (view, row)
    }

    // MARK: - Favourites

    func isFavorite(_ entry: PaletteIndex.Entry) -> Bool {
        model.commands.memory.isFavorite(entry)
    }

    /// ⌘⇧F: pins the selected root entry to the top, or unpins it.
    /// ⌘K's Add to Favorites (⌘⇧F) for the entry.
    private func favoriteAction(_ entry: PaletteIndex.Entry) -> Action {
        Action(title: isFavorite(entry) ? "Remove from Favorites" : "Add to Favorites", shortcut: "cmd+shift+f") { [weak self] in
            self?.toggleFavorite(entry)
        }
    }

    func toggleFavorite(_ entry: PaletteIndex.Entry) {
        model.commands.memory.toggleFavorite(entry, row: root.snapshot(entry))
        revision += 1
    }

    /// Bumped when something the cache can't see changes (a favourite), so
    /// the list redraws.
    private(set) var revision = 0

    // MARK: - ⌘1…⌘9

    /// ⌘ and a digit: runs that line of the list showing, counted from 1.
    func activate(line: Int) -> Bool {
        switch top {
        case .none:
            let results = results
            guard !collapsed, results.indices.contains(line - 1) else { return false }
            activate(results[line - 1])
            return true
        case .view(let view):
            let rows = rows(of: view)
            guard rows.indices.contains(line - 1), let primary = rows[line - 1].actions.first else { return false }
            perform(primary, in: view)
            return true
        case .arguments, .approval:
            return false
        }
    }

    /// The plugin the palette is about now: the open command's, or the
    /// selected entry's.
    var currentPluginID: String? {
        switch top {
        case .view(let view): return view.entry.pluginID
        case .arguments(let entry, _): return entry.pluginID
        case .approval(let entry, _, _): return entry.pluginID
        case .none: return selectedEntry?.pluginID
        }
    }

    /// A plugin is working: a view opening, or a view searching.
    var isLoading: Bool {
        if opening { return true }
        if case .view(let view) = top { return view.isSearching }
        return false
    }

    /// The root entry Return runs: the one the arrows chose, or the first.
    var selectedEntry: PaletteIndex.Entry? { selectedEntry(in: root) }

    /// `selectedEntry` in a root already read, for a view that reads it once.
    func selectedEntry(in root: PaletteRoot) -> PaletteIndex.Entry? {
        let results = root.entries
        return selection.index(in: results.map(\.id), query: query).map { results[$0] }
    }

    /// The row of a list view Return acts on, by the same rule.
    func selectedRow(of view: CommandViewModel) -> RowNode? {
        let rows = rows(of: view)
        return selection.index(in: rows.map(\.key), query: view.query).map { rows[$0] }
    }

    func activate(_ entry: PaletteIndex.Entry) {
        problem = nil
        // What was picked for this text, so it ranks higher for it next time,
        // and its use. A Store suggestion teaches nothing.
        let root = self.root
        if root.learns(entry) {
            model.commands.memory.chose(entry, query: stack.isEmpty ? query : nil)
        }
        // A plugin's row is kept, so it can show under Frequently Used.
        if let snapshot = root.snapshot(entry) {
            model.commands.memory.remember(snapshot)
        }
        if let found = rootRow(entry), let primary = found.row.actions.first {
            activateRootRow(found.view, key: found.row.rowKey, action: primary)
            return
        }
        switch entry.kind {
        case .action(let action, let value):
            // Held for a second press: stay open so Return again sends it.
            guard model.controller(for: entry.pluginID)?.press(action, value) != false else { return }
            finish()
        case .open(let url):
            guard let url = URL(string: url) else { return }
            // Stackbar's own links (a Store suggestion, Settings, a command)
            // open in this copy of the app; through Launch Services they
            // could reach another one (a dev build).
            finish()
            AppDelegate.shared?.route(url)
        case .showPanel:
            finish()
            AppDelegate.shared?.showPanel(pluginID: entry.pluginID)
        case .copy(let text):
            Platform.copy(text)
            HUD.shared.show("Copied \(text)")
            finish()
        case .navigate(let target):
            guard let command = model.commands.registry.entry(CommandKey(pluginID: entry.pluginID, commandID: target.command)) else {
                problem = "\(target.command) is not a command of \(entry.pluginName)"
                return
            }
            enter(command, arguments: target.arguments, source: .palette)
        case .command:
            guard let key = entry.commandKey, let command = model.commands.registry.entry(key) else { return }
            enter(command, input: root.input(for: entry, query: query, index: model.palette), source: .palette)
        case .remembered(let command, let rowKey, let text):
            replay(entry, command: CommandKey(pluginID: entry.pluginID, commandID: command), rowKey: rowKey, query: text)
        }
    }

    /// A pinned or frequent plugin row: asks its command for it again by
    /// its title, then does what Return on the live row does.
    private func replay(_ entry: PaletteIndex.Entry, command: CommandKey, rowKey: String, query text: String) {
        opening = true
        openToken += 1
        let token = openToken
        Task {
            let opened = await model.commands.openView(command, query: CommandQuery(text: text), context: context, recordUse: false)
            guard case .success(let view) = opened else {
                if token == openToken { opening = false }
                if case .failure(let outcome) = opened, token == openToken { problem = outcome.message }
                return
            }
            let action = await RootSearchSession<CommandViewModel>.replay(view, key: rowKey)
            guard token == openToken else {
                view.close()
                return
            }
            opening = false
            guard let action else {
                view.close()
                problem = "\(entry.pluginName) no longer has \(entry.title). Unpin it with ⌘⇧F."
                return
            }
            perform(action, in: view)
            view.close()
        }
    }

    /// Starts a command from inside the palette, by `CommandStart`'s plan.
    func enter(_ entry: CommandRegistry.Entry, arguments: [String: String] = [:], input: String = "", source: InvocationSource) {
        carryOut(model.commands.plan(entry, source: source, arguments: arguments, input: input), for: entry, source: source)
    }

    /// Runs the command, shows its argument fields, opens its view, or
    /// shows why it can't start.
    func carryOut(_ plan: CommandStart.Plan, for entry: CommandRegistry.Entry, source: InvocationSource) {
        problem = nil
        showingActions = false
        // A plugin that waits for approval is asked about here, in the
        // palette, instead of failing and sending the user to Settings.
        if plan.starts, model.controller(for: entry.pluginID)?.isWaitingForApproval == true {
            stack.append(.approval(entry, plan: plan, source: source))
            selection.reset()
            return
        }
        switch plan {
        case .refuse(let message):
            problem = message
        case .run(let arguments):
            run(entry, arguments, source: source)
        case .ask(let arguments):
            argumentValues = arguments
            stack.append(.arguments(entry, source: source))
        case .openView(let query):
            opening = true
            openToken += 1
            let token = openToken
            Task {
                let opened = await model.commands.openView(entry.key, query: query, context: context)
                // The palette was hidden, reset or went back while the
                // plugin started: this view belongs to nothing now.
                guard token == openToken else {
                    if case .success(let view) = opened { view.close() }
                    return
                }
                opening = false
                switch opened {
                case .success(let view):
                    view.onFinished = { [weak self] in self?.finish() }
                    stack.append(.view(view))
                    selection.reset()
                case .failure(let outcome):
                    problem = outcome.message
                }
            }
        }
    }

    /// What the plugin of the approval on top asks for, as Settings lists it.
    var pendingApproval: [Capability] {
        guard case .approval(let entry, _, _) = top else { return [] }
        return model.controller(for: entry.pluginID)?.pendingApproval ?? []
    }

    /// Return on an approval: allows what the plugin asks for, then starts
    /// the command as it would have.
    func approve() {
        guard case .approval(let entry, let plan, let source) = top, let controller = model.controller(for: entry.pluginID) else { return }
        let granted = controller.approve()
        Task {
            await granted?.value
            guard case .approval(let current, _, _) = top, current.key == entry.key else { return }
            stack.removeLast()
            if controller.isWaitingForApproval {
                problem = controller.problem ?? "\(entry.pluginName) is still waiting for approval"
                return
            }
            carryOut(plan, for: entry, source: source)
        }
    }

    /// Opens the plugin's page in Settings, for a closer look first.
    func reviewInSettings() {
        guard case .approval(let entry, _, _) = top else { return }
        let controller = model.controller(for: entry.pluginID)
        finish()
        AppDelegate.shared?.showSettings(plugin: controller)
    }

    /// Return in the argument fields.
    func submitArguments() {
        guard case .arguments(let entry, let source) = top else { return }
        if let missing = CommandStart.missing(entry.spec, argumentValues) {
            problem = "\(entry.spec.title) needs \(missing.placeholder)"
            return
        }
        run(entry, argumentValues, source: source)
    }

    /// Closes the palette first, so a paste goes to the app the user was in.
    private func run(_ entry: CommandRegistry.Entry, _ arguments: [String: String], source: InvocationSource) {
        let commands = model.commands
        let context = context
        finish()
        Task { await commands?.run(entry.key, arguments: arguments, source: source, context: context) }
    }

    // MARK: - A command view

    /// The columns of the open view's grid list, when it is one.
    var gridColumns: Int? {
        guard case .view(let view) = top else { return nil }
        return list(of: view).columns
    }

    /// Kept clipboard images, for a row preview's image.
    func imageData(for pluginID: String) -> (@Sendable (String) -> Data?)? {
        model.controller(for: pluginID).flatMap(AppModel.previewImages(for:))
    }

    /// A list view's tree after the filter, which the body, the arrows and
    /// Return all read: worked out once per answer and text, not on each read.
    struct ListState {
        var items: [RowFilter.Item]?
        var rows: [RowNode]
        var columns: Int?
        var hasPreviews: Bool
    }

    @ObservationIgnored private var listCache: (view: ObjectIdentifier, answers: Int, query: String, state: ListState)?

    func list(of view: CommandViewModel) -> ListState {
        let id = ObjectIdentifier(view)
        let answers = view.answers
        let query = view.query
        if let listCache, listCache.view == id, listCache.answers == answers, listCache.query == query { return listCache.state }
        let state: ListState
        if let root = view.root {
            let items = RowFilter.items(in: root, query: query)
            state = ListState(items: items,
                              rows: (items ?? []).compactMap { if case .row(let row) = $0 { return row } else { return nil } },
                              columns: RowFilter.columns(in: root), hasPreviews: RowFilter.hasPreviews(root))
        } else {
            state = ListState(items: nil, rows: [], columns: nil, hasPreviews: false)
        }
        listCache = (id, answers, query, state)
        return state
    }

    func rows(of view: CommandViewModel) -> [RowNode] { list(of: view).rows }

    /// Return on a plugin's row in the root. While its view is still
    /// answering newer text, the row on screen comes from the older answer:
    /// the session waits for the answer and runs the same row from it. If
    /// the row is gone, say so and keep the palette open.
    private func activateRootRow(_ view: CommandViewModel, key: String, action: ActionRef) {
        guard view.isSearching else {
            perform(action, in: view)
            return
        }
        let shown = shownCount
        Task { @MainActor [weak self] in
            guard let activation = await self?.rootSearch.activation(of: view, key: key, action: action),
                  let self, self.shownCount == shown else { return }
            switch activation {
            case .perform(let ref): self.perform(ref, in: view)
            case .gone: self.problem = "That result went away as you typed. Press Return again."
            }
        }
    }

    /// A row action in a list view: navigate within the plugin, or send it
    /// and close the palette, as the primary action of a launcher does.
    func perform(_ action: ActionRef, in view: CommandViewModel) {
        if let target = action.navigate {
            guard let command = model.commands.registry.entry(CommandKey(pluginID: view.entry.pluginID, commandID: target.command)) else {
                problem = "\(target.command) is not a command of \(view.entry.pluginName)"
                return
            }
            enter(command, arguments: target.arguments, source: .palette)
            return
        }
        // A plugin that is restarting or stopped can't act: say so and keep
        // the palette open, rather than close it with nothing done.
        guard view.canAct else {
            problem = view.problem ?? "\(view.entry.pluginName) isn't running"
            return
        }
        guard view.perform(action.id) else { return }
        finish()
    }

    /// Any other control in a view (a button, a field, a form): sent, and the
    /// palette stays, except after a form that comes back without errors.
    func send(_ action: ActionID, _ value: EventValue?, in view: CommandViewModel) {
        if let ref = view.root?.rows.flatMap(\.actions).first(where: { $0.id == action }) {
            perform(ref, in: view)
            return
        }
        view.perform(action, value)
    }

    // MARK: - ⌘K

    var actions: [Action] {
        switch top {
        case .none:
            guard let entry = selectedEntry else { return [] }
            let root = self.root
            // A plugin's row in the root: its own actions, as in its view.
            if let found = rootRow(entry) {
                let view = found.view
                var actions = found.row.actions.map { ref in
                    Action(title: ref.title, shortcut: ref.shortcut, role: ref.role) { [weak self] in self?.perform(ref, in: view) }
                }
                if root.canPin(entry) { actions.append(favoriteAction(entry)) }
                return actions + [resetRanking(entry)]
            }
            var actions = [Action(title: root.primaryTitle(entry)) { [weak self] in self?.activate(entry) }]
            if root.canPin(entry) { actions.append(favoriteAction(entry)) }
            if let key = entry.commandKey, let command = model.commands.registry.entry(key) {
                if command.spec.exposure == .everywhere {
                    actions.append(Action(title: "Copy Link", shortcut: "cmd+shift+c", section: "Command") { [weak self] in
                        Platform.copy(CommandLink(key: key).url)
                        HUD.shared.show("Copied the link")
                        self?.finish()
                    })
                }
                actions.append(Action(title: "Set Alias and Hotkey…", section: "Command") { [weak self] in
                    self?.finish()
                    AppDelegate.shared?.showCommandSettings(key)
                })
                actions.append(Action(title: "Disable Command", role: .critical, section: "Command") { [weak self] in
                    guard let self else { return }
                    var preference = model.commands.preferences[key]
                    preference.enabled = false
                    do {
                        try model.commands.set(preference, for: key)
                        showingActions = false
                    } catch {
                        // Say why it stays on, rather than closing the menu on a command that didn't change.
                        showingActions = false
                        problem = "Couldn't disable \(entry.title): \(error)"
                    }
                })
            }
            if root.learns(entry) { actions.append(resetRanking(entry)) }
            return actions
        case .arguments:
            return [Action(title: "Run") { [weak self] in self?.submitArguments() }]
        case .approval:
            return [Action(title: "Allow") { [weak self] in self?.approve() },
                    Action(title: "Review in Settings") { [weak self] in self?.reviewInSettings() }]
        case .view(let view):
            guard let row = selectedRow(of: view) else { return [] }
            return row.actions.map { ref in
                Action(title: ref.title, shortcut: ref.shortcut, role: ref.role) { [weak self] in self?.perform(ref, in: view) }
            }
        }
    }

    /// Forgets what the palette learned about one entry: its use and the
    /// text it was picked for, as Raycast's Reset Ranking does.
    private func resetRanking(_ entry: PaletteIndex.Entry) -> Action {
        Action(title: "Reset Ranking", section: "Ranking") { [weak self] in
            guard let self else { return }
            model.commands.memory.forget(entry)
            revision += 1
            showingActions = false
            HUD.shared.show("Ranking reset")
        }
    }

    /// ⌘K's list after its search field: the arrows and Return walk this.
    var filteredActions: [Action] {
        let typed = actionQuery.lowercased().filter { !$0.isWhitespace }
        guard !typed.isEmpty else { return actions }
        return actions
            .compactMap { action in TextMatch.score(typed, in: action.title.lowercased()).map { (action, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func runAction(_ index: Int) {
        let actions = filteredActions
        guard actions.indices.contains(index) else { return }
        showingActions = false
        actionQuery = ""
        actions[index].perform()
    }

    /// What Return does, for the footer.
    var primaryTitle: String? {
        switch top {
        case .none:
            return selectedEntry.map(root.primaryTitle)
        case .arguments:
            return "Run"
        case .approval:
            return "Allow"
        case .view(let view):
            return selectedRow(of: view)?.actions.first?.title
        }
    }

    /// What ⌘Return does: the second thing ⌘K offers.
    var secondaryTitle: String? {
        let actions = actions
        return actions.count > 1 ? actions[1].title : nil
    }

    /// ⌘Return.
    func submitSecondary() -> Bool {
        guard !showingActions, actions.count > 1 else { return false }
        runAction(1)
        return true
    }

    /// Return.
    func submit() {
        if showingActions {
            runAction(actionSelection)
            return
        }
        switch top {
        case .none:
            // Compact and nothing typed: no list shows, so nothing to run.
            guard !collapsed else { return }
            if let entry = selectedEntry { activate(entry) }
        case .arguments:
            submitArguments()
        case .approval:
            approve()
        case .view(let view):
            if let primary = selectedRow(of: view)?.actions.first { perform(primary, in: view) }
        }
    }

    func move(_ delta: Int) {
        if showingActions {
            actionSelection = min(max(actionSelection + delta, 0), max(filteredActions.count - 1, 0))
            return
        }
        switch top {
        case .none:
            guard !collapsed else { return }
            selection.move(delta, in: results.map(\.id), query: query)
        case .arguments, .approval: break
        case .view(let view): selection.move(delta, in: rows(of: view).map(\.key), query: view.query)
        }
    }

    func toggleActions() {
        guard showingActions || !actions.isEmpty else { return }
        showingActions.toggle()
        actionQuery = ""
        actionSelection = 0
    }

    /// A row action's own shortcut on the selected row of a list view.
    /// A shortcut pressed without ⌘K open: the selected row's action that
    /// has it, in a view, or the ⌘K action that has it, at the root
    /// (⌘⇧F Add to Favorites, ⌘⇧C Copy Link, a plugin row's own).
    func shortcut(matching matches: (String) -> Bool) -> Bool {
        switch top {
        case .view(let view):
            guard let action = selectedRow(of: view)?.actions.first(where: { $0.shortcut.map(matches) ?? false }) else { return false }
            perform(action, in: view)
            return true
        case .none:
            guard !collapsed, let index = actions.firstIndex(where: { $0.shortcut.map(matches) ?? false }) else { return false }
            showingActions = false
            actions[index].perform()
            return true
        case .arguments, .approval:
            return false
        }
    }
}
#endif
