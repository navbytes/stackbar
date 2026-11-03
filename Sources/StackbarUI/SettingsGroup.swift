#if canImport(SwiftUI)
import SwiftUI

/// A titled, rounded group of rows with hairlines between them, like a
/// section in System Settings. The Settings window builds its pages from
/// these, and draws a plugin's own `settings` sections with them too, so the
/// two read as one page.
public struct SettingsGroup<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().padding(.leading, 12) }
                        row
                            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
            }
            .background(SettingsGroupStyle.fill, in: SettingsGroupStyle.shape)
            .overlay(SettingsGroupStyle.shape.strokeBorder(SettingsGroupStyle.stroke))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The fill, hairline and shape every `SettingsGroup` shares.
public enum SettingsGroupStyle {
    public static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }
    public static var fill: Color { Color.primary.opacity(0.035) }
    public static var stroke: Color { Color.primary.opacity(0.08) }
}

/// A toggle drawn as a label with a small switch at the row's trailing edge.
public struct TrailingSwitchStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
#endif
