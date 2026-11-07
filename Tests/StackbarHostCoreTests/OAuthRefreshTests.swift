import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class OAuthRefreshTests: XCTestCase {
    private func expiredToken(_ secrets: MemorySecretStore, provider: OAuthProvider) throws {
        let token = OAuthBroker.Token(accessToken: "old", refreshToken: "r1", expiresAt: Date(timeIntervalSinceNow: -100))
        secrets.setSecret(String(decoding: try JSONEncoder().encode(token), as: UTF8.self), for: OAuthBroker.key("dev.test.p", provider))
    }

    func testARefreshFailureThatIsNotInvalidGrantDoesNotOpenTheBrowser() async throws {
        let server = try LoopbackServer { _ in .text("down", status: 503) }
        defer { server.stop() }
        let secrets = MemorySecretStore()
        let provider = OAuthProvider(name: "test", authorizeURL: "http://127.0.0.1:1/authorize", tokenURL: "\(server.baseURL)/token", clientID: "c")
        try expiredToken(secrets, provider: provider)
        let opened = Log()
        let broker = OAuthBroker(secrets: secrets, timeout: 1) { _ in opened.add(.log(.info, "opened")) }
        do {
            _ = try await broker.token(pluginID: "dev.test.p", provider: provider)
            XCTFail("a 503 on refresh is an error")
        } catch let error as OAuthBroker.OAuthError {
            guard case .tokenEndpoint(503, _) = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(opened.all.count, 0)
    }

    func testInvalidGrantOnRefreshFallsBackToSignIn() async throws {
        let server = try LoopbackServer { _ in .json(#"{"error":"invalid_grant"}"#, status: 400) }
        defer { server.stop() }
        let secrets = MemorySecretStore()
        let provider = OAuthProvider(name: "test", authorizeURL: "http://127.0.0.1:1/authorize", tokenURL: "\(server.baseURL)/token", clientID: "c")
        try expiredToken(secrets, provider: provider)
        let opened = Log()
        let broker = OAuthBroker(secrets: secrets, timeout: 0.3) { _ in opened.add(.log(.info, "opened")) }
        do {
            _ = try await broker.token(pluginID: "dev.test.p", provider: provider)
            XCTFail("nobody answers the sign-in")
        } catch let error as OAuthBroker.OAuthError {
            XCTAssertEqual(error, .timedOut("test"))
        }
        XCTAssertEqual(opened.all.count, 1)
    }

    func testForgettingTokensReportsWhatTheKeychainRefused() {
        struct Refusing: SecretStore {
            func secret(_ name: String) throws -> String? { nil }
            func setSecret(_ value: String?, for name: String) throws { throw CocoaError(.fileWriteNoPermission) }
        }
        let provider = OAuthProvider(name: "test", authorizeURL: "http://x", tokenURL: "http://x", clientID: "c")
        XCTAssertEqual(OAuthBroker.forgetTokens(of: "dev.test.p", providers: [provider], in: Refusing()), ["test"])
    }
}
