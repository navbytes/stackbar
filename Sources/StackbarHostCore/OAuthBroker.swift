import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import StackbarProtocol

/// Signs in to OAuth 2.0 providers for plugins and keeps their tokens.
///
/// Authorization code with PKCE (RFC 7636) and a loopback redirect (RFC 8252):
/// the broker opens the provider's sign-in page in the browser, receives the
/// code on `http://127.0.0.1:<port>/callback`, exchanges it, and stores the
/// tokens in the host's secret store under `oauth/<plugin id>/<provider>`. A
/// plugin only ever gets the access token. Expired tokens are refreshed when
/// the provider gave a refresh token, and only one sign-in per provider runs
/// at a time.
public actor OAuthBroker {
    public struct Token: Codable, Equatable, Sendable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?

        func isFresh(at now: Date) -> Bool {
            guard let expiresAt else { return true }
            return expiresAt.timeIntervalSince(now) > 60
        }
    }

    private let secrets: any SecretStore
    private let openURL: @Sendable (URL) -> Void
    private let timeout: Double
    private let session: URLSession
    private var inFlight: [String: Task<Token, Error>] = [:]

    public init(secrets: any SecretStore, timeout: Double = 300, openURL: @escaping @Sendable (URL) -> Void) {
        self.secrets = secrets
        self.openURL = openURL
        self.timeout = timeout
        self.session = URLSession(configuration: .ephemeral)
    }

    public func token(pluginID: String, provider: OAuthProvider, forceRefresh: Bool = false) async throws -> String {
        let key = Self.key(pluginID, provider)
        if let running = inFlight[key] { return try await running.value.accessToken }
        if let stored = try loadToken(key), !forceRefresh, stored.isFresh(at: Date()) {
            return stored.accessToken
        }
        let task = Task { try await self.obtain(key: key, provider: provider) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value.accessToken
    }

    public func signOut(pluginID: String, provider: OAuthProvider) throws {
        try secrets.setSecret(nil, for: Self.key(pluginID, provider))
    }

    public func isSignedIn(pluginID: String, provider: OAuthProvider) -> Bool {
        (try? loadToken(Self.key(pluginID, provider))) != nil
    }

    private func obtain(key: String, provider: OAuthProvider) async throws -> Token {
        if let refreshToken = try loadToken(key)?.refreshToken,
           let refreshed = try? await exchange(provider, ["grant_type": "refresh_token", "refresh_token": refreshToken], keepRefresh: refreshToken) {
            try save(refreshed, key)
            return refreshed
        }
        let token = try await signIn(provider)
        try save(token, key)
        return token
    }

    private func signIn(_ provider: OAuthProvider) async throws -> Token {
        let verifier = Data.random(count: 32).base64URLEncoded
        let challenge = SHA256.hash(Data(verifier.utf8)).base64URLEncoded
        let state = Data.random(count: 16).base64URLEncoded
        let received = CallbackBox()
        let server = try LoopbackServer { request in
            guard request.path == "/callback" else { return .text("not found", status: 404) }
            // Only an answer to this sign-in counts. Anything else that hits
            // the port (another local process, a stale tab) is turned away
            // without ending the wait for the real one.
            guard request.query["state"] == state else {
                return .html(Self.page("Sign-in failed", "This answer is not for the sign-in Stackbar is waiting for."), status: 400)
            }
            received.set(request.query)
            if request.query["error"] != nil {
                return .html(Self.page("Sign-in failed", "You can close this tab and try again from Stackbar."), status: 400)
            }
            return .html(Self.page("Signed in", "You can close this tab and return to Stackbar."))
        }
        defer { server.stop() }
        let redirect = "\(server.baseURL)/callback"
        var query = [
            "response_type": "code", "client_id": provider.clientID, "redirect_uri": redirect,
            "state": state, "code_challenge": challenge, "code_challenge_method": "S256",
        ]
        if !provider.scopes.isEmpty { query["scope"] = provider.scopes.joined(separator: " ") }
        let separator = provider.authorizeURL.contains("?") ? "&" : "?"
        guard let url = URL(string: provider.authorizeURL + separator + Self.form(query)) else {
            throw OAuthError.badProvider(provider.name)
        }
        openURL(url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = received.value {
                if let error = result["error"] { throw OAuthError.denied(result["error_description"] ?? error) }
                guard result["state"] == state, let code = result["code"] else { throw OAuthError.stateMismatch }
                return try await exchange(provider, ["grant_type": "authorization_code", "code": code, "redirect_uri": redirect, "code_verifier": verifier])
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw OAuthError.timedOut(provider.name)
    }

    private func exchange(_ provider: OAuthProvider, _ fields: [String: String], keepRefresh: String? = nil) async throws -> Token {
        guard let url = URL(string: provider.tokenURL) else { throw OAuthError.badProvider(provider.name) }
        var fields = fields
        fields["client_id"] = provider.clientID
        if let secret = provider.clientSecret { fields["client_secret"] = secret }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.form(fields).utf8)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = json["error"] as? String {
            throw OAuthError.denied((json["error_description"] as? String) ?? error)
        }
        guard (200..<300).contains(status), let access = json["access_token"] as? String else {
            throw OAuthError.tokenEndpoint(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let expiresIn = (json["expires_in"] as? Double) ?? (json["expires_in"] as? Int).map(Double.init) ?? (json["expires_in"] as? String).flatMap(Double.init)
        return Token(accessToken: access, refreshToken: (json["refresh_token"] as? String) ?? keepRefresh, expiresAt: expiresIn.map { Date().addingTimeInterval($0) })
    }

    private func loadToken(_ key: String) throws -> Token? {
        guard let json = try secrets.secret(key) else { return nil }
        return try? JSONDecoder().decode(Token.self, from: Data(json.utf8))
    }

    private func save(_ token: Token, _ key: String) throws {
        try secrets.setSecret(String(decoding: try JSONEncoder().encode(token), as: UTF8.self), for: key)
    }

    static func key(_ pluginID: String, _ provider: OAuthProvider) -> String { "oauth/\(pluginID)/\(provider.name)" }

    /// Deletes the tokens a plugin signed in with (when its data is deleted).
    /// Named secrets are shared between plugins, so they stay.
    public static func forgetTokens(of pluginID: String, providers: [OAuthProvider], in secrets: any SecretStore) {
        for provider in providers { try? secrets.setSecret(nil, for: key(pluginID, provider)) }
    }

    static func form(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }.joined(separator: "&")
    }

    static func page(_ title: String, _ message: String) -> String {
        "<!doctype html><meta charset=utf-8><title>\(title)</title><body style=\"font:16px -apple-system,sans-serif;margin:4em auto;max-width:28em;text-align:center\"><h1>\(title)</h1><p>\(message)</p>"
    }

    public enum OAuthError: Error, CustomStringConvertible, Equatable {
        case badProvider(String)
        case denied(String)
        case stateMismatch
        case timedOut(String)
        case tokenEndpoint(Int, String)

        public var description: String {
            switch self {
            case .badProvider(let name): return "the \(name) provider's URLs are invalid"
            case .denied(let reason): return "sign-in was refused: \(reason)"
            case .stateMismatch: return "sign-in answer did not match the request (state mismatch)"
            case .timedOut(let name): return "sign-in to \(name) was not finished in time"
            case .tokenEndpoint(let status, let body): return "token endpoint answered \(status): \(body)"
            }
        }
    }
}

/// The callback's query, handed from the server thread to the waiting task.
final class CallbackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String]?

    func set(_ value: [String: String]) {
        lock.lock()
        if stored == nil { stored = value }
        lock.unlock()
    }

    var value: [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
