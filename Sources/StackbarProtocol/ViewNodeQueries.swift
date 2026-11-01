import Foundation

/// Pure questions about a view tree that surfaces ask. They live here, not in
/// the SwiftUI or app code that asks them, so Linux tests cover them.
extension ViewNode {
    /// This node with `transform` applied to each of its `children`: the one
    /// place that rebuilds a container, so a rewrite of the tree only says
    /// what it changes.
    public func mapChildren(_ transform: (ViewNode) -> ViewNode) -> ViewNode {
        switch self {
        case .stack(let axis, let spacing, let alignment, let children):
            return .stack(axis: axis, spacing: spacing, alignment: alignment, children: children.map(transform))
        case .list(let searchable, let children):
            return .list(searchable: searchable, children: children.map(transform))
        case .section(let title, let children):
            return .section(title: title, children: children.map(transform))
        case .styled(let child, let style):
            return .styled(transform(child), style: style)
        case .tappable(let child, let action):
            return .tappable(transform(child), action: action)
        case .text, .label, .row, .badge, .button, .toggle, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .link, .empty, .form, .shape, .image, .timer, .spacer:
            return self
        }
    }

    /// The tree as a widget draws it: lists keep their first `maxRows`
    /// children and lose their search field. Controls stay; the widget
    /// draws them disabled.
    public func trimmed(maxRows: Int) -> ViewNode {
        if case .list(_, let children) = self {
            return .list(searchable: false, children: children.prefix(maxRows).map { $0.trimmed(maxRows: maxRows) })
        }
        return mapChildren { $0.trimmed(maxRows: maxRows) }
    }

    /// True when nothing in the tree has a menu-bar form, so the status item
    /// shows the plugin's name instead. Controls and lists live in the panel.
    public var isBlankInMenuBar: Bool {
        switch self {
        case .text, .label, .badge, .progress, .labeled, .chart, .empty, .image, .timer:
            return false
        case .stack, .styled:
            return children.allSatisfy(\.isBlankInMenuBar)
        case .list, .section, .row, .button, .toggle, .divider, .textField, .picker, .slider, .link, .form, .shape, .spacer, .tappable:
            return true
        }
    }

    /// Whether a form in the tree shows a problem with a field: a submitted
    /// form that comes back this way keeps the palette open.
    public var hasFormErrors: Bool {
        if case .form(let form) = self { return form.fields.contains { $0.error != nil } }
        return children.contains(where: \.hasFormErrors)
    }

    /// Everything in the tree a user can press, in order, each named as it
    /// would be out of context. The palette, `actions` and the agent gateway
    /// read this rather than walking the tree themselves.
    public var affordances: [Affordance] {
        switch self {
        case .row(let row):
            return row.actions.enumerated().map { index, action in
                Affordance(
                    title: index == 0 ? row.title : "\(action.title): \(row.title)",
                    subtitle: row.subtitle ?? (index == 0 ? action.title : nil),
                    symbol: row.symbol,
                    kind: action.navigate.map { .navigate($0, action: action.id) } ?? .action(action.id, value: nil)
                )
            }
        case .button(let title, let symbol, _, let action):
            return [Affordance(title: title, symbol: symbol, kind: .action(action, value: nil))]
        case .toggle(let title, let isOn, let action):
            return [Affordance(title: "\(isOn ? "Turn off" : "Turn on") \(title)", symbol: "switch.2", kind: .action(action, value: .bool(!isOn)))]
        case .textField(let placeholder, _, let action):
            return [Affordance(title: placeholder, kind: .input(action))]
        case .picker(let title, _, _, _, let action), .slider(let title, _, _, _, _, let action):
            return [Affordance(title: title, kind: .input(action))]
        case .form(let form):
            return [Affordance(title: form.submitTitle, kind: .input(form.action))]
        case .link(let title, let url):
            return [Affordance(title: title, subtitle: url, symbol: "link", kind: .open(url))]
        case .tappable(let content, let action):
            let inside = content.affordances.map { affordance in
                var affordance = affordance
                affordance.isInsideTappable = true
                return affordance
            }
            return [Affordance(title: content.plainText, kind: .tappable(action))] + inside
        case .stack, .list, .section, .styled:
            return children.flatMap(\.affordances)
        case .text, .label, .badge, .progress, .divider, .labeled, .chart, .empty, .shape, .image, .timer, .spacer:
            return []
        }
    }
}

