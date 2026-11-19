import Foundation

/// Stale-while-revalidate for plugins, as Raycast's `useCachedPromise`
/// does it: show what you have at once, fetch fresh behind it, and draw
/// again when it lands. Plugins stay running, so the cache is memory.
extension Stackbar {
    /// Whether the plugin is fetching behind what its views show: inside
    /// `updating`, or a `cached` value reloading. Open palette views carry
    /// it, so the palette keeps its loading bar over their rows (Stackbar
    /// 0.41.0 and later; older hosts ignore it).
    @MainActor public static var isUpdating: Bool { CacheStore.shared.updates > 0 }

    /// Runs `body` with the palette's loading bar showing over the plugin's
    /// open views, and draws when it starts and ends. Wrap a fetch your own
    /// `Task` runs behind a view:
    ///
    ///     Task { try? await Stackbar.updating { try await Stackbar.refresh() } }
    @MainActor @discardableResult
    public static func updating<T>(_ body: @MainActor () async throws -> T) async rethrows -> T {
        let store = CacheStore.shared
        store.updates += 1
        if store.updates == 1 { redraw() }
        defer {
            store.updates -= 1
            redraw()
        }
        return try await body()
    }

    /// Runs `fetch` only when `key` has no value yet; returns the value.
    /// When the value is older than `maxAge`, it is returned at once and
    /// `fetch` runs again in the background (one at a time per key, with
    /// the palette's loading bar showing), and the views draw again when it
    /// lands. Use it in a view's `search`, so only the first open waits. The
    /// simplest `fetch` stores into your own properties, which `body` reads:
    ///
    ///     .view(search: { _ in
    ///         try await Stackbar.cached("containers", maxAge: 5) { self.containers = try await self.listContainers() }
    ///     })
    ///
    /// A first fetch that fails throws. A background one that fails keeps
    /// the old value; `cacheError(key)` says why until a fetch succeeds.
    @MainActor @discardableResult
    public static func cached<Value>(_ key: String, maxAge: TimeInterval,
                                     fetch: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try await CacheStore.shared.value(key, maxAge: maxAge, fetch: fetch)
    }

    /// The value `cached` holds for `key`, without fetching.
    @MainActor public static func cachedValue<Value>(_ key: String, as type: Value.Type = Value.self) -> Value? {
        CacheStore.shared.entries[key]?.value as? Value
    }

    /// Why the last background fetch of `key` failed; nil once one succeeds.
    @MainActor public static func cacheError(_ key: String) -> (any Error)? {
        CacheStore.shared.errors[key]
    }

    /// Forgets `key` (or everything), so the next `cached` call waits for a
    /// fresh fetch: after a setting or the account changed.
    @MainActor public static func invalidateCache(_ key: String? = nil) {
        CacheStore.shared.invalidate(key)
    }
}

/// Carries a fetched value out of its task; it is only read on the main actor.
final class CacheBox: @unchecked Sendable {
    let value: Any
    init(_ value: Any) { self.value = value }
}

@MainActor
final class CacheStore {
    static let shared = CacheStore()

    struct Entry {
        var value: Any
        var fetchedAt: Date
    }

    var entries: [String: Entry] = [:]
    var errors: [String: any Error] = [:]
    var updates = 0
    /// Fetches running, by key, so callers share one.
    private var fetching: [String: (id: Int, task: Task<CacheBox, any Error>)] = [:]
    private var nextID = 0
    /// Moved forward by `invalidate`, so a fetch that started before it
    /// doesn't store an answer for the old setting.
    private var generations: [String: Int] = [:]
    private var generation = 0
    private func stamp(_ key: String) -> [Int] { [generation, generations[key, default: 0]] }

    func value<Value>(_ key: String, maxAge: TimeInterval, fetch: @escaping @MainActor () async throws -> Value) async throws -> Value {
        if let entry = entries[key], let value = entry.value as? Value {
            if Date().timeIntervalSince(entry.fetchedAt) >= maxAge, fetching[key] == nil {
                let task = start(key, fetch: fetch)
                Task { @MainActor in _ = await Stackbar.updating { try? await task.value } }
            }
            return value
        }
        let task = fetching[key]?.task ?? start(key, fetch: fetch)
        guard let value = try await task.value.value as? Value else {
            throw HostError("the value cached as \(key) is not a \(Value.self)")
        }
        return value
    }

    private func start<Value>(_ key: String, fetch: @escaping @MainActor () async throws -> Value) -> Task<CacheBox, any Error> {
        nextID += 1
        let id = nextID
        let stamp = stamp(key)
        let task = Task { @MainActor () throws -> CacheBox in
            defer { if self.fetching[key]?.id == id { self.fetching[key] = nil } }
            do {
                let value = try await fetch()
                if stamp == self.stamp(key) {
                    self.entries[key] = Entry(value: value, fetchedAt: Date())
                    self.errors[key] = nil
                }
                return CacheBox(value)
            } catch {
                if stamp == self.stamp(key), self.entries[key] != nil { self.errors[key] = error }
                throw error
            }
        }
        fetching[key] = (id, task)
        return task
    }

    func invalidate(_ key: String?) {
        if let key {
            generations[key, default: 0] += 1
            entries[key] = nil
            errors[key] = nil
            fetching[key]?.task.cancel()
            fetching[key] = nil
        } else {
            generation += 1
            entries = [:]
            errors = [:]
            for running in fetching.values { running.task.cancel() }
            fetching = [:]
        }
    }
}
