import Foundation
import XCTest
@testable import StackbarKit

/// Answers `Stackbar.*` calls straight away: secrets from a table, HTTP with
/// a fixed JSON reply, keeping each request to check what was sent.
final class FakeHost: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [HTTPRequest] = []
    let secrets: [String: String]
    let reply: Data

    init(secrets: [String: String], reply: String = #"{"ok":true}"#) {
        self.secrets = secrets
        self.reply = Data(reply.utf8)
        HostClient.shared.configure { [self] message in
            guard case .request(let id, let call) = message else { return }
            switch call {
            case .secret(let name):
                HostClient.shared.resolve(id: id, result: .value(self.secrets[name]))
            case .http(let request):
                lock.withLock { sent.append(request) }
                HostClient.shared.resolve(id: id, result: .http(HTTPResponse(status: 200, body: self.reply)))
            default:
                HostClient.shared.resolve(id: id, result: .failure("unexpected \(call)"))
            }
        }
    }

    var requests: [HTTPRequest] { lock.withLock { sent } }
}

final class AuthTests: XCTestCase {
    struct Reply: Decodable, Equatable { let ok: Bool }

    func testEachAuthKindBuildsItsHeader() async throws {
        let host = FakeHost(secrets: ["GITHUB_TOKEN": "ghp", "LINEAR_API_KEY": "lin", "DEEPL_API_KEY": "dl:fx"])
        _ = try await Stackbar.getJSON("https://api.github.com/user", as: Reply.self, auth: .bearer(secret: "GITHUB_TOKEN"))
        _ = try await Stackbar.getJSON("https://api.linear.app/x", as: Reply.self, auth: .header("Authorization", secret: "LINEAR_API_KEY"))
        _ = try await Stackbar.get("https://api-free.deepl.com/v2/usage", auth: .header("Authorization", secret: "DEEPL_API_KEY", prefix: "DeepL-Auth-Key"))
        XCTAssertEqual(host.requests.map { $0.headers["Authorization"] }, ["Bearer ghp", "lin", "DeepL-Auth-Key dl:fx"])
        XCTAssertEqual(host.requests[0].headers["Accept"], "application/json")
    }

    func testAMissingOrEmptySecretThrowsBeforeAnyRequest() async {
        let host = FakeHost(secrets: ["EMPTY": ""])
        for name in ["UNSET", "EMPTY"] {
            do {
                _ = try await Stackbar.getJSON("https://example.com", as: Reply.self, auth: .bearer(secret: name))
                XCTFail("\(name) should throw")
            } catch {
                XCTAssertEqual(error as? StackbarError, .missingSecret(name))
            }
        }
        XCTAssertTrue(host.requests.isEmpty)
    }

    func testPostJSONEncodesTheBody() async throws {
        struct Query: Encodable { let query: String }
        let host = FakeHost(secrets: ["LINEAR_API_KEY": "lin"])
        let reply = try await Stackbar.postJSON("https://api.linear.app/graphql", body: Query(query: "{ viewer { id } }"), as: Reply.self, auth: .header("Authorization", secret: "LINEAR_API_KEY"))
        XCTAssertEqual(reply, Reply(ok: true))
        let request = try XCTUnwrap(host.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), #"{"query":"{ viewer { id } }"}"#)
    }

    @MainActor func testAMissingSecretShowsAsAWaitingStateNotAFailure() {
        let context = RenderContext()
        XCTAssertEqual(ContentUnavailableView(StackbarError.missingSecret("GITHUB_TOKEN")).resolve(in: context), [
            .empty(title: "Waiting for GITHUB_TOKEN", symbol: "key", message: "Enter it in the prompt above. Stackbar keeps it in your Keychain."),
        ])
        XCTAssertEqual(ContentUnavailableView(HostError("offline")).resolve(in: context), [
            .empty(title: "Couldn't refresh", symbol: "exclamationmark.triangle", message: "offline"),
        ])
    }
}
