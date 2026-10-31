import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import FluidHostCore
import FluidProtocol

final class SHA256Tests: XCTestCase {
    func testStandardVectors() {
        XCTAssertEqual(SHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(SHA256.hex(Data(repeating: 0x61, count: 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func testPKCEChallengeMatchesRFC7636Example() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(SHA256.hash(Data(verifier.utf8)).base64URLEncoded, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}

final class URLPartsTests: XCTestCase {
    func testHostsAndPatterns() {
        XCTAssertEqual(URLParts.host(of: "https://API.github.com/x?y"), "api.github.com")
        XCTAssertEqual(URLParts.host(of: "https://user:pw@example.com:8443/"), "example.com")
        XCTAssertEqual(URLParts.host(of: "http://[::1]:80/"), "::1")
        XCTAssertNil(URLParts.host(of: "not a url"))
        XCTAssertTrue(URLParts.host("api.github.com", matches: ["api.github.com"]))
        XCTAssertTrue(URLParts.host("a.b.example.com", matches: ["*.example.com"]))
        XCTAssertFalse(URLParts.host("example.com", matches: ["*.example.com"]), "a wildcard covers subdomains, not the apex")
        XCTAssertFalse(URLParts.host("evilexample.com", matches: ["*.example.com"]))
        XCTAssertFalse(URLParts.host("api.github.com.evil.io", matches: ["api.github.com"]))
    }

    func testManifestProblems() {
        XCTAssertEqual(Manifest(id: "dev.example.ok", name: "OK").problems, [])
        XCTAssertFalse(Manifest(id: "nodots", name: "x").problems.isEmpty)
        XCTAssertFalse(Manifest(id: "a.b", name: " ").problems.isEmpty)
        XCTAssertFalse(Manifest(id: "a.b", name: "x", capabilities: [.network("https://api.github.com")]).problems.isEmpty)
        XCTAssertEqual(Manifest(id: "a.b", name: "x", capabilities: [.secret(name: "GITHUB_TOKEN"), .secret(name: "api-key.v2")]).problems, [])
        // OAuth tokens live in the same store under oauth/<plugin>/<provider>.
        XCTAssertFalse(Manifest(id: "a.b", name: "x", capabilities: [.secret(name: "oauth/dev.other/github")]).problems.isEmpty)
        XCTAssertFalse(Manifest(id: "a.b", name: "x", capabilities: [.secret(name: "")]).problems.isEmpty)
    }

    func testASecretNameCannotReachAnotherPluginsOAuthToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = MemorySecretStore(["oauth/dev.victim/github": #"{"accessToken":"stolen"}"#])
        let services = HostServices.local(directory: directory, secrets: secrets)
        let thief = Manifest(id: "dev.thief", name: "Thief", capabilities: [.secret(name: "oauth/dev.victim/github")])
        let result = await services.handle(.secret(name: "oauth/dev.victim/github"), for: thief)
        guard case .failure = result else { return XCTFail("read another plugin's token: \(result)") }
    }
}

final class StorageStoreTests: XCTestCase {
    func testPersistsPerPluginAndEnforcesQuota() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StorageStore(directory: directory, quotaBytes: 64)
        try await store.set("a", "1", for: "p.one")
        try await store.set("b", "\"x\"", for: "p.one")
        try await store.set("a", nil, for: "p.one")
        let reopened = StorageStore(directory: directory, quotaBytes: 64)
        let snapshot = await reopened.snapshot(for: "p.one")
        XCTAssertEqual(snapshot, ["b": "\"x\""])
        let other = await reopened.snapshot(for: "p.two")
        XCTAssertEqual(other, [:])
        do {
            try await reopened.set("big", String(repeating: "x", count: 100), for: "p.one")
            XCTFail("over quota must throw")
        } catch {}
        let unchanged = await reopened.snapshot(for: "p.one")
        XCTAssertEqual(unchanged, ["b": "\"x\""])
    }

    func testIDsThatLookAlikeGetTheirOwnFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Both ids sanitize to dev-a-b-c.
        XCTAssertNotEqual(PluginBuilder.dataFileName("dev.a-b.c"), PluginBuilder.dataFileName("dev-a.b.c"))
        XCTAssertNotEqual(PluginBuilder.dataFileName("a_b.c"), PluginBuilder.dataFileName("a_5F.c"))
        XCTAssertEqual(PluginBuilder.dataFileName("dev.fluid.clock"), "dev.fluid.clock")
        XCTAssertFalse(PluginBuilder.dataFileName("../x").contains("/"))
        XCTAssertFalse(PluginBuilder.dataFileName("..").hasPrefix("."))
        let store = StorageStore(directory: directory)
        try await store.set("token", "\"mine\"", for: "dev.a-b.c")
        let other = await StorageStore(directory: directory).snapshot(for: "dev-a.b.c")
        XCTAssertEqual(other, [:])
    }

    func testReadsValuesSavedUnderTheOldFileName() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"count":"3"}"#.utf8).write(to: directory.appendingPathComponent("dev-fluid-clock.json"))
        let store = StorageStore(directory: directory)
        let migrated = await store.snapshot(for: "dev.fluid.clock")
        XCTAssertEqual(migrated, ["count": "3"])
        try await store.set("count", "4", for: "dev.fluid.clock")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("dev-fluid-clock.json").path))
        let reopened = await StorageStore(directory: directory).snapshot(for: "dev.fluid.clock")
        XCTAssertEqual(reopened, ["count": "4"])
    }
}

final class PluginBusTests: XCTestCase {
    func testDeliversToListenersButNotTheSender() async throws {
        let bus = PluginBus()
        let received = Log()
        await bus.subscribe("a", to: ["t"]) { topic, payload, from in received.add(.log(.info, "a \(topic) \(payload) \(from)")) }
        await bus.subscribe("b", to: ["t", "u"]) { topic, payload, from in received.add(.log(.info, "b \(topic) \(payload) \(from)")) }
        let count = try await bus.publish("t", payload: "hi", from: "a")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(received.all, ["b t hi a"])
        await bus.unsubscribe("b")
        let none = try await bus.publish("t", payload: "again", from: "a")
        XCTAssertEqual(none, 0)
        do {
            try await bus.publish("t", payload: String(repeating: "x", count: PluginBus.maxPayloadBytes + 1), from: "a")
            XCTFail("oversized payloads are refused")
        } catch {}
    }
}

final class HostServicesTests: XCTestCase {
    var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCapabilitiesAreEnforced() async throws {
        let missing = Log()
        let opened = Log()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore(["TOKEN": "t0k"]), platform: .init(open: { opened.add(.log(.info, $0.absoluteString)) }, secretMissing: { id, name in missing.add(.log(.info, "\(id) \(name)")) }))
        let manifest = Manifest(id: "dev.test.p", name: "P", capabilities: [.secret(name: "TOKEN"), .secret(name: "UNSET"), .network("api.example.com")])

