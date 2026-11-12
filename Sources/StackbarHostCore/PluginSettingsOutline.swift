import Foundation
import StackbarProtocol

/// A plugin's `settings` tree split into its top-level sections, so the
/// Settings window can help with a long page whatever the plugin draws:
/// links that jump to a section, a filter that keeps only the sections that
/// mention what you typed, and sections you can fold away. Plugins don't
/// change for any of this; it reads the tree they already send.
public struct PluginSettingsOutline: Equatable, Sendable {
    /// One top-level piece of the settings tree.
    public struct Part: Equatable, Sendable {
        /// Its place in the tree, which is also its scroll anchor.
        public var index: Int
        /// The section's title; `nil` for an untitled section or a loose node.
        public var title: String?
        /// The node itself, drawn as the plugin sent it.
        public var node: ViewNode
        /// Every word a user could look for in it, lowercased.
        public var searchText: String
    }

    /// From this many titled sections on, a page gets section links and a
    /// filter. Fewer fit on a screen or two and need neither.
    public static let longPageSections = 5

    public var parts: [Part]

    public init(_ root: ViewNode) {
        let nodes: [ViewNode]
        if case .stack(.vertical, _, _, let children) = root {
            nodes = children
        } else {
            nodes = [root]
        }
        parts = nodes.enumerated().map { index, node in
            var title: String?
            if case .section(let name, _) = node, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { title = name }
            return Part(index: index, title: title, node: node, searchText: Self.words(in: node).lowercased())
        }
    }

    /// The scroll anchor of the part at `index`.
    public static func anchor(_ index: Int) -> String { "plugin-settings-\(index)" }

    /// The titled sections, in order: what the links at the top name.
    public var titled: [Part] { parts.filter { $0.title != nil } }

    /// Whether the page is long enough for links, a filter and folding.
    public var isLong: Bool { titled.count >= Self.longPageSections }

    /// The parts to show for a filter. Every word of the query has to appear
    /// somewhere in the part (title, labels, captions, options). An empty
    /// query shows everything.
    public func filtered(_ query: String) -> [Part] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return parts }
        return parts.filter { part in words.allSatisfy { part.searchText.contains($0) } }
    }

    /// Everything readable in a node: texts, labels, row titles and
    /// subtitles, control titles, field placeholders and picker options.
    static func words(in node: ViewNode) -> String {
        var found: [String] = []
        func walk(_ node: ViewNode) {
            switch node {
            case .text(let string, _, _), .badge(let string, _):
                found.append(string)
            case .label(let title, _, _), .button(let title, _, _, _, _), .toggle(let title, _, _), .link(let title, _):
                found.append(title)
            case .section(let title, _):
                if let title { found.append(title) }
            case .labeled(let label, let value, _):
                found.append(label)
                found.append(value)
            case .textField(let placeholder, _, _):
                found.append(placeholder)
            case .picker(let title, let options, _, _, _):
                found.append(title)
                found.append(contentsOf: options)
            case .slider(let title, _, _, _, _, _, _):
                found.append(title)
            case .row(let row):
                found.append(row.title)
                if let subtitle = row.subtitle { found.append(subtitle) }
                found.append(contentsOf: row.actions.map(\.title))
                row.accessories.forEach(walk)
            case .empty(let title, _, let message):
                found.append(title)
                if let message { found.append(message) }
            case .form(let form):
                found.append(form.submitTitle)
                found.append(contentsOf: form.fields.map(\.label))
            default:
                break
            }
            node.children.forEach(walk)
        }
        walk(node)
        return found.joined(separator: " ")
    }
}

/// Which of a plugin's settings sections the user folded, by title, kept in
/// the app's defaults so a page opens the way it was left.
public enum PluginSettingsFolds {
    static func key(_ pluginID: String) -> String { "pluginSettingsFolded.\(pluginID)" }

    public static func load(_ pluginID: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key(pluginID)) ?? [])
    }

    public static func save(_ titles: Set<String>, for pluginID: String, defaults: UserDefaults = .standard) {
        if titles.isEmpty {
            defaults.removeObject(forKey: key(pluginID))
        } else {
            defaults.set(titles.sorted(), forKey: key(pluginID))
        }
    }
}
