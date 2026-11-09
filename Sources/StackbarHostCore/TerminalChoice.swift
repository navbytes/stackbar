import Foundation

/// The terminal a plugin's "open in terminal" uses: the app that opens
/// `.command` files (Terminal unless changed in Finder), or one picked in
/// Settings. Kept in UserDefaults under `defaultsKey`.
public struct TerminalChoice: Equatable, Sendable, Identifiable {
    /// How the app is handed the script.
    public enum Launch: Equatable, Sendable {
        /// Opens the `.command` file, as Terminal, iTerm and Warp do.
        case openFile
        /// Started with `-e <shell> <file>`, as Ghostty, kitty and WezTerm
        /// need (they don't open `.command` files).
        case execute
    }

    public var bundleID: String
    public var name: String
    public var launch: Launch
    public var id: String { bundleID }

    public static let defaultsKey = "terminalApp"

    /// The terminals Stackbar knows how to start, in the order offered.
    public static let known: [TerminalChoice] = [
        TerminalChoice(bundleID: "com.apple.Terminal", name: "Terminal", launch: .openFile),
        TerminalChoice(bundleID: "com.googlecode.iterm2", name: "iTerm", launch: .openFile),
        TerminalChoice(bundleID: "dev.warp.Warp-Stable", name: "Warp", launch: .openFile),
        TerminalChoice(bundleID: "com.mitchellh.ghostty", name: "Ghostty", launch: .execute),
        TerminalChoice(bundleID: "net.kovidgoyal.kitty", name: "kitty", launch: .execute),
        TerminalChoice(bundleID: "com.github.wez.wezterm", name: "WezTerm", launch: .execute),
    ]

    /// The choice saved under `bundleID`; nil (the `.command` default) for
    /// none or one Stackbar doesn't know.
    public static func chosen(_ bundleID: String?) -> TerminalChoice? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return known.first { $0.bundleID == bundleID }
    }

    /// The arguments an `.execute` terminal is started with to run `script`.
    public func arguments(running script: String) -> [String] {
        switch launch {
        case .openFile: return []
        case .execute:
            // kitty and WezTerm take the command after their own word.
            if bundleID == "com.github.wez.wezterm" { return ["start", "--", "/bin/zsh", "-l", script] }
            if bundleID == "net.kovidgoyal.kitty" { return ["/bin/zsh", "-l", script] }
            return ["-e", "/bin/zsh", "-l", script]
        }
    }
}
