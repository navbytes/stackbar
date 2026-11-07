import Foundation
@testable import StackbarHostCore
import StackbarProtocol
import XCTest

/// Each host call's rate limit is declared on `HostCall.budget`, checked in
/// one place, and listed in the guide from the same table.
final class RateBudgetTests: XCTestCase {
    func testCallsInOnePoolShareItsLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: SimulatedSystem()))
        let plugin = Manifest(id: "dev.test.switcher", name: "Switcher", capabilities: [.apps, .windows, .menus])
        let safari = "com.apple.Safari"
        for index in 0..<RateBudget.Pool.appSwitching.limit {
            let call: HostCall = index.isMultiple(of: 2) ? .activateApp(safari, launch: false) : .hideApp(safari)
            if case .failure(let message) = await services.handle(call, for: plugin), message.hasPrefix("too many") {
                return XCTFail("refused at \(index): \(message)")
            }
        }
        let refused = await services.handle(.pressMenuItem(appID: safari, path: ["File"]), for: plugin)
        XCTAssertEqual(refused, .failure("too many menu presses; at most 120 a minute"), "menu presses draw from the app switches' pool")

        let other = Manifest(id: "dev.test.other", name: "Other", capabilities: [.apps])
        if case .failure(let message) = await services.handle(.hideApp(safari), for: other) {
            XCTAssertFalse(message.hasPrefix("too many"), "each plugin has its own budget")
        }
    }

    func testAMissingCapabilityIsReportedBeforeTheBudget() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: SimulatedSystem()))
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        for _ in 0...RateBudget.Pool.terminals.limit {
            guard case .failure(let message) = await services.handle(.openInTerminal(command: ["ls"], title: nil), for: bare) else { return XCTFail("ran without .terminal") }
            XCTAssertTrue(message.contains("add .terminal"), message)
        }
    }

    func testTheGuideListsEveryPool() {
        for pool in RateBudget.Pool.allCases {
            XCTAssertTrue(AuthoringGuide.text.contains("| \(pool.calls) |"), "\(pool) is missing from the guide")
        }
        XCTAssertTrue(AuthoringGuide.text.contains("| `activateApp`, `hideApp`, `focusWindow`, `pressMenuItem` | 120 a minute |"))
    }

    func testSharedPoolsKeepTheirOwnWords() {
        XCTAssertEqual(HostCall.pickColor.budget, RateBudget(.filePanels, "color pickers"))
        XCTAssertEqual(HostCall.chooseFile(types: []).budget?.pool, .filePanels)
        XCTAssertNil(HostCall.clipboardRead.budget)
    }
}
