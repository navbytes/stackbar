/// What macOS already does well, so Stackbar doesn't redo it: shown in
/// Settings > General under "Use macOS for these", for people coming from
/// launchers that bundle everything.
public enum MacOSAlternatives {
    public struct Item: Equatable, Sendable {
        public var title: String
        /// What to press or where to look, in a sentence.
        public var how: String
        public var symbol: String
        /// The System Settings pane to open, as an `x-apple.systempreferences:` URL.
        public var settings: String?
    }

    public static let items: [Item] = [
        Item(title: "Open apps and files, do math", how: "⌘Space opens Spotlight. Type an app, a file, a sum or a unit conversion like 5 km in miles.", symbol: "magnifyingglass", settings: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension"),
        Item(title: "Quick keys for actions", how: "In Spotlight, give an action a short quick key, then type it to run the action. Stackbar's commands show up in Spotlight too.", symbol: "command", settings: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension"),
        Item(title: "Tile windows", how: "Drag a window to a screen edge, or press Fn-Control with an arrow key. Window > Move & Resize lists the layouts.", symbol: "rectangle.split.2x1", settings: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"),
        Item(title: "Expand plain abbreviations", how: "Text Replacements turn a short keyword into text as you type, in every app. Use Stackbar's Snippets for placeholders and the cursor.", symbol: "textformat.abc", settings: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
        Item(title: "Emoji and symbols", how: "Fn-E (or Control-Command-Space) opens the Character Viewer.", symbol: "face.smiling", settings: nil),
        Item(title: "Lock the screen", how: "Control-Command-Q locks the Mac right away.", symbol: "lock", settings: nil),
    ]

    /// What Stackbar adds on top, for the same page.
    public static let stackbarDoes = "Stackbar adds what macOS doesn't: clipboard history you paste from with ⌘⇧V, snippets with placeholders and a cursor, quicklinks that ask for input, and plugin commands from the palette (⌃⌥Space), hotkeys and links."
}
