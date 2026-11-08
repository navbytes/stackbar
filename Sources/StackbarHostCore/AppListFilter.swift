import Foundation

/// Which of Spotlight's application bundles the app list keeps. Spotlight
/// knows every app on every indexed drive, including the helpers inside other
/// apps, updaters, Time Machine copies and system agents nobody opens; the
/// folder scan finds the usual places, and this decides what Spotlight adds.
public enum AppListFilter {
    /// Folders inside another app that hold apps people open: Xcode's
    /// Simulator and Instruments, for example.
    static let nestedAppFolders = ["/Contents/Applications/", "/Contents/Developer/Applications/"]

    /// Whether an app Spotlight found belongs in the list.
    public static func keeps(_ path: String) -> Bool {
        guard path.hasSuffix(".app") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return false }
        // Hidden folders (the Trash, .timemachine) and backups.
        if components.dropLast().contains(where: { $0.hasPrefix(".") || $0 == "Backups.backupdb" }) { return false }
        // System internals: /System/Library, /Library, ~/Library, /private,
        // /usr, /opt and the system's own volumes. The folder scan covers the
        // system apps people open.
        for (index, component) in components.enumerated().dropLast() {
            if component == "Library" { return false }
            if index == 0, ["private", "usr", "opt", "bin", "sbin", "cores"].contains(component) { return false }
        }
        if path.hasPrefix("/System/Volumes/") { return false }
        // Inside another bundle: only the folders that hold real apps.
        let inner = components.dropLast().contains { ["app", "framework", "bundle", "appex", "xpc", "plugin"].contains(($0 as NSString).pathExtension.lowercased()) }
        if inner {
            guard let range = nestedAppFolders.lazy.compactMap({ path.range(of: $0, options: .backwards) }).first else { return false }
            // Directly in that folder, not deeper inside one of its apps.
            return !path[range.upperBound...].dropLast(4).contains("/")
        }
        return true
    }
}
