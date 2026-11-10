import Foundation

/// The usual shape of a row's preview view (`Row.preview(text:caption:view:)`):
/// a tile, a title and a line of detail, then the facts, one `Metadata` each,
/// then anything else (a chain of steps, a chart, a swatch).
///
/// ```swift
/// Row(pr.title, key: pr.url)
///     .preview(text: checksText(pr), caption: pr.repo) {
///         PreviewDetail("#\(pr.number) checks", subtitle: pr.repo, symbol: "checkmark.seal", theme: .critical) {
///             Metadata("Status", pill: "2 failing", theme: .critical)
///             Metadata("Updated", pr.updated)
///         }
///     }
/// ```
public struct PreviewDetail: StackbarView {
    var title: String
    var subtitle: String?
    var symbol: String?
    var theme: Theme
    var content: ViewContent

    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, theme: Theme = .neutral, @ViewBuilder content: () -> ViewContent = { [] }) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.theme = theme
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s + 2) {
                if let symbol { IconTile(symbol, theme: theme, size: 32) }
                VStack(spacing: Space.xxs) {
                    Text(title).typography(.title)
                    if let subtitle { Text(subtitle).role(.secondary).typography(.caption) }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .frame(fillWidth: true, alignment: .leading)
        .resolve(in: context)
    }
}

/// One fact in a preview: its name on the left and its value, or a colored
/// `Pill`, on the right. Raycast calls these a detail's metadata.
public struct Metadata: StackbarView {
    var label: String
    var value: String
    var role: Role
    var pill: Theme?
    var symbol: String?

    /// A plain value; `role` colors it (`.critical` for "Failed").
    public init(_ label: String, _ value: String, role: Role = .primary) {
        self.label = label
        self.value = value
        self.role = role
    }

    /// A state in the theme's color: "Running", "2 failing", "Deployed".
    public init(_ label: String, pill: String, theme: Theme, symbol: String? = nil) {
        self.label = label
        self.value = pill
        self.role = .primary
        self.pill = theme
        self.symbol = symbol
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        HStack(spacing: Space.s) {
            Text(label).role(.secondary).typography(.caption)
            Spacer(minLength: Space.s)
            if let pill {
                Pill(value, symbol: symbol, theme: pill)
            } else {
                Text(value).role(role).typography(.body)
            }
        }
        .frame(fillWidth: true)
        .resolve(in: context)
    }
}
