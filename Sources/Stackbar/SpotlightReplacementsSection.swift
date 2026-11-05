#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarUI

/// Settings › General: what to type in the palette instead of reaching for
/// Spotlight, with Install for a plugin that isn't there.
struct SpotlightReplacementsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsGroup("In the Palette", footer: SpotlightReplacements.stillMacOS) {
            ForEach(SpotlightReplacements.items, id: \.title) { item in
                SettingsRow(symbol: item.symbol, color: .indigo, title: item.title, caption: item.how) {
                    if !model.controllers.contains(where: { $0.pluginID == item.pluginID }) {
                        Button("Install…") {
                            model.storeFocus = item.pluginID
                            AppDelegate.shared?.showStore()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}
#endif
