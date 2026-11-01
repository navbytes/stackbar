import Foundation

/// Which plugins the user turned off, by plugin id, so the choice survives
/// the file moving (a reinstall, an update, the move to the store).
///
/// The id is only known once a plugin is built, so each file remembers the
/// id it last loaded as. That lets the host skip building a plugin that is
/// off. Before 0.11.0 the choice was kept per file (`disabled.<path>`);
/// `adopt` carries such a setting over to the id.
public final class PluginSwitches: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private static let offKey = "pluginsOff"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The ids of the plugins that are off.
    public var offIDs: Set<String> {
        lock.withLock { Set(defaults.stringArray(forKey: Self.offKey) ?? []) }
    }

    public func isOn(_ pluginID: String) -> Bool { !offIDs.contains(pluginID) }

    public func set(_ pluginID: String, on: Bool) {
        lock.withLock {
            var off = Set(defaults.stringArray(forKey: Self.offKey) ?? [])
            if on { off.remove(pluginID) } else { off.insert(pluginID) }
            defaults.set(off.sorted(), forKey: Self.offKey)
        }
    }

    /// Whether the plugin in `file` is on, as far as the host knows before
    /// building it: by the id it last loaded as, else the old per-file
    /// setting, else on.
    public func isOn(file: URL) -> Bool {
        if let id = knownID(for: file) { return isOn(id) }
        return !defaults.bool(forKey: Self.legacyKey(file))
    }

    /// The id the plugin in `file` last loaded as.
    public func knownID(for file: URL) -> String? {
        defaults.string(forKey: "pluginID." + file.standardizedFileURL.path)
    }

    /// Records the id `file` loaded as, and moves an old per-file setting to
    /// it. Returns whether the plugin is on.
    @discardableResult
    public func adopt(_ pluginID: String, for file: URL) -> Bool {
        defaults.set(pluginID, forKey: "pluginID." + file.standardizedFileURL.path)
        let legacy = Self.legacyKey(file)
        if defaults.object(forKey: legacy) != nil {
            if defaults.bool(forKey: legacy) { set(pluginID, on: false) }
            defaults.removeObject(forKey: legacy)
        }
        return isOn(pluginID)
    }

    /// Forgets a file's remembered id (it was removed).
    public func forget(file: URL) {
        defaults.removeObject(forKey: "pluginID." + file.standardizedFileURL.path)
        defaults.removeObject(forKey: Self.legacyKey(file))
    }

    private static func legacyKey(_ file: URL) -> String { "disabled." + file.path }
}
