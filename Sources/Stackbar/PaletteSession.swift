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

        var id: String {
            switch self {
            case .arguments(let entry, _): return "arguments|\(entry.key)"
            case .view(let view): return "view|\(view.id)"
            }
        }

        var title: String {
            switch self {
            case .arguments(let entry, _): return entry.spec.title
            case .view(let view): return view.entry.spec.title
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
    /// Nothing to come back to: no open command and nothing typed.
    var isIdle: Bool { stack.isEmpty && query.isEmpty }

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

    init(model: AppModel) {
        self.model = model
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
        query = ""
        closeRootSearch()
        selection.reset()
        cache = nil
        argumentValues = [:]
        showingActions = false
        actionQuery = ""
        problem = nil
        opening = false
        context = nil
    }

    /// Esc: hides ⌘K, then pops a stage. False at the root (close).
    func back() -> Bool {
        if showingActions {
            showingActions = false
            actionQuery = ""
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
    @ObservationIgnored private var cache: (query: String, revision: Int, store: Int, plugins: [String], sections: [PaletteSection], results: [PaletteIndex.Entry])?
    /// The Store's indexes were asked for once, for its suggestions.
    @ObservationIgnored private var storeRequested = false

    /// The root's results in titled groups, as drawn.
    var sections: [PaletteSection] {
        _ = revision
        return load().sections
    }

    /// The same results in the order drawn, which the arrows walk.
    var results: [PaletteIndex.Entry] {
        load().results
    }

    private func load() -> (sections: [PaletteSection], results: [PaletteIndex.Entry]) {
        let palette = model.palette
        // Read every time, so the list redraws once the Store's indexes arrive.
        let storeCount = model.store?.catalogs.count ?? 0
        // Plugins' rows arrive after the query does, so they are read every
        // time and are part of the cache's key.
        let plugins = rootSearchSections()
        let pluginKey = plugins.flatMap(\.entries).map(\.id)
        if let cache, cache.query == query, cache.revision == palette.revision, cache.store == storeCount, cache.plugins == pluginKey {
            return (cache.sections, cache.results)
        }
        let usage = model.commands.usage
        var found = palette.search(query, limit: 30, usage: usage)
        if let match = palette.aliasMatch(query) {
            found.removeAll { $0.id == match.entry.id }
            found.insert(match.entry, at: 0)
        }
        let favorites = model.commands.favorites.entries(in: palette.all)
        let store = model.store.map { StoreListing.paletteSuggestions($0.catalogs, query: query, installed: $0.installed) } ?? []
        let sections = PaletteSection.group(found, query: query, favorites: favorites, store: store,
                                            plugins: plugins, fallbacks: fallbackEntries()) { usage.score($0.id) > 0 }
        let ordered = sections.flatMap(\.entries)
        cache = (query, palette.revision, storeCount, pluginKey, sections, ordered)
        return (sections, ordered)
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

    /// Views of `.rootSearch()` commands, open while the user types at the
    /// root and fed the same text. Their top rows are a section each.
    @ObservationIgnored private var rootViews: [CommandKey: CommandViewModel] = [:]
    @ObservationIgnored private var rootOpening: Set<CommandKey> = []
    /// When each root view was last given new text and hasn't answered yet,
    /// for the time budget.
    @ObservationIgnored private var rootFedAt: [CommandKey: Date] = [:]
    /// What a root row does when chosen: its view and its primary action.
    @ObservationIgnored private var rootRows: [String: (view: CommandViewModel, action: ActionRef, actions: [ActionRef])] = [:]
    /// Bumped when a root view opens, so the list reads it.
    private(set) var rootViewsRevision = 0
    /// Rows from each plugin, at most.
    static let rootRowLimit = 3

    private var rootText: String? {
        let text = query.trimmingCharacters(in: .whitespaces)
        return stack.isEmpty && text.count >= 2 ? text : nil
    }

    /// Opens or updates the root views. Only running plugins are asked: the
    /// palette never starts one to search it.
    private func feedRootSearch() {
        guard let text = rootText else {
            closeRootSearch()
            return
        }
        let commands: CommandCenter = model.commands
        let wanted = commands.registry.entries.filter {
            RootSearchGate.accepts($0.spec, text: text, preference: commands.preferences[$0.key]) && !commands.rootBudget.isBenched($0.key)
        }
        let keys = Set(wanted.map(\.key))
        // A view whose pattern no longer matches (or that was benched) closes,
        // so its rows for older text don't linger.
        for (key, view) in rootViews where !keys.contains(key) {
            view.close()
            rootViews[key] = nil
            rootFedAt[key] = nil
            rootViewsRevision += 1
        }
        for entry in wanted {
            if let view = rootViews[entry.key] {
                if view.query != text { rootFedAt[entry.key] = Date() }
                view.query = text
                continue
            }
            guard !rootOpening.contains(entry.key), model.controller(for: entry.pluginID)?.supervisor != nil else { continue }
            rootOpening.insert(entry.key)
            let key = entry.key
            rootFedAt[key] = Date()
            Task {
                let opened = await model.commands.openView(key, query: CommandQuery(text: text), context: context, recordUse: false)
                rootOpening.remove(key)
                guard case .success(let view) = opened else { return }
                guard let now = rootText, rootViews[key] == nil else {
                    view.close()
                    return
                }
                view.query = now
                rootViews[key] = view
                rootViewsRevision += 1
            }
        }
    }

    private func closeRootSearch() {
        for view in rootViews.values { view.close() }
        rootViews = [:]
        rootRows = [:]
        rootFedAt = [:]
        if rootViewsRevision != 0 { rootViewsRevision += 1 }
    }

    /// One section per root view with rows, in command-title order.
    private func rootSearchSections() -> [PaletteSection] {
        _ = rootViewsRevision
        guard rootText != nil else { return [] }
        var table: [String: (view: CommandViewModel, action: ActionRef, actions: [ActionRef])] = [:]
        for (key, view) in rootViews where !view.isSearching {
            if let fed = rootFedAt.removeValue(forKey: key) {
                model.commands.rootBudget.record(key, took: Date().timeIntervalSince(fed))
            }
        }
        let sections = rootViews.values.sorted { $0.entry.spec.title < $1.entry.spec.title }.compactMap { view -> PaletteSection? in
            let entries = self.rows(of: view).prefix(Self.rootRowLimit).compactMap { row -> PaletteIndex.Entry? in
                guard let primary = row.actions.first else { return nil }
                let kind: PaletteIndex.Entry.Kind = primary.navigate.map { .navigate($0) } ?? .action(primary.id, value: nil)
                var entry = PaletteIndex.Entry(pluginID: view.entry.pluginID, pluginName: view.entry.pluginName, title: row.title,
                                               subtitle: row.subtitle, symbol: row.symbol ?? view.entry.spec.symbol, kind: kind)
                entry.appIcon = row.appIcon
                entry.fileIcon = row.fileIcon
                table[entry.id] = (view, primary, row.actions)
                return entry
            }
            return entries.isEmpty ? nil : PaletteSection(title: view.entry.spec.rootSection ?? view.entry.spec.title, entries: entries,
                                                          leads: view.entry.spec.rootPattern != nil)
        }
        rootRows = table
        return sections
    }

    /// `.fallback()` commands, offered for whatever was typed.
    private func fallbackEntries() -> [PaletteIndex.Entry] {
        guard stack.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let preferences = model.commands.preferences
        return model.commands.registry.entries.filter { RootSearchGate.offersFallback($0.spec, preference: preferences[$0.key]) }.map { entry in
            PaletteIndex.Entry(pluginID: entry.pluginID, pluginName: entry.pluginName, title: entry.spec.title,
                               subtitle: entry.pluginName, symbol: entry.spec.symbol, kind: .command(entry.spec))
        }
    }

    /// Chosen from the fallback section, so the whole query is its input.
    func isFallback(_ entry: PaletteIndex.Entry) -> Bool {
        let title = PaletteSection.fallbackTitle(query.trimmingCharacters(in: .whitespaces))
        return sections.first { $0.title == title }?.entries.contains { $0.id == entry.id } ?? false
    }

    // MARK: - Favourites

    func isFavorite(_ entry: PaletteIndex.Entry) -> Bool {
        model.commands.favorites.contains(entry.id)
    }

    /// ⌘⇧F: pins the selected root entry to the top, or unpins it.
    func toggleFavorite(_ entry: PaletteIndex.Entry) {
        model.commands.favorites.toggle(entry.id)
        cache = nil
        revision += 1
    }

    /// Bumped when something the cache can't see changes (a favourite), so
    /// the list redraws.
    private(set) var revision = 0

    func toggleFavoriteOfSelection() -> Bool {
        guard top == nil, let entry = selectedEntry, canPin(entry) else { return false }
        toggleFavorite(entry)
        return true
    }

    /// Store suggestions and calculator answers come and go with the query,
    /// so they can't be pinned.
    func canPin(_ entry: PaletteIndex.Entry) -> Bool {
        if case .copy = entry.kind { return false }
        if rootRows[entry.id] != nil || isFallback(entry) { return false }
        return !isStoreSuggestion(entry)
    }

    func isStoreSuggestion(_ entry: PaletteIndex.Entry) -> Bool {
        if case .open(let url) = entry.kind { return url.hasPrefix("stackbar://store/") }
        return false
    }

    // MARK: - ⌘1…⌘9

    /// ⌘ and a digit: runs that line of the list showing, counted from 1.
    func activate(line: Int) -> Bool {
        switch top {
        case .none:
            let results = results
            guard results.indices.contains(line - 1) else { return false }
            activate(results[line - 1])
            return true
        case .view(let view):
            let rows = rows(of: view)
            guard rows.indices.contains(line - 1), let primary = rows[line - 1].actions.first else { return false }
            perform(primary, in: view)
            return true
        case .arguments:
            return false
        }
    }

    /// The plugin the palette is about now: the open command's, or the
    /// selected entry's.
    var currentPluginID: String? {
        switch top {
        case .view(let view): return view.entry.pluginID
        case .arguments(let entry, _): return entry.pluginID
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
    var selectedEntry: PaletteIndex.Entry? {
        let results = results
        return selection.index(in: results.map(\.id), query: query).map { results[$0] }
    }

    /// The row of a list view Return acts on, by the same rule.
    func selectedRow(of view: CommandViewModel) -> RowNode? {
        let rows = rows(of: view)
        return selection.index(in: rows.map(\.key), query: view.query).map { rows[$0] }
    }

    func activate(_ entry: PaletteIndex.Entry) {
        problem = nil
        if let row = rootRows[entry.id] {
            perform(row.action, in: row.view)
            return
        }
        switch entry.kind {
        case .action(let action, let value):
            model.commands.usage.record(entry.id)
            model.controller(for: entry.pluginID)?.send(action, value)
            finish()
        case .open(let url):
            guard let url = URL(string: url) else { return }
            // A Store suggestion goes to this app's own Store window: through
            // Launch Services it could open another Stackbar copy (a dev
            // build). Not counted as a use: it isn't a palette entry.
            if let link = StoreLink(url) {
                finish()
                model.storeFocus = link.pluginID
                AppDelegate.shared?.showStore()
                return
            }
            // Stackbar's own places (Settings, the Store) open here too.
            if let link = AppLink(url) {
                model.commands.usage.record(entry.id)
                finish()
                AppDelegate.shared?.open(link)
                return
            }
            model.commands.usage.record(entry.id)
            NSWorkspace.shared.open(url)
            finish()
        case .showPanel:
            model.commands.usage.record(entry.id)
            finish()
            AppDelegate.shared?.showPanel(pluginID: entry.pluginID)
        case .copy(let text):
            Platform.copy(text)
            HUD.shared.show("Copied \(text)")
            finish()
        case .navigate(let target):
            model.commands.usage.record(entry.id)
            guard let command = model.commands.registry.entry(CommandKey(pluginID: entry.pluginID, commandID: target.command)) else {
                problem = "\(target.command) is not a command of \(entry.pluginName)"
                return
            }
            enter(command, arguments: target.arguments, source: .palette)
        case .command:
            guard let key = entry.commandKey, let command = model.commands.registry.entry(key) else { return }
            // `gh react`: the rest of the line fills the first argument, or a
            // view's search.
            // A fallback: all of it.
            let rest = isFallback(entry)
                ? query.trimmingCharacters(in: .whitespaces)
                : model.palette.aliasMatch(query).flatMap { $0.entry.id == entry.id ? $0.rest : nil } ?? ""
            var arguments: [String: String] = [:]
            var text = ""
            if !rest.isEmpty {
                if command.spec.kind == .view {
                    text = rest
                } else if let first = command.spec.arguments.first {
                    arguments[first.name] = rest
                }
            }
            enter(command, arguments: arguments, query: text, source: .palette)
        }
    }

    /// Starts a command: runs it when it has what it needs, asks for its
    /// arguments when not, or opens its view.
    func enter(_ entry: CommandRegistry.Entry, arguments: [String: String] = [:], query text: String = "", source: InvocationSource) {
        problem = nil
        showingActions = false
        switch entry.spec.kind {
        case .run:
            var values = arguments
            for argument in entry.spec.arguments where (values[argument.name] ?? "").isEmpty {
                values[argument.name] = argument.defaultValue ?? argument.options?.first ?? ""
            }
            let ready = entry.spec.requiredArguments.allSatisfy { !(values[$0.name] ?? "").isEmpty }
            if entry.spec.arguments.isEmpty || (!arguments.isEmpty && ready) {
                run(entry, values, source: source)
            } else {
                argumentValues = values
                stack.append(.arguments(entry, source: source))
            }
        case .view:
            opening = true
            Task {
                let opened = await model.commands.openView(entry.key, query: CommandQuery(text: text, arguments: arguments), context: context)
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

    /// Return in the argument fields.
    func submitArguments() {
        guard case .arguments(let entry, let source) = top else { return }
        if let missing = entry.spec.requiredArguments.first(where: { (argumentValues[$0.name] ?? "").isEmpty }) {
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
        guard case .view(let view) = top, let root = view.root else { return nil }
        return RowFilter.columns(in: root)
    }

    /// Kept clipboard images, for a row preview's image.
    func imageData(for pluginID: String) -> (@Sendable (String) -> Data?)? {
        model.controller(for: pluginID).flatMap(AppModel.previewImages(for:))
    }

    func rows(of view: CommandViewModel) -> [RowNode] {
        guard let root = view.root, let items = RowFilter.items(in: root, query: view.query) else { return [] }
        return items.compactMap { if case .row(let row) = $0 { return row } else { return nil } }
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
        view.perform(action.id)
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
            // A plugin's row in the root: its own actions, as in its view.
            if let row = rootRows[entry.id] {
                return row.actions.map { ref in
                    Action(title: ref.title, shortcut: ref.shortcut, role: ref.role) { [weak self] in self?.perform(ref, in: row.view) }
                }
            }
            var actions = [Action(title: primaryTitle ?? "Run") { [weak self] in self?.activate(entry) }]
            if canPin(entry) {
                let pinned = isFavorite(entry)
                actions.append(Action(title: pinned ? "Remove from Favorites" : "Add to Favorites", shortcut: "cmd+shift+f") { [weak self] in
                    self?.toggleFavorite(entry)
                })
            }
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
                    try? model.commands.set(preference, for: key)
                    showingActions = false
                })
            }
            return actions
        case .arguments:
            return [Action(title: "Run") { [weak self] in self?.submitArguments() }]
        case .view(let view):
            guard let row = selectedRow(of: view) else { return [] }
            return row.actions.map { ref in
                Action(title: ref.title, shortcut: ref.shortcut, role: ref.role) { [weak self] in self?.perform(ref, in: view) }
            }
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
            guard let entry = selectedEntry else { return nil }
            if let row = rootRows[entry.id] { return row.action.title }
            switch entry.kind {
            case .command(let spec): return spec.kind == .view || !spec.arguments.isEmpty ? "Open" : "Run"
            case .navigate, .showPanel: return "Open"
            case .open: return isStoreSuggestion(entry) ? "Show in Store" : "Open"
            case .action: return "Run"
            case .copy: return "Copy Answer"
            }
        case .arguments:
            return "Run"
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
            if let entry = selectedEntry { activate(entry) }
        case .arguments:
            submitArguments()
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
        case .none: selection.move(delta, in: results.map(\.id), query: query)
        case .arguments: break
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
    func shortcut(matching matches: (String) -> Bool) -> Bool {
        guard case .view(let view) = top else { return false }
        guard let action = selectedRow(of: view)?.actions.first(where: { $0.shortcut.map(matches) ?? false }) else { return false }
        perform(action, in: view)
        return true
    }
}
#endif
