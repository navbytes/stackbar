#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarUI

/// Settings > General: what to keep using macOS for, with a button to each
/// System Settings pane.
struct MacOSAlternativesSection: View {
    var body: some View {
        SettingsGroup("Use macOS for These", footer: MacOSAlternatives.stackbarDoes) {
            ForEach(MacOSAlternatives.items, id: \.title) { item in
                SettingsRow(symbol: item.symbol, color: .gray, title: item.title, caption: item.how) {
                    if let settings = item.settings, let url = URL(string: settings) {
                        Button("Open Settings") { NSWorkspace.shared.open(url) }.controlSize(.small)
                    }
                }
            }
        }
    }
}
#endif
