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
    /// team-prefixed id needs no profile. The team comes from the build's
    /// distribution, so an organization signing with its own team gets its own group.
    public static var appGroup: String { Distribution.current.appGroup }

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
        try JSONFile.write(snapshot, to: file(snapshot.pluginID))
        removeLegacy(snapshot.pluginID)
    }

    public func read(_ pluginID: String) -> WidgetSnapshot? {
        JSONFile.read(from: file(pluginID))
    }

    public func all() -> [WidgetSnapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { JSONFile.read(WidgetSnapshot.self, from: $0) }
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

/// What the app has yet to hand the widget extension, and when. A plugin on
/// a short interval renders its widget every few seconds; writing each
/// render and reloading WidgetKit's timelines every time spends WidgetKit's
/// reload budget and the main thread. So a render that matches what was
/// last written is dropped, renders that arrive close together are written
/// together, and reloads come at most once per `minimumInterval`.
public struct WidgetPublishQueue: Sendable {
    /// How long a change waits, so a burst of renders lands as one write.
    public var debounce: TimeInterval
    /// The shortest time between two reloads.
    public var minimumInterval: TimeInterval
    private var pending: [String: WidgetSnapshot] = [:]
    private var written: [String: WidgetSnapshot] = [:]
    private var lastFlush: Date?

    public init(debounce: TimeInterval = 0.5, minimumInterval: TimeInterval = 5) {
        self.debounce = debounce
        self.minimumInterval = minimumInterval
    }

    public var isEmpty: Bool { pending.isEmpty }

    /// Queues the plugin's widget. False when it shows the same as what was
    /// last written: there is nothing to write.
    @discardableResult
    public mutating func change(_ snapshot: WidgetSnapshot) -> Bool {
        if let last = written[snapshot.pluginID], last.name == snapshot.name, last.node == snapshot.node {
            pending[snapshot.pluginID] = nil
            return false
        }
        pending[snapshot.pluginID] = snapshot
        return true
    }

    /// The plugin's widget went away (removed or turned off).
    public mutating func forget(_ pluginID: String) {
        pending[pluginID] = nil
        written[pluginID] = nil
    }

    /// Whether the plugin's widget was written and not forgotten since.
    public func remembers(_ pluginID: String) -> Bool { written[pluginID] != nil }

    /// How long to wait, from `now`, before taking what is queued.
    public func delay(now: Date) -> TimeInterval {
        guard let lastFlush else { return debounce }
        return max(debounce, lastFlush.addingTimeInterval(minimumInterval).timeIntervalSince(now))
    }

    /// The queued snapshots, by plugin id, now counted as written.
    public mutating func take(now: Date) -> [WidgetSnapshot] {
        let taken = pending.values.sorted { $0.pluginID < $1.pluginID }
        pending = [:]
        guard !taken.isEmpty else { return [] }
        for snapshot in taken { written[snapshot.pluginID] = snapshot }
        lastFlush = now
        return taken
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
        let name = String(format: "%.6f", action.pressedAt.timeIntervalSince1970) + "-" + UUID().uuidString + ".json"
        try JSONFile.write(action, to: directory.appendingPathComponent(name))
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
            guard let action = JSONFile.read(WidgetAction.self, from: file) else { continue }
            if now.timeIntervalSince(action.pressedAt) <= Self.maxAge { result.append(action) }
        }
        return result
    }
}
