import Foundation
import XCTest
@testable import StackbarKit

final class SentMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [PluginMessage] = []
    func add(_ message: PluginMessage) { lock.withLock { list.append(message) } }
    var all: [PluginMessage] { lock.withLock { list } }
    var calls: [(id: Int, call: HostCall)] {
        all.compactMap { if case .request(let id, let call) = $0 { return (id, call) } else { return nil } }
    }
}

final class RunClientTests: XCTestCase {
    func testAStreamGetsItsOutputThenItsExit() async throws {
        let client = HostClient()
        let sent = SentMessages()
        client.configure(send: sent.add)
        let events = client.stream(RunRequest(command: "docker", arguments: ["logs", "-f", "web"]))
        let (id, call) = try XCTUnwrap(sent.calls.first)
        guard case .run(let request) = call else { return XCTFail("sent \(call)") }
        XCTAssertTrue(request.stream)
        XCTAssertEqual(request.arguments, ["logs", "-f", "web"])

        XCTAssertTrue(client.resolve(id: id, result: .ok))
        XCTAssertTrue(client.deliver(run: .runOutput(id: id, channel: .stdout, data: Data("one\n".utf8))))
        XCTAssertTrue(client.deliver(run: .runOutput(id: id, channel: .stderr, data: Data("warn\n".utf8))))
        XCTAssertTrue(client.deliver(run: .runExit(id: id, exit: RunExit(status: 0))))
        XCTAssertFalse(client.deliver(run: .runOutput(id: id, channel: .stdout, data: Data())), "nothing after the exit")

        var received: [RunEvent] = []
        for try await event in events { received.append(event) }
        XCTAssertEqual(received, [.stdout(Data("one\n".utf8)), .stderr(Data("warn\n".utf8)), .exit(RunExit(status: 0))])
        XCTAssertFalse(sent.calls.contains { if case .cancelRun = $0.call { return true } else { return false } }, "a finished run is not cancelled")
    }

    func testLeavingTheLoopEarlyCancelsTheRun() async throws {
        let client = HostClient()
        let sent = SentMessages()
        client.configure(send: sent.add)
        // As a plugin writes it: nothing else holds the stream.
        func readFirstLine() async throws -> RunEvent? {
            for try await event in client.stream(RunRequest(command: "tail", arguments: ["-f", "/var/log/system.log"])) {
                return event
            }
            return nil
        }
        let host = Task.detached {
            while sent.calls.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
            let id = sent.calls[0].id
            client.resolve(id: id, result: .ok)
            client.deliver(run: .runOutput(id: id, channel: .stdout, data: Data("line\n".utf8)))
            return id
        }
        let first = try await readFirstLine()
        XCTAssertEqual(first, .stdout(Data("line\n".utf8)))
        let id = await host.value
        let cancelled = sent.calls.contains { if case .cancelRun(id) = $0.call { return true } else { return false } }
        XCTAssertTrue(cancelled)
    }

    func testARefusedRunThrowsItsReason() async throws {
        let client = HostClient()
        let sent = SentMessages()
        client.configure(send: sent.add)
        let events = client.stream(RunRequest(command: "brew"))
        let id = try XCTUnwrap(sent.calls.first?.id)
        client.resolve(id: id, result: .failure("brew is not installed"))
        do {
            for try await _ in events {}
            XCTFail("did not throw")
        } catch {
            XCTAssertEqual("\(error)", "brew is not installed")
        }
    }

    func testTheHostGoingAwayEndsStreams() async throws {
        let client = HostClient()
        let sent = SentMessages()
        client.configure(send: sent.add)
        let events = client.stream(RunRequest(command: "sleep", arguments: ["30"]))
        client.failAll("the host went away")
        do {
            for try await _ in events {}
            XCTFail("did not throw")
        } catch {
            XCTAssertEqual("\(error)", "the host went away")
        }
    }
}
