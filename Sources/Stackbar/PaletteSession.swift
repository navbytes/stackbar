#if os(macOS)
import AppKit
import Observation
import StackbarHostCore
import StackbarProtocol
import StackbarUI

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
        var perform: @MainActor () -> Void
        var id: String { title }
    }

    let model: AppModel
    var query = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    /// The selected root entry, or the selected row of a list view.
    var selection = 0
    private(set) var stack: [Stage] = []
    /// The argument fields' values while a run command waits for them.
    var argumentValues: [String: String] = [:]
    var showingActions = false
    var actionSelection = 0
    /// Why the last thing didn't work, shown under the search field.
    private(set) var problem: String?
    /// A view command is waiting for its plugin.
    private(set) var opening = false
    /// Changes each time the palette opens, to take focus again.
    private(set) var shownCount = 0
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
        selection = 0
        argumentValues = [:]
        showingActions = false
        problem = nil
        opening = false
    }

    /// Esc: hides ⌘K, then pops a stage. False at the root (close).
    func back() -> Bool {
        if showingActions {
            showingActions = false
            return true
        }
        guard let last = stack.popLast() else { return false }
        if case .view(let view) = last { view.close() }
        selection = 0
        problem = nil
        argumentValues = [:]
        return true
    }

    private func finish() {
        dismiss()
    }

    // MARK: - The root

    var results: [PaletteIndex.Entry] {
        var found = model.palette.search(query, limit: 30, usage: model.commands.usage)
        if let match = model.palette.aliasMatch(query) {
            found.removeAll { $0.id == match.entry.id }
            found.insert(match.entry, at: 0)
        }
        return found
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
                let opened = await model.commands.openView(entry.key, query: CommandQuery(text: text, arguments: arguments))
                opening = false
                switch opened {
                case .success(let view):
                    view.onFinished = { [weak self] in self?.finish() }
                    stack.append(.view(view))
                    selection = 0
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
        finish()
        Task { await commands?.run(entry.key, arguments: arguments, source: source) }
    }

    // MARK: - A command view

    /// The rows of a list view after the host's filter, for keyboard
    /// selection; nil when the view isn't a list of rows.
    static func items(_ root: ViewNode, query: String) -> [ListItem]? {
        guard case .list(let searchable, let children) = root else { return nil }
        let shown = searchable ? RowFilter.filter(children, query: query) : children
        var items: [ListItem] = []
        for child in shown {
            switch child {
            case .row(let row):
                items.append(.row(row))
            case .section(let title, let inner):
                if let title { items.append(.header(title)) }
                for node in inner {
                    guard case .row(let row) = node else { return nil }
                    items.append(.row(row))
                }
            default:
                return nil
            }
        }
        return items
    }

    enum ListItem: Identifiable {
        case header(String)
        case row(RowNode)

        var id: String {
            switch self {
            case .header(let title): return "header|\(title)"
            case .row(let row): return row.key
            }
        }
    }

    func rows(of view: CommandViewModel) -> [RowNode] {
        guard let root = view.root, let items = Self.items(root, query: view.query) else { return [] }
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
            let results = results
            guard results.indices.contains(selection) else { return [] }
            let entry = results[selection]
            var actions = [Action(title: entry.commandKey == nil ? "Run" : "Open") { [weak self] in self?.activate(entry) }]
            if let key = entry.commandKey, let command = model.commands.registry.entry(key) {
                if command.spec.exposure == .everywhere {
                    actions.append(Action(title: "Copy Link", shortcut: "cmd+shift+c") { [weak self] in
                        Platform.copy(CommandLink(key: key).url)
                        HUD.shared.show("Copied the link")
                        self?.finish()
                    })
                }
                actions.append(Action(title: "Set Alias and Hotkey…") { [weak self] in
                    self?.finish()
                    AppDelegate.shared?.showCommandSettings(key)
                })
                actions.append(Action(title: "Disable Command", role: .critical) { [weak self] in
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
            let rows = rows(of: view)
            guard rows.indices.contains(selection) else { return [] }
            return rows[selection].actions.map { ref in
                Action(title: ref.title, shortcut: ref.shortcut, role: ref.role) { [weak self] in self?.perform(ref, in: view) }
            }
        }
    }

    func runAction(_ index: Int) {
        let actions = actions
        guard actions.indices.contains(index) else { return }
        showingActions = false
        actions[index].perform()
    }

    /// What Return does, for the footer.
    var primaryTitle: String? {
        switch top {
        case .none:
            let results = results
            guard results.indices.contains(selection) else { return nil }
            switch results[selection].kind {
            case .command(let spec): return spec.kind == .view || !spec.arguments.isEmpty ? "Open" : "Run"
            case .navigate, .showPanel: return "Open"
            case .action, .open: return "Run"
            }
        case .arguments:
            return "Run"
        case .view(let view):
            let rows = rows(of: view)
            return rows.indices.contains(selection) ? rows[selection].actions.first?.title : nil
        }
    }

    /// Return.
    func submit() {
        if showingActions {
            runAction(actionSelection)
            return
        }
        switch top {
        case .none:
            let results = results
            if results.indices.contains(selection) { activate(results[selection]) }
        case .arguments:
            submitArguments()
        case .view(let view):
            let rows = rows(of: view)
            if rows.indices.contains(selection), let primary = rows[selection].actions.first { perform(primary, in: view) }
        }
    }

    func move(_ delta: Int) {
        if showingActions {
            actionSelection = min(max(actionSelection + delta, 0), max(actions.count - 1, 0))
            return
        }
        let count: Int
        switch top {
        case .none: count = results.count
        case .arguments: count = 0
        case .view(let view): count = rows(of: view).count
        }
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func toggleActions() {
        guard showingActions || !actions.isEmpty else { return }
        showingActions.toggle()
        actionSelection = 0
    }

    /// A row action's own shortcut on the selected row of a list view.
    func shortcut(matching matches: (String) -> Bool) -> Bool {
        guard case .view(let view) = top else { return false }
        let rows = rows(of: view)
        guard rows.indices.contains(selection), let action = rows[selection].actions.first(where: { $0.shortcut.map(matches) ?? false }) else { return false }
        perform(action, in: view)
        return true
    }
}
#endif