        let token = await services.handle(.secret(name: "TOKEN"), for: manifest)
        XCTAssertEqual(token, .value("t0k"))
        let unset = await services.handle(.secret(name: "UNSET"), for: manifest)
        XCTAssertEqual(unset, .value(nil))
        XCTAssertEqual(missing.all, ["dev.test.p UNSET"], "a declared but missing secret asks the user")
        guard case .failure(let message) = await services.handle(.secret(name: "OTHER"), for: manifest) else { return XCTFail("undeclared secrets are refused") }
        XCTAssertTrue(message.contains(".secret(name: \"OTHER\")"), "the error names the capability to add: \(message)")

        guard case .failure(let http) = await services.handle(.http(HTTPRequest(url: "https://evil.example.org/")), for: manifest) else { return XCTFail("undeclared hosts are refused") }
        XCTAssertTrue(http.contains("evil.example.org"))
        XCTAssertEqual(services.audit.report(for: manifest).undeclared, ["evil.example.org"])

        guard case .failure = await services.handle(.oauthToken(provider: "github", forceRefresh: false), for: manifest) else { return XCTFail("undeclared providers are refused") }
        guard case .failure = await services.handle(.openURL("file:///etc/passwd"), for: manifest) else { return XCTFail("file URLs are not opened") }
        let open = await services.handle(.openURL("https://example.com"), for: manifest)
        XCTAssertEqual(open, .ok)
        XCTAssertEqual(opened.all, ["https://example.com"])

        for _ in 0..<10 {
            let ok = await services.handle(.notify(title: "hi", body: nil), for: manifest)
            XCTAssertEqual(ok, .ok)
        }
        guard case .failure = await services.handle(.notify(title: "spam", body: nil), for: manifest) else { return XCTFail("notifications are rate limited") }
    }

