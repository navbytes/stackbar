import Foundation
import StackbarProtocol

/// The command palette's entries: everything a user can do across every
/// plugin, found by typing.
///
/// Entries come from what plugins already render on their panels (rows'
/// actions, buttons, toggles, links), so a plugin gets palette support without
/// writing anything for it. `SurfaceParity`'s palette column says the same.
public struct PaletteIndex: Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable {
            case action(ActionID, value: EventValue?)
            case open(String)
            /// A row action that opens one of the plugin's commands.
            case navigate(CommandTarget)
            /// One of the plugin's declared commands.
            case command(CommandSpec)
            /// Opens the panel of a plugin that has no menu-bar item.
            case showPanel
        }

        public var pluginID: String
        public var pluginName: String
        public var title: String
        public var subtitle: String?
        public var symbol: String?
        public var kind: Kind
        /// More words it is found by (a command's keywords).
        public var keywords: [String] = []
        /// The alias the user gave the command, shown on its row.
        public var alias: String?

        public var commandKey: CommandKey? {
            if case .command(let spec) = kind { return CommandKey(pluginID: pluginID, commandID: spec.id) }
            return nil
        }

        public var id: String {
            switch kind {
            case .action(let action, _): return "\(pluginID)|\(action.rawValue)"
            case .open(let url): return "\(pluginID)|open|\(url)"
            case .navigate(let target): return "\(pluginID)|navigate|\(target.command)|\(target.arguments.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))"
            case .command(let spec): return "\(pluginID)/\(spec.id)"
            case .showPanel: return "\(pluginID)|panel"
            }
        }
    }

    /// Entries derived from panels (rows, buttons, toggles, links).
    public private(set) var entries: [Entry] = []
    /// Declared commands, listed before panel entries.
    public private(set) var commands: [Entry] = []
    /// "Open <Plugin>" for plugins without a menu-bar item.
    public private(set) var panels: [Entry] = []

    public init() {}

    /// Replaces one plugin's entries with those found in its panel tree.
    public mutating func update(pluginID: String, pluginName: String, panel: ViewNode?) {
        entries.removeAll { $0.pluginID == pluginID }
        guard let panel else { return }
        entries += Self.entries(in: panel, pluginID: pluginID, pluginName: pluginName)
    }

    public mutating func remove(pluginID: String) {
        entries.removeAll { $0.pluginID == pluginID }
        commands.removeAll { $0.pluginID == pluginID }
        panels.removeAll { $0.pluginID == pluginID }
    }

    /// The plugins whose panel opens from the palette, not the menu bar.
    public mutating func setHeadlessPanels(_ plugins: [(pluginID: String, name: String)]) {
        panels = plugins.map { Entry(pluginID: $0.pluginID, pluginName: $0.name, title: "Open \($0.name)", symbol: "macwindow", kind: .showPanel) }
    }

    /// Replaces the command entries with the registry's enabled commands.
    public mutating func setCommands(_ registry: [CommandRegistry.Entry], preferences: [CommandKey: CommandPreference]) {
        commands = registry.compactMap { item in
            let preference = preferences[item.key] ?? .default
            guard preference.enabled else { return nil }
            var entry = Entry(pluginID: item.pluginID, pluginName: item.pluginName, title: item.spec.title, subtitle: item.spec.subtitle, symbol: item.spec.symbol, kind: .command(item.spec))
            entry.keywords = item.spec.keywords
            entry.alias = preference.alias
            return entry
        }
    }

    /// Commands first, then panels to open, then panel entries.
    public var all: [Entry] { commands + panels + entries }

    /// Entries matching `query`, best first: an exact alias, then the fuzzy
    /// match plus a bonus for what was used often and lately. An empty query
    /// lists the most used first, then everything in plugin order.
    public func search(_ query: String, limit: Int = 50, usage: PaletteUsage? = nil) -> [Entry] {
        let typed = query.lowercased().trimmingCharacters(in: .whitespaces)
        let squeezed = typed.filter { !$0.isWhitespace }
        let all = all
        func bonus(_ entry: Entry) -> Int {
            guard let usage else { return 0 }
            let score = usage.score(entry.id)
            return score > 0 ? min(300, Int(60 * log2(1 + score))) : 0
        }
        guard !squeezed.isEmpty else {
            guard usage != nil else { return Array(all.prefix(limit)) }
            return Array(all.enumerated()
                .sorted { (bonus($0.element), -$0.offset) > (bonus($1.element), -$1.offset) }
                .map(\.element)
                .prefix(limit))
        }
        return all
            .compactMap { entry -> (Entry, Int)? in
                if let alias = entry.alias, alias == typed { return (entry, 100_000) }
                let haystacks = [entry.title, entry.subtitle ?? "", entry.keywords.joined(separator: " "), entry.pluginName]
                let best = haystacks.enumerated().compactMap { index, text in
                    Self.score(squeezed, in: text.lowercased()).map { $0 - index * 5 }
                }.max()
                guard let best else { return nil }
                let commandBonus = entry.commandKey == nil ? 0 : 40
                return (entry, best + bonus(entry) + commandBonus)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// `gh react` → the command aliased `gh` and the rest of the line, which
    /// fills its first argument (or its view's query).
    public func aliasMatch(_ query: String) -> (entry: Entry, rest: String)? {
        guard let space = query.firstIndex(of: " ") else { return nil }
        let alias = query[..<space].lowercased()
        guard !alias.isEmpty, let entry = commands.first(where: { $0.alias == alias }) else { return nil }
        return (entry, String(query[query.index(after: space)...]).trimmingCharacters(in: .whitespaces))
    }

    static func entries(in node: ViewNode, pluginID: String, pluginName: String) -> [Entry] {
        func entry(_ title: String, _ subtitle: String?, _ symbol: String?, _ kind: Entry.Kind) -> Entry {
            Entry(pluginID: pluginID, pluginName: pluginName, title: title, subtitle: subtitle, symbol: symbol, kind: kind)
        }
        switch node {
        case .row(let row):
            return row.actions.enumerated().map { index, action in
                let title = index == 0 ? row.title : "\(action.title): \(row.title)"
                return entry(title, row.subtitle ?? (index == 0 ? action.title : nil), row.symbol, action.navigate.map(Entry.Kind.navigate) ?? .action(action.id, value: nil))
            }
        case .button(let title, let symbol, _, let action):
            return [entry(title, nil, symbol, .action(action, value: nil))]
        case .toggle(let title, let isOn, let action):
            return [entry("\(isOn ? "Turn off" : "Turn on") \(title)", nil, isOn ? "switch.2" : "switch.2", .action(action, value: .bool(!isOn)))]
        case .link(let title, let url):
            return [entry(title, url, "link", .open(url))]
        case .tappable(let content, let action):
            let title = content.plainText
            return title.isEmpty ? [] : [entry(title, nil, nil, .action(action, value: nil))]
        case .stack, .list, .section, .styled:
            return node.children.flatMap { entries(in: $0, pluginID: pluginID, pluginName: pluginName) }
        case .text, .label, .badge, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .empty, .form, .shape, .image, .timer, .spacer:
            return []
        }
    }

    /// Subsequence match with bonuses for word starts and runs; `nil` when
    /// the letters don't appear in order.
    static func score(_ query: String, in text: String) -> Int? {
        TextMatch.score(query, in: text)
    }
}
