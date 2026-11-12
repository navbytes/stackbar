#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol
import StackbarUI

/// A plugin's icon: its SF Symbol, white, on a tile in its accent. Settings,
/// the Store and the store's plugin pages all draw plugins with this, so a
/// plugin looks the same wherever it appears.
struct PluginIcon: View {
    var symbol: String?
    var accent: Accent?
    var size: CGFloat = 40

    init(symbol: String?, accent: Accent?, size: CGFloat = 40) {
        self.symbol = symbol
        self.accent = accent
        self.size = size
    }

    init(manifest: Manifest?, size: CGFloat = 40) {
        self.init(symbol: manifest?.symbol, accent: manifest?.accent, size: size)
    }

    var body: some View {
        let name = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0 } ?? "puzzlepiece.extension.fill"
        SettingsIconTile(symbol: name, color: PluginIcon.color(accent), size: size)
    }

    /// The system colour nearest each design-system hue; grey without one.
    static func color(_ accent: Accent?) -> Color {
        guard let accent else { return .gray }
        switch accent {
        case .blue: return .blue
        case .indigo: return .indigo
        case .violet: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .amber: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .cyan: return .cyan
        case .graphite: return .gray
        }
    }
}

/// A white SF Symbol on a rounded, gradient tile: the sidebar's section
/// icons, permission rows and plugin icons.
struct SettingsIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// The dot beside a plugin in the sidebar and under its name on its page.
struct StatusDot: View {
    let tone: SettingsPresentation.Status.Tone
    var size: CGFloat = 7

    var body: some View {
        Circle().fill(Self.color(tone)).frame(width: size, height: size).accessibilityHidden(true)
    }

    static func color(_ tone: SettingsPresentation.Status.Tone) -> Color {
        switch tone {
        case .good: return .green
        case .busy: return .orange
        case .attention: return .orange
        case .failed: return .red
        case .off: return Color.secondary.opacity(0.5)
        }
    }
}

/// A Settings page: a scrolling column of groups at a readable width.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            // The section links on a long plugin page jump with this.
            .environment(\.stackbarScrollTo, { key in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(key, anchor: .top) }
            })
        }
    }
}

/// Above a long plugin settings surface: a filter and a link to each
/// section, so a page of eighteen sections is one click from any of them.
struct SettingsOutlineBar: View {
    let outline: PluginSettingsOutline
    @Binding var filter: String
    let allCollapsed: Bool
    /// Unfolds a section before jumping to it.
    let open: (PluginSettingsOutline.Part) -> Void
    let toggleAll: (_ fold: Bool) -> Void

    @Environment(\.stackbarScrollTo) private var scrollTo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter settings", text: $filter)
                        .textFieldStyle(.plain)
                    if !filter.isEmpty {
                        Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear the filter")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SettingsGroupStyle.fill, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SettingsGroupStyle.stroke))
                Button(allCollapsed ? "Unfold All" : "Fold All") { toggleAll(!allCollapsed) }
                    .controlSize(.small)
                    .disabled(!filter.isEmpty)
            }
            if filter.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(outline.titled, id: \.index) { part in
                            Button(part.title ?? "") {
                                open(part)
                                let anchor = PluginSettingsOutline.anchor(part.index)
                                DispatchQueue.main.async { scrollTo?(anchor) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

/// The top of a page: a large icon, the title, a line of description, an
/// optional status line and a control at the trailing edge.
struct SettingsPageHeader<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var status: SettingsPresentation.Status?
    var detail: String?
    @ViewBuilder let icon: Icon
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.bold))
                if let subtitle {
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if status != nil || detail != nil {
                    HStack(spacing: 6) {
                        if let status {
                            StatusDot(tone: status.tone)
                            Text(status.text)
                        }
                        if let detail {
                            if status != nil { Text("·") }
                            Text(detail)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// One row in a group: an optional tile, a title with a caption under it,
/// and controls at the trailing edge.
struct SettingsRow<Trailing: View>: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    var caption: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let symbol { SettingsIconTile(symbol: symbol, color: color) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(symbol: String? = nil, color: Color = .gray, title: String, caption: String? = nil) {
        self.init(symbol: symbol, color: color, title: title, caption: caption) { EmptyView() }
    }
}

/// A small capsule label: "Allowed", "Asks", "Off".
struct StatusTag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

extension SettingsPresentation.Access {
    @MainActor var color: Color { PluginIcon.color(accent) }
}
#endif
