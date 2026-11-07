import Foundation

/// A plugin's saved values: small Codable values that survive restarts,
/// kept by the host per plugin.
///
/// The host sends every saved value in `hello`, so reads are synchronous and
/// never wait. Writes update the local copy at once and are sent to the host
/// without waiting.
@MainActor
public final class PluginStorage {
    private var values: [String: String] = [:]
    /// The last decoded value per key, so reading a large value on every
    /// render decodes it once. Dropped when the key changes.
    private var decoded: [String: (type: ObjectIdentifier, value: Any)] = [:]
    /// In a preview, values start empty and writes stay here, so a scene
    /// neither shows nor overwrites what the plugin saved for real.
    var isScratch = false

    init() {}

    /// Replaces the local copy with the host's snapshot.
    public func load(_ snapshot: [String: String]) {
        values = snapshot
        decoded.removeAll()
    }

    public func value<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let json = values[key] else { return nil }
        if let cached = decoded[key], cached.type == ObjectIdentifier(T.self), let value = cached.value as? T {
            return value
        }
        guard let value = try? JSONDecoder().decode(T.self, from: Data(json.utf8)) else { return nil }
        // A class instance could be changed in place without a set, so only
        // values are kept.
        if !(T.self is AnyClass) { decoded[key] = (ObjectIdentifier(T.self), value) }
        return value
    }

    /// Saves `value` (or removes the key for `nil`).
    public func set<T: Encodable>(_ key: String, _ value: T?) {
        guard let value else {
            remove(key)
            return
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        let json = String(decoding: data, as: UTF8.self)
        guard values[key] != json else { return }
        values[key] = json
        decoded[key] = nil
        if !isScratch { HostClient.shared.fire(.storageSet(key: key, value: json)) }
    }

    public func remove(_ key: String) {
        guard values.removeValue(forKey: key) != nil else { return }
        decoded[key] = nil
        if !isScratch { HostClient.shared.fire(.storageSet(key: key, value: nil)) }
    }

    public var keys: [String] { values.keys.sorted() }
}

/// A property saved by the host, so it survives restarts and updates.
///
/// ```swift
/// @Stored("laps") var laps: [Date] = []
/// ```
@MainActor
@propertyWrapper
public struct Stored<Value: Codable> {
    public let key: String
    private let defaultValue: Value

    public init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    public var wrappedValue: Value {
        get { Stackbar.storage.value(key, as: Value.self) ?? defaultValue }
        nonmutating set { Stackbar.storage.set(key, newValue) }
    }
}
