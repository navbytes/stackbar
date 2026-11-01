#if canImport(SwiftUI)
import SwiftUI

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
#endif
