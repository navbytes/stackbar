import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class HTTPServiceTests: XCTestCase {
    func testABodyOverTheCapIsRefusedWithoutBeingReturned() async throws {
        let big = Data(repeating: 0x61, count: HTTPService.maxResponseBytes + 1024)
        let server = try LoopbackServer { request in
            request.path == "/big" ? LoopbackServer.Response(body: big) : .text("small")
        }
        defer { server.stop() }
        let service = HTTPService(audit: NetworkAudit())
        let refused = await service.perform(HTTPRequest(url: "\(server.baseURL)/big"), pluginID: "dev.test.p", allowedHosts: ["127.0.0.1"])
        guard case .failure(let message) = refused else { return XCTFail("\(refused)") }
        XCTAssertTrue(message.contains("larger than the limit"), message)

        let fine = await service.perform(HTTPRequest(url: "\(server.baseURL)/small"), pluginID: "dev.test.p", allowedHosts: ["127.0.0.1"])
        guard case .http(let response) = fine else { return XCTFail("\(fine)") }
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "small")
    }

    func testDownloadsStopAtTheirLimit() async throws {
        let server = try LoopbackServer { _ in LoopbackServer.Response(body: Data(repeating: 0x61, count: 5000)) }
        defer { server.stop() }
        let url = try XCTUnwrap(URL(string: "\(server.baseURL)/x"))
        let ok = try await PluginIndex.download(url, limit: 6000)
        XCTAssertEqual(ok.count, 5000)
        do {
            _ = try await PluginIndex.download(url, limit: 1000)
            XCTFail("over the limit")
        } catch let error as PluginIndex.IndexError {
            XCTAssertEqual(error, .tooLarge(url.absoluteString))
        }
    }
}

final class NetworkAuditTests: XCTestCase {
    func testTheHostListIsBoundedAndKeepsHostsThatWereUsed() {
        let audit = NetworkAudit()
        audit.record(pluginID: "p", host: "api.example.com", allowed: true)
        for index in 0..<(NetworkAudit.maxHostsPerPlugin * 3) {
            audit.record(pluginID: "p", host: "made-up-\(index).example", allowed: false, at: Date().addingTimeInterval(Double(index)))
        }
        let entries = audit.entries(for: "p")
        XCTAssertEqual(entries.count, NetworkAudit.maxHostsPerPlugin)
        XCTAssertTrue(entries.contains { $0.host == "api.example.com" })
    }
}

final class UserServerLookupTests: XCTestCase {
    final class CountingSecrets: SecretStore, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var reads: Int { lock.withLock { count } }
        func secret(_ name: String) throws -> String? { lock.withLock { count += 1 }; return "https://server.example.com/api" }
        func setSecret(_ value: String?, for name: String) throws {}
    }

    func testAFailingCallReadsEachUserServerSecretOnce() async {
        let secrets = CountingSecrets()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: secrets)
        let manifest = Manifest(id: "dev.test.p", name: "P", capabilities: [.userServer(secret: "PROXY_URL")])
        let result = await services.handle(.http(HTTPRequest(url: "https://other.example.com/")), for: manifest)
        guard case .failure = result else { return XCTFail("\(result)") }
        XCTAssertEqual(secrets.reads, 1)
    }
}
