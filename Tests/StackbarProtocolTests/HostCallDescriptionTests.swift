import Foundation
import XCTest
@testable import StackbarProtocol

final class HostCallDescriptionTests: XCTestCase {
    /// One of each case; `label` and `requirement` themselves are exhaustive.
    static let everyCall: [HostCall] = [
        .storageSet(key: "k", value: nil), .secret(name: "TOKEN"), .http(HTTPRequest(url: "https://example.com")),
        .oauthToken(provider: "github", forceRefresh: false), .publish(topic: "t", payload: "{}"),
        .notify(title: "t", body: nil), .alert(title: "t", body: nil, actions: []), .playSound(.ping),
        .openURL("https://example.com"), .open(url: "https://example.com", app: nil), .copy("x"),
        .clipboardRead, .clipboardWrite(.text("x")), .paste(.text("x")), .keepAwake(KeepAwakeRequest()), .keepAwake(nil),
        .systemStatus, .calendarEvents(from: Date(), to: Date()), .run(RunRequest(command: "brew")), .cancelRun(id: 1),
        .context, .finderSelection, .chooseFile(types: []), .saveFile(name: "x.json", data: Data()), .resolveApplication("Safari"),
    ]

    func testEveryCallHasALabel() {
        for call in Self.everyCall {
            XCTAssertFalse(call.label.isEmpty, "\(call)")
        }
    }

    func testRequirements() {
        XCTAssertEqual(HostCall.clipboardRead.requirement?.capability, .clipboard)
        XCTAssertEqual(HostCall.clipboardRead.requirement?.purpose, "read the clipboard")
        XCTAssertEqual(HostCall.paste(.text("x")).requirement?.capability, .clipboard)
        XCTAssertEqual(HostCall.keepAwake(KeepAwakeRequest()).requirement?.capability, .power)
        // Letting go needs nothing, so a revoked plugin can still release.
        XCTAssertNil(HostCall.keepAwake(nil).requirement)
        // What these need depends on the manifest's details; the host checks them.
        XCTAssertNil(HostCall.secret(name: "TOKEN").requirement)
        XCTAssertNil(HostCall.run(RunRequest(command: "brew")).requirement)
    }
}
