#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore

/// Settings > General: what to keep using macOS for, with a button to each
/// System Settings pane.
struct MacOSAlternativesSection: View {
    var body: some View {
        Section {
            ForEach(MacOSAlternatives.items, id: \.title) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.how).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let settings = item.settings, let url = URL(string: settings) {
                        Button("Open Settings") { NSWorkspace.shared.open(url) }.controlSize(.small)
                    }
                }
            }
            Text(MacOSAlternatives.stackbarDoes).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Use macOS for these")
        }
    }
}
#endif
