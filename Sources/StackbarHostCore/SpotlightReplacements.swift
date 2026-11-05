/// What Stackbar's palette does in place of Spotlight and other launchers,
/// and the plugin that does it: shown in Settings › General under "In the
/// Palette", with an Install button for a missing plugin. `stillMacOS` is
/// the little that macOS still does better.
public enum SpotlightReplacements {
    public struct Item: Equatable, Sendable {
        public var title: String
        /// What to type or press, in a sentence.
        public var how: String
        public var symbol: String
        /// The store plugin that does it.
        public var pluginID: String
    }

    public static let items: [Item] = [
        Item(title: "Open apps and settings", how: "Type an app's or a System Settings pane's name.", symbol: "square.grid.2x2", pluginID: "io.navbytes.stackbar.plugins.applications"),
        Item(title: "Find files", how: "Type part of a file's name; ⌘K shows Reveal in Finder and Copy Path.", symbol: "doc.text.magnifyingglass", pluginID: "io.navbytes.stackbar.plugins.file-search"),
        Item(title: "Sums and conversions", how: "Type 12% of 340, 5 km in miles or 100 usd in eur.", symbol: "plus.forwardslash.minus", pluginID: "io.navbytes.stackbar.plugins.calculator"),
        Item(title: "Clipboard history", how: "Press ⌘⇧V, or type what you copied.", symbol: "doc.on.clipboard", pluginID: "io.navbytes.stackbar.clipboard"),
        Item(title: "Lock, sleep and restart", how: "Type lock, sleep, empty trash or dark mode.", symbol: "power", pluginID: "io.navbytes.stackbar.plugins.system-commands"),
        Item(title: "Tile windows", how: "Type left half, center or next display.", symbol: "rectangle.split.2x1", pluginID: "io.navbytes.stackbar.plugins.workspaces"),
        Item(title: "Emoji", how: "Type a colon and a word, like :tada.", symbol: "face.smiling", pluginID: "io.navbytes.stackbar.plugins.emoji"),
        Item(title: "Snippets and quicklinks", how: "Type a snippet's or link's name; placeholders ask for what they need.", symbol: "text.quote", pluginID: "io.navbytes.stackbar.snippets"),
    ]

    /// Still best left to macOS, for the footer.
    public static let stillMacOS = "Text Replacements (System Settings › Keyboard) still expand plain abbreviations as you type, in every app."
}
