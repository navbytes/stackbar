import Foundation

/// Where the app runs from, and whether to offer moving it. macOS runs an
/// app straight from Downloads or a disk image under App Translocation, a
/// random read-only path: updates can't replace it there, and login items
/// point at a path that is gone after a restart.
public enum AppLocation {
    /// Whether the app at `bundlePath` should offer to move to Applications.
    public static func shouldOfferMove(bundlePath: String, home: String) -> Bool {
        guard bundlePath.hasSuffix(".app") else { return false }
        if isTranslocated(bundlePath) { return true }
        if bundlePath.hasPrefix("/Volumes/") { return true }
        let folders = ["/Applications/", home.hasSuffix("/") ? home + "Applications/" : home + "/Applications/"]
        return !folders.contains { bundlePath.hasPrefix($0) }
    }

    public static func isTranslocated(_ bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    /// Where `stackbarctl` goes on the PATH.
    public static let commandLineLink = "/usr/local/bin/stackbarctl"

    /// The shell line that links `stackbarctl` onto the PATH, quoted for
    /// `do shell script … with administrator privileges`.
    public static func linkCommand(to tool: String, at link: String = commandLineLink) -> String {
        let folder = (link as NSString).deletingLastPathComponent
        return "mkdir -p \(quoted(folder)) && ln -sf \(quoted(tool)) \(quoted(link))"
    }

    /// Single-quoted for the shell, with any `'` closed and escaped.
    public static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
