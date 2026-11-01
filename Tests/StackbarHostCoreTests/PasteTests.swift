import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Pasting with options, and storage grants.
final class PasteTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func services(_ system: SimulatedSystem) -> HostServices {
        HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system))
    }

    private let manifest = Manifest(id: "dev.test.paste", name: "Paste", capabilities: [.clipboard])

    func testAPasteThatRestoresPutsTheClipboardBack() async throws {
        let system = SimulatedSystem()
        system.restoreDelay = .milliseconds(20)
        system.simulateCopy("what the user had")
        let result = await services(system).handle(.paste(.text("snippet"), options: PasteOptions(restoreClipboard: true, cursorFromEnd: 3)), for: manifest)
        XCTAssertEqual(result, .ok)
        XCTAssertEqual(system.pastes.last?.options, PasteOptions(restoreClipboard: true, cursorFromEnd: 3))
        XCTAssertEqual(system.readClipboard()?.concealed, true, "the pasted text is transient")
        let restored = await waitUntil { system.readClipboard()?.text == "what the user had" }
        XCTAssertTrue(restored)
        XCTAssertEqual(system.readClipboard()?.concealed, false)
    }

    func testACopyMeanwhileIsLeftAlone() async throws {
        let system = SimulatedSystem()
        system.restoreDelay = .milliseconds(50)
        system.simulateCopy("old")
        _ = await services(system).handle(.paste(.text("snippet"), options: PasteOptions(restoreClipboard: true)), for: manifest)
        system.simulateCopy("copied after the paste")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(system.readClipboard()?.text, "copied after the paste")
    }

    func testAPlainPasteLeavesTheContentOnTheClipboard() async throws {
        let system = SimulatedSystem()
        system.restoreDelay = .milliseconds(10)
        system.simulateCopy("old")
        _ = await services(system).handle(.paste(.text("from history")), for: manifest)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(system.readClipboard()?.text, "from history")
        XCTAssertEqual(system.readClipboard()?.concealed, false)
        XCTAssertEqual(system.pastes.last?.options, PasteOptions())
    }

    func testTheCursorOffsetIsCapped() async throws {
        let system = SimulatedSystem()
        _ = await services(system).handle(.paste(.text("x"), options: PasteOptions(cursorFromEnd: 1_000_000)), for: manifest)
        XCTAssertEqual(system.pastes.last?.options.cursorFromEnd, PasteOptions.maxCursorFromEnd)
        XCTAssertEqual(PasteOptions(cursorFromEnd: -4).cursorFromEnd, 0)
    }

    func testOlderPluginsPasteWithoutOptions() throws {
        // A protocol 9 plugin sends `paste` with only the content.
        let old = #"{"paste":{"_0":{"text":{"_0":"hi"}}}}"#
        let call = try JSONDecoder().decode(HostCall.self, from: Data(old.utf8))
        XCTAssertEqual(call, .paste(.text("hi"), options: nil))
    }

    func testStorageQuotaComesFromTheGrant() async throws {
        let services = services(SimulatedSystem())
        let big = String(repeating: "x", count: 2 * 1024 * 1024)
        let plain = Manifest(id: "dev.test.plain", name: "Plain")
        guard case .failure(let message) = await services.handle(.storageSet(key: "k", value: big), for: plain) else { return XCTFail("1 MB by default") }
        XCTAssertTrue(message.contains("the limit is 1048576"), message)

        let granted = Manifest(id: "dev.test.big", name: "Big", capabilities: [.storage(megabytes: 4)])
        let ok = await services.handle(.storageSet(key: "k", value: big), for: granted)
        XCTAssertEqual(ok, .ok)
        let tooBig = String(repeating: "x", count: 5 * 1024 * 1024)
        guard case .failure = await services.handle(.storageSet(key: "k2", value: tooBig), for: granted) else { return XCTFail("4 MB is the grant") }
        // Removing a value always works, even over the quota.
        let removed = await services.handle(.storageSet(key: "k", value: nil), for: plain)
        XCTAssertEqual(removed, .ok)

        XCTAssertEqual(granted.storageQuotaBytes, 4 * 1024 * 1024)
        XCTAssertNil(plain.storageQuotaBytes)
        XCTAssertEqual(Capability.storage(megabytes: 16).summary, "Stores up to 16 MB")
        XCTAssertTrue(Manifest(id: "dev.test.x", name: "X", capabilities: [.storage(megabytes: 65)]).problems.contains("storage is 1 to 64 megabytes"))
        XCTAssertTrue(Manifest(id: "dev.test.x", name: "X", capabilities: [.storage(megabytes: 2), .storage(megabytes: 3)]).problems.contains("declare .storage(megabytes:) once"))
    }
}
