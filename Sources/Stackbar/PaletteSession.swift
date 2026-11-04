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
        didSet { if query != oldValue { selection.reset() } }
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
    @ObservationIgnored var dismiss: () -> Void = {}

    init(model: AppModel) {
        self.model = model
    }

    var top: Stage? { stack.last }

    func shown() {
        shownCount += 1
    }

    /// Back to an empty root, closing every open view.
    func reset() {
        for stage in stack.reversed() {
            if case .view(let view) = stage { view.close() }
        }
        stack = []
        query = ""
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
    @ObservationIgnored private var cache: (query: String, revision: Int, sections: [PaletteSection], results: [PaletteIndex.Entry])?

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
        if let cache, cache.query == query, cache.revision == palette.revision { return (cache.sections, cache.results) }
        let usage = model.commands.usage
        var found = palette.search(query, limit: 30, usage: usage)
        if let match = palette.aliasMatch(query) {
            found.removeAll { $0.id == match.entry.id }
            found.insert(match.entry, at: 0)
        }
        let favorites = model.commands.favorites.entries(in: palette.all)
        let store = model.store.map { StoreListing.paletteSuggestions($0.catalogs, query: query, installed: $0.installed) } ?? []
        let sections = PaletteSection.group(found, query: query, favorites: favorites, store: store) { usage.score($0.id) > 0 }
        let ordered = sections.flatMap(\.entries)
        cache = (query, palette.revision, sections, ordered)
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
        guard top == nil, let entry = selectedEntry, !isStoreSuggestion(entry) else { return false }
        toggleFavorite(entry)
        return true
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
        switch entry.kind {
        case .action(let action, let value):
            model.commands.usage.record(entry.id)
            model.controller(for: entry.pluginID)?.send(action, value)
            finish()
        case .open(let url):
            model.commands.usage.record(entry.id)
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
            finish()
        case .showPanel:
            model.commands.usage.record(entry.id)
            finish()
            AppDelegate.shared?.showPanel(pluginID: entry.pluginID)
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
            let rest = model.palette.aliasMatch(query).flatMap { $0.entry.id == entry.id ? $0.rest : nil } ?? ""
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
            var actions = [Action(title: entry.commandKey == nil ? "Run" : "Open") { [weak self] in self?.activate(entry) }]
            if !isStoreSuggestion(entry) {
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
            switch entry.kind {
            case .command(let spec): return spec.kind == .view || !spec.arguments.isEmpty ? "Open" : "Run"
            case .navigate, .showPanel: return "Open"
            case .action, .open: return "Run"
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
