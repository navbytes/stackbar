import Foundation
import StackbarProtocol

/// Folders the user picked for a plugin with `Stackbar.chooseFolder`.
///
/// The pick is the consent, the way picking a file in an Open panel is: the
/// plugin's commands may then run in that folder (and inside it) until the
/// user removes it on the plugin's Settings page. The plugin's own sandbox
/// doesn't change; only `Stackbar.run(workingDirectory:)` looks here.
public final class FolderGrants: @unchecked Sendable {
    /// Where the grants are saved; `nil` keeps them in memory only.
    public let file: URL?
    private let lock = NSLock()
    private var grants: [String: [String]]
    private var observers: [@Sendable (String) -> Void] = []

    public init(file: URL?) {
        self.file = file
        self.grants = JSONFile.read(from: file) ?? [:]
    }

    /// Calls `body` with the plugin's id after its folders change.
    public func observe(_ body: @escaping @Sendable (String) -> Void) {
        lock.withLock { observers.append(body) }
    }

    /// The plugin's folders, full paths, in the order they were picked.
    public func folders(for pluginID: String) -> [String] {
        lock.withLock { grants[pluginID] ?? [] }
    }

    /// Why a folder can't be granted, or nil when it can. A folder this broad
    /// is too much for one click in a panel to stand for.
    public static func refusal(_ path: String, home: String = NSHomeDirectory()) -> String? {
        let canonical = CommandRunGate.canonical(NSString(string: path).expandingTildeInPath)
        let home = CommandRunGate.canonical(home)
        let tooBroad = ["/", "/Users", "/System", "/Library", "/Applications", "/private", "/usr", "/bin", "/sbin", "/etc", "/var", "/private/var", "/private/etc", "/Volumes", home]
        if tooBroad.contains(canonical) { return "\(path) is too broad; choose a folder inside it" }
        let library = home + "/Library"
        if canonical == library || canonical.hasPrefix(library + "/") { return "folders in ~/Library can't be chosen" }
        for system in ["/System/", "/usr/", "/bin/", "/sbin/", "/private/etc/", "/private/var/db/"] where canonical.hasPrefix(system) {
            return "system folders can't be chosen"
        }
        return nil
    }

    /// Adds a folder the user picked. Returns the canonical path, or throws
    /// when it is too broad. Adding one already granted changes nothing.
    @discardableResult
    public func add(_ path: String, for pluginID: String) throws -> String {
        if let refusal = Self.refusal(path) { throw SystemServiceError(refusal) }
        let canonical = CommandRunGate.canonical(NSString(string: path).expandingTildeInPath)
        let changed = try lock.withLock { () -> Bool in
            var list = grants[pluginID] ?? []
            guard !list.contains(canonical) else { return false }
            list.append(canonical)
            try change(pluginID, to: list)
            return true
        }
        if changed { notify(pluginID) }
        return canonical
    }

    /// Removes one folder; commands stop running there at once.
    public func remove(_ path: String, for pluginID: String) throws {
        let canonical = CommandRunGate.canonical(NSString(string: path).expandingTildeInPath)
        let changed = try lock.withLock { () -> Bool in
            guard var list = grants[pluginID], list.contains(canonical) else { return false }
            list.removeAll { $0 == canonical }
            try change(pluginID, to: list.isEmpty ? nil : list)
            return true
        }
        if changed { notify(pluginID) }
    }

    /// Forgets every folder of a plugin (when it is uninstalled).
    public func removeAll(for pluginID: String) throws {
        let changed = try lock.withLock { () -> Bool in
            guard grants[pluginID] != nil else { return false }
            try change(pluginID, to: nil)
            return true
        }
        if changed { notify(pluginID) }
    }

    private func notify(_ pluginID: String) {
        for observer in lock.withLock({ observers }) { observer(pluginID) }
    }

    /// Call with the lock held; puts the old list back if saving fails.
    private func change(_ pluginID: String, to list: [String]?) throws {
        let previous = grants[pluginID]
        grants[pluginID] = list
        guard let file else { return }
        do {
            try JSONFile.write(grants, to: file, encoder: .readable)
        } catch {
            grants[pluginID] = previous
            throw error
        }
    }
}
