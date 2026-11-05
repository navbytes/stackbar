import Foundation

/// Stackbar's own places, as links and as palette entries: its Settings
/// window (on a page, when one is named) and the Plugin Store.
///
/// `stackbar://settings`, `stackbar://settings/commands`, `stackbar://store`.
/// A Store link with a plugin id (`stackbar://store/<id>`) is a `StoreLink`.
public enum AppLink: Equatable, Sendable {
    case settings(page: String?)
    case store

    /// The Settings pages a link can name, in sidebar order.
    public static let settingsPages = ["general", "commands", "agents", "privacy", "store"]

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "stackbar", let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map { $0.lowercased() }
        switch host {
        case "settings":
            guard parts.count <= 1 else { return nil }
            if let page = parts.first {
                guard Self.settingsPages.contains(page) else { return nil }
                self = .settings(page: page)
            } else {
                self = .settings(page: nil)
            }
        case "store":
            guard parts.isEmpty else { return nil }
            self = .store
        default:
            return nil
        }
    }

    public var url: String {
        switch self {
        case .settings(let page): return "stackbar://settings" + (page.map { "/" + $0 } ?? "")
        case .store: return "stackbar://store"
        }
    }
}

extension PaletteIndex {
    /// The id the app's own entries go under, so their usage and favourites
    /// are kept like a plugin's.
    public static let appID = "io.navbytes.stackbar"

    /// Stackbar's own entries: found by typing "settings" or "store", as
    /// Raycast finds its own.
    public static let appEntries: [Entry] = [
        Entry(pluginID: appID, pluginName: "Stackbar", title: "Stackbar Settings", subtitle: "Open Settings", symbol: "gearshape.fill",
              kind: .open(AppLink.settings(page: nil).url), keywords: ["settings", "preferences", "config", "options"]),
        Entry(pluginID: appID, pluginName: "Stackbar", title: "Commands & Hotkeys", subtitle: "Settings", symbol: "command",
              kind: .open(AppLink.settings(page: "commands").url), keywords: ["aliases", "shortcuts", "hotkeys"]),
        Entry(pluginID: appID, pluginName: "Stackbar", title: "Privacy & Secrets", subtitle: "Settings", symbol: "hand.raised.fill",
              kind: .open(AppLink.settings(page: "privacy").url), keywords: ["permissions", "secrets", "privacy"]),
        Entry(pluginID: appID, pluginName: "Stackbar", title: "Plugin Store", subtitle: "Browse and install plugins", symbol: "bag.fill",
              kind: .open(AppLink.store.url), keywords: ["store", "plugins", "extensions", "install"]),
    ]
}
