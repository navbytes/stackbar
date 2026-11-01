import Foundation
import StackbarProtocol

/// Fetches and keeps the remote images (`ImageSource.url`) plugins draw.
///
/// A plugin process never draws, so it can't fetch a picture for itself and
/// hand over the pixels; the host does it, through the same `HTTPService`
/// (and so the same declared-domain check and network audit) as a plugin's
/// own requests. Only https, only images, at most
/// `RemoteImageLimits.maxBytes` each and `RemoteImageLimits.maxPerTree` a
/// tree. Kept in memory, the oldest dropped past `capacity`; a failed URL is
/// not tried again for `retryAfter` seconds.
public final class RemoteImageStore: @unchecked Sendable {
    public static let capacity = 400
    public static let retryAfter: TimeInterval = 300

    private let http: HTTPService
    private let lock = NSLock()
    private var images: [String: Data] = [:]
    private var order: [String] = []
    private var failed: [String: Date] = [:]
    private var loading: Set<String> = []

    public init(http: HTTPService) { self.http = http }

    /// The image's bytes when they've been fetched.
    public func data(for url: String) -> Data? {
        lock.withLock { images[url] }
    }

    /// Fetches the images `tree` names that aren't kept yet, for the plugin
    /// `pluginID`, from `allowedHosts`. Returns the URLs that newly loaded.
    @discardableResult
    public func load(_ tree: ViewNode, pluginID: String, allowedHosts: [String], now: Date = Date()) async -> [String] {
        await load(Array(tree.imageURLs.prefix(RemoteImageLimits.maxPerTree)), pluginID: pluginID, allowedHosts: allowedHosts, now: now)
    }

    @discardableResult
    public func load(_ urls: [String], pluginID: String, allowedHosts: [String], now: Date = Date()) async -> [String] {
        let wanted: [String] = lock.withLock {
            let fresh = urls.filter { url in
                images[url] == nil && !loading.contains(url) && (failed[url].map { now.timeIntervalSince($0) >= Self.retryAfter } ?? true)
            }
            loading.formUnion(fresh)
            return fresh
        }
        guard !wanted.isEmpty else { return [] }
        let results = await withTaskGroup(of: (String, Data?).self) { group in
            for url in wanted {
                group.addTask { (url, await self.fetch(url, pluginID: pluginID, allowedHosts: allowedHosts)) }
            }
            var collected: [(String, Data?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        return lock.withLock {
            var loaded: [String] = []
            for (url, data) in results {
                loading.remove(url)
                if let data {
                    store(url, data)
                    loaded.append(url)
                } else {
                    failed[url] = now
                }
            }
            return urls.filter(loaded.contains)
        }
    }

    /// Keeps `data` for `url` without fetching: for tests and previews.
    public func insert(_ data: Data, for url: String) {
        lock.withLock { store(url, data) }
    }

    /// Call with the lock held.
    private func store(_ url: String, _ data: Data) {
        if images.updateValue(data, forKey: url) == nil { order.append(url) }
        failed[url] = nil
        while order.count > Self.capacity {
            images[order.removeFirst()] = nil
        }
    }

    private func fetch(_ url: String, pluginID: String, allowedHosts: [String]) async -> Data? {
        guard Self.isFetchable(url) else { return nil }
        let result = await http.perform(HTTPRequest(url: url, headers: ["Accept": "image/*"], timeout: 20), pluginID: pluginID, allowedHosts: allowedHosts)
        guard case .http(let response) = result, (200..<300).contains(response.status),
              !response.body.isEmpty, response.body.count <= RemoteImageLimits.maxBytes,
              Self.isImage(contentType: response.headers["content-type"], body: response.body) else { return nil }
        return response.body
    }

    /// An https URL with a host.
    public static func isFetchable(_ url: String) -> Bool {
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host?.isEmpty == false else { return false }
        return true
    }

    /// An image by its declared type, or, when the server says nothing
    /// useful, by its first bytes (PNG, JPEG, GIF, WebP, ICO, HEIC).
    static func isImage(contentType: String?, body: Data) -> Bool {
        if let type = contentType?.lowercased() {
            if type.hasPrefix("image/") { return true }
            if !type.hasPrefix("application/octet-stream") && !type.hasPrefix("binary/") { return false }
        }
        let head = [UInt8](body.prefix(12))
        let signatures: [[UInt8]] = [[0x89, 0x50, 0x4E, 0x47], [0xFF, 0xD8, 0xFF], [0x47, 0x49, 0x46], [0x00, 0x00, 0x01, 0x00]]
        if signatures.contains(where: { head.starts(with: $0) }) { return true }
        if head.count >= 12, head[0..<4] == [0x52, 0x49, 0x46, 0x46], head[8..<12] == [0x57, 0x45, 0x42, 0x50] { return true }
        return head.count >= 12 && head[4..<8] == [0x66, 0x74, 0x79, 0x70]
    }
}
