#if canImport(SwiftUI)
import SwiftUI
import StackbarProtocol

/// An `editor` where it can't be edited: a widget, or a snapshot, which
/// ImageRenderer can't draw an NSTextView into. Shows the text as it is.
struct SnapshotEditor: View {
    let editor: EditorNode

    var body: some View {
        Text(editor.text.isEmpty ? editor.placeholder ?? "" : editor.text)
            .foregroundStyle(editor.text.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(8)
    }
}

/// A text field as `Snapshot` draws it: AppKit's field doesn't render off
/// screen, so a PNG would show a placeholder block instead.
struct SnapshotField: View {
    let placeholder: String
    let text: String

    var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
    }
}

/// A picker as `Snapshot` draws it: segments, or a menu button with its title.
struct SnapshotPicker: View {
    let title: String
    let options: [String]
    let selection: String?
    let segmented: Bool

    var body: some View {
        if segmented {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    Text(option)
                        .font(.system(size: 12, weight: option == selection ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 5).fill(option == selection ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
                            .shadow(color: .black.opacity(option == selection ? 0.15 : 0), radius: 1, y: 0.5))
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.15)))
        } else {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(selection ?? "Choose")
                        .foregroundStyle(selection == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(.background)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5))
            }
        }
    }
}

/// A slider as `Snapshot` draws it: AppKit's slider is a placeholder block
/// off screen.
struct SnapshotSlider: View {
    let title: String
    let fraction: Double
    let tint: Color

    var body: some View {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                let x = (proxy.size.width - 16) * clamped
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 4)
                    Capsule().fill(tint).frame(width: x + 8, height: 4)
                    Circle().fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: 16, height: 16)
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)
        }
    }
}

/// A toggle as `Snapshot` draws it: a switch after its title in a settings
/// group, a checkbox before it anywhere else.
struct SnapshotToggle: View {
    let title: String
    let isOn: Bool
    let trailing: Bool

    var body: some View {
        if trailing {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.3))
                    Circle().fill(.white).padding(1.5).shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                }
                .frame(width: 26, height: 15)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(title)
            }
        }
    }
}
#endif
