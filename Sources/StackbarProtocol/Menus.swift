import Foundation

// Values for the menu calls (protocol 20): the menu bar of the app the user
// was in, read through Accessibility by the host so plugins stay sandboxed.

/// One item that does something: a leaf of the menu bar, never a submenu's
/// title or a separator.
public struct MenuItemInfo: Codable, Equatable, Hashable, Sendable {
    /// Titles from the menu bar down: `["File", "Export", "PDF…"]`.
    public var path: [String]
    /// Its key equivalent as glyphs, like `⇧⌘S`, or `nil` when it has none.
    public var shortcut: String?
    public var isEnabled: Bool
    /// Shows a check mark (a setting that is on).
    public var isChecked: Bool

    public init(path: [String], shortcut: String? = nil, isEnabled: Bool = true, isChecked: Bool = false) {
        self.path = path
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.isChecked = isChecked
    }

    /// The item's own title, the last of the path.
    public var title: String { path.last ?? "" }
    /// The menus above it, as `File › Export`.
    public var location: String { path.dropLast().joined(separator: " › ") }
}

/// The menu bar of one app, answered by `HostCall.menuItems`.
public struct MenuSnapshot: Codable, Equatable, Sendable {
    public var appID: String
    public var appName: String
    /// In menu order, the Apple menu left out. At most `maxItems`.
    public var items: [MenuItemInfo]

    public static let maxItems = 3000
    /// Submenus deeper than this are not read.
    public static let maxDepth = 5

    public init(appID: String, appName: String, items: [MenuItemInfo] = []) {
        self.appID = appID
        self.appName = appName
        self.items = Array(items.prefix(Self.maxItems))
    }

    /// Accessibility's `AXMenuItemCmdModifiers` bits: no bit set means ⌘
    /// alone; 1 adds ⇧, 2 adds ⌥, 4 adds ⌃, and 8 takes ⌘ away.
    public static func shortcut(character: String?, modifiers: Int) -> String? {
        guard let character, !character.isEmpty else { return nil }
        let key: String
        switch character {
        case " ": key = "Space"
        case "\u{8}", "\u{7f}": key = "⌫"
        case "\r", "\u{3}": key = "↩"
        case "\t": key = "⇥"
        case "\u{1b}": key = "⎋"
        default: key = character.uppercased()
        }
        var glyphs = ""
        if modifiers & 4 != 0 { glyphs += "⌃" }
        if modifiers & 2 != 0 { glyphs += "⌥" }
        if modifiers & 1 != 0 { glyphs += "⇧" }
        if modifiers & 8 == 0 { glyphs += "⌘" }
        return glyphs + key
    }
}