/// Something a user can press in a view tree, and what pressing it does.
public struct Affordance: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A button, a toggle or a row action: pressing sends the action with
        /// `value`, so it can be pressed from anywhere.
        case action(ActionID, value: EventValue?)
        /// Custom content as a button. Its title is the words it shows, which
        /// may be none (an icon), and then nothing can name it.
        case tappable(ActionID)
        /// A text field, picker, slider or form: it sends what the user enters,
        /// so it can't be pressed without its control.
        case input(ActionID)
        /// A link: the host opens the URL and the plugin never hears of it.
        case open(String)
        /// A row action that opens one of the plugin's commands instead of
        /// sending `action`.
        case navigate(CommandTarget, action: ActionID)
    }

    public var title: String
    public var subtitle: String?
    public var symbol: String?
    public var kind: Kind
    /// Inside a tappable's content. The palette lists only the tappable,
    /// whose content is its label; the plugin still accepts the action.
    public var isInsideTappable = false

    public init(title: String, subtitle: String? = nil, symbol: String? = nil, kind: Kind) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.kind = kind
    }

    /// The id the plugin knows this by; `nil` for a link.
    public var action: ActionID? {
        switch kind {
        case .action(let action, _), .tappable(let action), .input(let action), .navigate(_, let action):
            return action
        case .open:
            return nil
        }
    }
}

/// The host's list filter, shared by panels and the palette.
public enum RowFilter {
    /// The children whose rows match `query`. Sections are filtered inside
    /// and dropped when empty. Plain rows come back best match first.
    public static func filter(_ children: [ViewNode], query: String) -> [ViewNode] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return children }
        return scored(children, query: query).map(\.node)
    }

    static func scored(_ children: [ViewNode], query: String) -> [(node: ViewNode, score: Int)] {
        let matches = children.compactMap { child -> (node: ViewNode, score: Int)? in
            if case .section(let title, let inner) = child {
                let kept = scored(inner, query: query)
                guard let best = kept.map(\.score).max() else { return nil }
                return (.section(title: title, children: kept.map(\.node)), best)
            }
            let best = child.rows.compactMap(score(query)).max()
            return best.map { (child, $0) }
        }
        let allRows = matches.allSatisfy { if case .row = $0.node { return true } else { return false } }
        guard allRows else { return matches }
        return matches.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
    }

    static func score(_ query: String) -> (RowNode) -> Int? {
        { row in
            let title = TextMatch.score(query, in: row.title)
            let subtitle = row.subtitle.flatMap { TextMatch.score(query, in: $0) }.map { $0 - 50 }
            let preview = row.preview?.text.flatMap { $0.lowercased().contains(query.lowercased()) ? 300 : nil }
            return [title, subtitle, preview].compactMap { $0 }.max()
        }
    }

    /// One line of a filtered list as the palette walks it with the keyboard.
    public enum Item: Identifiable, Equatable, Sendable {
        case header(String)
        case row(RowNode)

        public var id: String {
            switch self {
            case .header(let title): return "header|\(title)"
            case .row(let row): return row.key
            }
        }
    }

    /// The rows of a list after the filter (a searchable list only), with
    /// section titles as headers; `nil` when `root` isn't a list of rows and
    /// sections of rows, which the palette then draws as a panel.
    public static func items(in root: ViewNode, query: String) -> [Item]? {
        guard case .list(let searchable, let children) = root else { return nil }
        let shown = searchable ? filter(children, query: query) : children
        var items: [Item] = []
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
            case .text, .label, .stack, .list, .badge, .button, .toggle, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .link, .empty, .form, .styled, .shape, .image, .timer, .spacer, .tappable:
                return nil
            }
        }
        return items
    }
}
