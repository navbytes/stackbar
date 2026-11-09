import Foundation

/// Tokens for private stores: a source added with `#auth=<SECRET_NAME>`
/// sends its secret as a bearer token, but only to its own host and only
/// under its index's folder, so a bundle URL that points elsewhere never
/// gets it.
public final class StoreAuth: @unchecked Sendable {
    public static let shared = StoreAuth()

    private let lock = NSLock()
    /// Index URL → token.
    private var tokens: [URL: String] = [:]

    public init() {}

    /// Replaces every token (sources were read again).
    public func set(_ tokens: [URL: String]) {
        lock.withLock { self.tokens = tokens }
    }

    /// The `Authorization` header for `url`: a store's token when `url` is
    /// on that store's host (same scheme and port) under its index's folder.
    public func authorization(for url: URL) -> String? {
        guard url.scheme == "https" else { return nil }
        let known = lock.withLock { tokens }
        for (index, token) in known where Self.covers(index, url) {
            return "Bearer \(token)"
        }
        return nil
    }

    static func covers(_ index: URL, _ url: URL) -> Bool {
        guard index.scheme == url.scheme, index.host == url.host, index.port == url.port else { return false }
        let folder = index.deletingLastPathComponent().path
        let base = folder.hasSuffix("/") ? folder : folder + "/"
        return url.path == index.path || url.path.hasPrefix(base)
    }
}