    func testHTTPGoesOnlyToDeclaredHostsAndRedirectsStayInside() async throws {
        let server = try LoopbackServer { request in
            switch request.path {
            case "/hello": return .text("hello \(request.query["name"] ?? "")")
            case "/away": return LoopbackServer.Response(status: 302, body: Data())
            default: return .text("missing", status: 404)
            }
        }
        defer { server.stop() }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore())
        let manifest = Manifest(id: "dev.test.p", name: "P", capabilities: [.network("127.0.0.1")])
        let result = await services.handle(.http(HTTPRequest(url: "\(server.baseURL)/hello?name=fluid")), for: manifest)
        guard case .http(let response) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "hello fluid")
        XCTAssertEqual(services.audit.entries(for: "dev.test.p").map(\.host), ["127.0.0.1"])

        let wrongHost = await services.handle(.http(HTTPRequest(url: "http://localhost:\(server.port)/hello")), for: manifest)
        guard case .failure = wrongHost else { return XCTFail("localhost is not 127.0.0.1") }
    }

    func testOAuthIgnoresACallbackForAnotherSignIn() async throws {
        let tokenServer = try LoopbackServer { request in
            request.form["code"] == "real" ? .json(#"{"access_token":"ok"}"#) : .json(#"{"error":"invalid_grant"}"#, status: 400)
        }
        defer { tokenServer.stop() }
        // Something else hits the callback first with a wrong state; the real
        // answer that follows must still sign in.
        let browser: @Sendable (URL) -> Void = { url in
            let query = LoopbackServer.parseQuery(url.query ?? "")
            guard let redirect = query["redirect_uri"], let state = query["state"] else { return }
            Task.detached {
                _ = try? await URLSession.shared.data(from: URL(string: "\(redirect)?code=forged&state=wrong")!)
                _ = try? await URLSession.shared.data(from: URL(string: "\(redirect)?code=real&state=\(state)")!)
            }
        }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore(), platform: .init(open: browser))
        let provider = OAuthProvider(name: "test", authorizeURL: "http://127.0.0.1:1/authorize", tokenURL: "\(tokenServer.baseURL)/token", clientID: "client")
        let manifest = Manifest(id: "dev.test.p", name: "P", capabilities: [.oauth(provider)])
        let token = await services.handle(.oauthToken(provider: "test", forceRefresh: false), for: manifest)
        XCTAssertEqual(token, .value("ok"))
    }

    func testOAuthSignsInWithPKCEThenRefreshes() async throws {
        let issued = Log()
        let challenge = ChallengeBox()
        let tokenServer = try LoopbackServer { request in
            let form = request.form
            switch form["grant_type"] {
            case "authorization_code":
                guard form["code"] == "the-code", let verifier = form["code_verifier"],
                      SHA256.hash(Data(verifier.utf8)).base64URLEncoded == challenge.value else {
                    return .json(#"{"error":"invalid_grant"}"#, status: 400)
                }
                issued.add(.log(.info, "code"))
                return .json(#"{"access_token":"first","refresh_token":"r1","expires_in":0}"#)
            case "refresh_token":
                guard form["refresh_token"] == "r1" else { return .json(#"{"error":"invalid_grant"}"#, status: 400) }
                issued.add(.log(.info, "refresh"))
                return .json(#"{"access_token":"second","expires_in":3600}"#)
            default:
                return .json(#"{"error":"unsupported_grant_type"}"#, status: 400)
            }
        }
        defer { tokenServer.stop() }

        // Plays the browser: reads the authorize URL and calls the redirect.
        let browser: @Sendable (URL) -> Void = { url in
            let query = LoopbackServer.parseQuery(url.query ?? "")
            challenge.value = query["code_challenge"]
            guard let redirect = query["redirect_uri"], let state = query["state"], query["code_challenge_method"] == "S256" else { return }
            Task.detached { _ = try? await URLSession.shared.data(from: URL(string: "\(redirect)?code=the-code&state=\(state)")!) }
        }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore(), platform: .init(open: browser))
        let provider = OAuthProvider(name: "test", authorizeURL: "http://127.0.0.1:1/authorize", tokenURL: "\(tokenServer.baseURL)/token", clientID: "client", scopes: ["read"])
        let manifest = Manifest(id: "dev.test.p", name: "P", capabilities: [.oauth(provider)])

        let first = await services.handle(.oauthToken(provider: "test", forceRefresh: false), for: manifest)
        XCTAssertEqual(first, .value("first"))
        let second = await services.handle(.oauthToken(provider: "test", forceRefresh: false), for: manifest)
        XCTAssertEqual(second, .value("second"), "an expired token is refreshed without a new sign-in")
        let third = await services.handle(.oauthToken(provider: "test", forceRefresh: false), for: manifest)
        XCTAssertEqual(third, .value("second"), "a fresh token is reused")
        XCTAssertEqual(issued.all, ["code", "refresh"])
    }
}

final class ChallengeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class HardeningTests: XCTestCase {
    func testHostLogRollsOverAndTails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = HostLog(file: directory.appendingPathComponent("Logs/fluid.log"), maxBytes: 400)
        for index in 0..<20 { log.write(.info, "entry \(index)\nsecond line", plugin: "dev.test") }
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: log.file.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, 400)
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.rolledFile.path))
        let tail = log.tail(3)
        XCTAssertEqual(tail.count, 3)
        XCTAssertTrue(tail[2].hasSuffix("INFO [dev.test] entry 19\\nsecond line"), tail[2])
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: log.file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode, 0o600)
    }

    func testLogBudgetDropsThenSummarises() {
        var budget = LogBudget()
        let start = Date()
        for _ in 0..<LogBudget.limit { XCTAssertEqual(budget.take(now: start), .allow(suppressed: 0)) }
        XCTAssertEqual(budget.take(now: start), .drop)
        XCTAssertEqual(budget.take(now: start), .drop)
        XCTAssertEqual(budget.take(now: start.addingTimeInterval(LogBudget.window)), .allow(suppressed: 2))
        XCTAssertEqual(budget.take(now: start.addingTimeInterval(LogBudget.window)), .allow(suppressed: 0))
    }

    func testRateLimiterSlides() {
        let limiter = RateLimiter(limit: 2, per: 10)
        let start = Date()
        XCTAssertTrue(limiter.allow("a", now: start))
        XCTAssertTrue(limiter.allow("a", now: start))
        XCTAssertFalse(limiter.allow("a", now: start.addingTimeInterval(5)))
        XCTAssertTrue(limiter.allow("b", now: start), "limits are per plugin")
        XCTAssertTrue(limiter.allow("a", now: start.addingTimeInterval(10.1)))
    }
}
