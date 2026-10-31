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

    /// The app group's directory when the app is signed with one.
    public static func shared(appGroup: String = "group.io.navbytes.stackbar") -> WidgetSnapshotStore {
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
