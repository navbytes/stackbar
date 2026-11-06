import Foundation
import StackbarProtocol

/// The latest widget tree of each plugin, written by the app and read by the
/// widget extension, which can't talk to plugins itself.
///
/// One JSON file per plugin in a directory both can reach: the app group
/// container in a signed build, `StackbarPaths.widgetSnapshots` otherwise.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var pluginID: String
    public var name: String
    public var node: ViewNode
    public var updatedAt: Date

    public init(pluginID: String, name: String, node: ViewNode, updatedAt: Date = Date()) {
        self.pluginID = pluginID
        self.name = name
        self.node = node
        self.updatedAt = updatedAt
    }
}

public struct WidgetSnapshotStore: Sendable {
    public var directory: URL

    public init(directory: URL) { self.directory = directory }

    /// The app group the app and the widget extension share.
    ///
    /// A macOS-style id, prefixed with the team id, because the release is
    /// signed for Developer ID without a provisioning profile. An iOS-style
    /// `group.` id must be authorised by a profile; without one the sandboxed
    /// widget is refused the container, so it found no plugins, and the app is
    /// asked to approve access (macOS 15 app group container protection). A
    /// team-prefixed id needs no profile.
    public static let appGroup = "59J9RQXYYP.io.navbytes.stackbar"

    /// The app group's directory when the app is signed with one.
    public static func shared(appGroup: String = WidgetSnapshotStore.appGroup) -> WidgetSnapshotStore {
        #if os(macOS)
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return WidgetSnapshotStore(directory: container.appendingPathComponent("Widgets", isDirectory: true))
        }
        #endif
        return WidgetSnapshotStore(directory: StackbarPaths.widgetSnapshots)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file(snapshot.pluginID), options: .atomic)
        removeLegacy(snapshot.pluginID)
    }

    public func read(_ pluginID: String) -> WidgetSnapshot? {
        (try? Data(contentsOf: file(pluginID))).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }

    public func all() -> [WidgetSnapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) } }
            .sorted { $0.name < $1.name }
    }

    public func remove(_ pluginID: String) {
        try? FileManager.default.removeItem(at: file(pluginID))
        removeLegacy(pluginID)
    }

    private func file(_ pluginID: String) -> URL {
        directory.appendingPathComponent(PluginBuilder.dataFileName(pluginID) + ".json")
    }

    /// Snapshots written before per-id file names.
    private func removeLegacy(_ pluginID: String) {
        let legacy = directory.appendingPathComponent(PluginBuilder.sanitizedName(pluginID) + ".json")
        if legacy != file(pluginID) { try? FileManager.default.removeItem(at: legacy) }
    }
}

/// A press on a widget's button, row or toggle, left by the widget extension
/// for the app to send to the plugin (protocol 17). The extension can't
/// reach plugins, so it writes one file per press in the shared directory and
/// posts `notification`; the app sends each press as if it came from the
/// panel and deletes the file.
public struct WidgetAction: Codable, Equatable, Sendable {
    public var pluginID: String
    public var action: ActionID
    public var value: EventValue?
    public var pressedAt: Date

    public init(pluginID: String, action: ActionID, value: EventValue? = nil, pressedAt: Date = Date()) {
        self.pluginID = pluginID
        self.action = action
        self.value = value
        self.pressedAt = pressedAt
    }
}

public struct WidgetActionInbox: Sendable {
    /// The Darwin notification the extension posts after leaving a press.
    public static let notification = "io.navbytes.stackbar.widget-action"
    /// Presses older than this are dropped: the app wasn't running, and
    /// acting on a stale tap minutes later would surprise.
    public static let maxAge: TimeInterval = 60

    public var directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Beside the widget snapshots, in the app group when there is one.
    public static func shared() -> WidgetActionInbox {
        WidgetActionInbox(directory: WidgetSnapshotStore.shared().directory.deletingLastPathComponent().appendingPathComponent("WidgetActions", isDirectory: true))
    }

    public func post(_ action: WidgetAction) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = String(format: "%.6f", action.pressedAt.timeIntervalSince1970) + "-" + UUID().uuidString + ".json"
        try JSONEncoder().encode(action).write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    /// Every waiting press, oldest first, each removed as it is read; ones
    /// older than `maxAge` are removed and not returned.
    public func drain(now: Date = Date()) -> [WidgetAction] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WidgetAction] = []
        for file in files {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file), let action = try? JSONDecoder().decode(WidgetAction.self, from: data) else { continue }
            if now.timeIntervalSince(action.pressedAt) <= Self.maxAge { result.append(action) }
        }
        return result
    }
}
