import Foundation

// Values for the finding calls (protocol 16): the installed apps and System
// Settings panes, and files by name from Spotlight's index. The host reads
// both, so plugins stay sandboxed; these types cross the wire as JSON inside
// `HostResult.value`.

/// An installed app, or a System Settings pane, as `Stackbar.installedApps()`
/// lists it.
public struct InstalledApp: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case app
        /// A pane of System Settings; `url` opens it.
        case settingsPane
    }

    /// The app's bundle id, or the pane's extension id.
    public var id: String
    /// What Finder shows ("Visual Studio Code"), or the pane's title.
    public var name: String
    /// The `.app` bundle; for a pane, System Settings itself.
    public var path: String
    public var kind: Kind
    /// Other names it is found by: the file name when it differs.
    public var keywords: [String]
    /// What opens a pane (`x-apple.systempreferences:<id>`); nil for an app.
    public var url: String?

    public init(id: String, name: String, path: String, kind: Kind = .app, keywords: [String] = [], url: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.keywords = keywords
        self.url = url
    }
}

/// A search of Spotlight's index for files whose names hold every word.
public struct FileQuery: Codable, Equatable, Sendable {
    public var text: String
    /// At most `FileQuery.maxLimit`.
    public var limit: Int

    public static let maxLimit = 20

    public init(text: String, limit: Int = 8) {
        self.text = text
        self.limit = min(max(limit, 1), Self.maxLimit)
    }
}

/// A file or folder `Stackbar.findFiles` found.
public struct FoundFile: Codable, Equatable, Sendable {
    public var path: String
    /// The file name, as Finder shows it.
    public var name: String
    /// Its folder for showing, from `~` ("~/Documents/Plans").
    public var folder: String
    public var isFolder: Bool
    public var lastUsed: Date?

    public init(path: String, name: String, folder: String = "", isFolder: Bool = false, lastUsed: Date? = nil) {
        self.path = path
        self.name = name
        self.folder = folder
        self.isFolder = isFolder
        self.lastUsed = lastUsed
    }
}
