import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import StackbarProtocol

/// Makes HTTP requests for plugins, only to the domains they declared.
///
/// Redirects are followed only while they stay on declared domains, response
/// bodies are capped, and every attempt is recorded in the `NetworkAudit`.
/// Requests carry a private `X-Stackbar-Request` header so the redirect check can
/// tell which plugin's request is being redirected.
public final class HTTPService: Sendable {
    public static let maxResponseBytes = 16 * 1024 * 1024

    public let audit: NetworkAudit
    private let session: URLSession
    private let redirectPolicy = RedirectPolicy()

    public init(audit: NetworkAudit, configuration: URLSessionConfiguration = .ephemeral) {
        self.audit = audit
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "Stackbar"]
        let policy = redirectPolicy
        self.session = URLSession(configuration: configuration, delegate: RedirectDelegate(policy: policy), delegateQueue: nil)
    }

    /// Performs `request` if its host is covered by `allowedHosts`.
    public func perform(_ request: HTTPRequest, pluginID: String, allowedHosts: [String]) async -> HostResult {
        guard let url = URL(string: request.url), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = URLParts.host(of: request.url) else {
            return .failure("\(request.url) is not an http(s) URL")
        }
        guard URLParts.host(host, matches: allowedHosts) else {
            audit.record(pluginID: pluginID, host: host, allowed: false)
            return .failure("\(host) is not declared; add .network(\"\(host)\") to the manifest's capabilities")
        }
        if scheme == "http" && !Self.isLoopback(host) {
            return .failure("plain http is only allowed to 127.0.0.1 and localhost; use https://\(host)")
        }
        audit.record(pluginID: pluginID, host: host, allowed: true)
        var urlRequest = URLRequest(url: url, timeoutInterval: min(max(request.timeout, 1), 120))
        urlRequest.httpMethod = request.method.uppercased()
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        let taskID = redirectPolicy.register(allowedHosts: allowedHosts)
        urlRequest.setValue(taskID, forHTTPHeaderField: RedirectPolicy.header)
        defer { redirectPolicy.unregister(taskID) }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { return .failure("no HTTP response from \(host)") }
            if data.count > Self.maxResponseBytes {
                return .failure("response from \(host) is \(data.count) bytes; the limit is \(Self.maxResponseBytes)")
            }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
            }
            return .http(HTTPResponse(status: http.statusCode, headers: headers, body: data))
        } catch {
            if let blocked = redirectPolicy.blockedHost(taskID) {
                audit.record(pluginID: pluginID, host: blocked, allowed: false)
                return .failure("\(host) redirected to \(blocked), which is not declared")
            }
            return .failure("\(request.method) \(request.url) failed: \(error.localizedDescription)")
        }
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

/// Which hosts each in-flight request may be redirected to. Requests are
/// matched by a private header the delegate can see on the original request.
final class RedirectPolicy: @unchecked Sendable {
    static let header = "X-Stackbar-Request"
    private let lock = NSLock()
    private var allowed: [String: [String]] = [:]
    private var blocked: [String: String] = [:]
    private var next = 0

    func register(allowedHosts: [String]) -> String {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        let id = String(next)
        allowed[id] = allowedHosts
        return id
    }

    func unregister(_ id: String) {
        lock.lock()
        allowed[id] = nil
        blocked[id] = nil
        lock.unlock()
    }

    func allows(_ id: String, host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let hosts = allowed[id] else { return false }
        if URLParts.host(host, matches: hosts) { return true }
        blocked[id] = host
        return false
    }

    func blockedHost(_ id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return blocked[id]
    }
}

final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let policy: RedirectPolicy

    init(policy: RedirectPolicy) { self.policy = policy }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A redirect may not downgrade to plain http, which the first request
        // could not have used either (except to loopback).
        let scheme = request.url?.scheme?.lowercased()
        guard let id = task.originalRequest?.value(forHTTPHeaderField: RedirectPolicy.header), let host = request.url?.host?.lowercased(),
              scheme == "https" || (scheme == "http" && HTTPService.isLoopback(host)), policy.allows(id, host: host) else {
            task.cancel()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
