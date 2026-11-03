import Foundation

/// A named scene with sample data, for screenshots: the store, the website
/// and `stackbarctl render --preview <name>` show the plugin in use instead
/// of its first-run screen.
///
/// ```swift
/// static let previews: [Preview<Clipboard>] = [
///     Preview("hero", "Everything you copied") { plugin in
///         plugin.items = Clipboard.sampleItems
///     },
///     Preview("search", "Search everything") { plugin in
///         plugin.items = Clipboard.sampleItems
///         plugin.query = "invoice"
///     },
/// ]
/// ```
///
/// A preview runs on a fresh plugin after its stored values load, and the
/// plugin then never refreshes: triggers re-render what the preview set up,
/// so a scene doesn't turn back into "Connect Jira" when the launch trigger
/// can't reach Jira. Events still work, so `--event` can press things inside
/// a scene. Previews never run in the app.
///
/// Use made-up but believable data (no real people's names or emails), and
/// keep `title` short: the website uses it as a caption.
public struct Preview<Plugin: StackbarPlugin> {
    /// What `--preview` and README `<!-- preview: name -->` markers use:
    /// lowercase letters, digits and dashes.
    public var name: String
    /// A short caption, like "Search everything you copied".
    public var title: String
    public var setUp: @MainActor (Plugin) async throws -> Void

    public init(_ name: String, _ title: String, setUp: @escaping @MainActor (Plugin) async throws -> Void) {
        self.name = name
        self.title = title
        self.setUp = setUp
    }
}

public enum PreviewError: Error, CustomStringConvertible {
    case unknown(String, known: [String])

    public var description: String {
        switch self {
        case .unknown(let name, let known):
            known.isEmpty
                ? "this plugin has no previews (add `static let previews`), so there is no \"\(name)\""
                : "no preview named \"\(name)\"; this plugin has \(known.joined(separator: ", "))"
        }
    }
}

extension StackbarPlugin {
    /// The previews' names and titles, in order.
    public static var previewSpecs: [PreviewSpec] {
        previews.map { PreviewSpec(name: $0.name, title: $0.title) }
    }

    /// Sets this plugin up as the named preview.
    public func applyPreview(named name: String) async throws {
        guard let preview = Self.previews.first(where: { $0.name == name }) else {
            throw PreviewError.unknown(name, known: Self.previews.map(\.name))
        }
        try await preview.setUp(self)
    }
}
