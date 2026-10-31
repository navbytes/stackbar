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

    init() {}

    /// Replaces the local copy with the host's snapshot.
    public func load(_ snapshot: [String: String]) {
        values = snapshot
    }

    public func value<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let json = values[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
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
        HostClient.shared.fire(.storageSet(key: key, value: json))
    }

    public func remove(_ key: String) {
        guard values.removeValue(forKey: key) != nil else { return }
        HostClient.shared.fire(.storageSet(key: key, value: nil))
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
        get { Fluid.storage.value(key, as: Value.self) ?? defaultValue }
        nonmutating set { Fluid.storage.set(key, newValue) }
    }
}
