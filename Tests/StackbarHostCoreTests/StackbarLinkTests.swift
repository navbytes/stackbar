import Foundation
@testable import StackbarHostCore
import StackbarProtocol
import XCTest

final class StackbarLinkTests: XCTestCase {
    private func link(_ text: String) -> StackbarLink? { StackbarLink(text) }

    func testEachKindOfLinkIsReadOnce() {
        XCTAssertEqual(link("stackbar://store/dev.example.weather"), .storePage(StoreLink(pluginID: "dev.example.weather")))
        XCTAssertEqual(link("stackbar://store"), .place(.store))
        XCTAssertEqual(link("STACKBAR://settings/commands"), .place(.settings(page: "commands")))
        XCTAssertEqual(link("stackbar://commands/dev.example.notes/new?title=Hi"),
                       .command(CommandLink(key: CommandKey(pluginID: "dev.example.notes", commandID: "new"), arguments: ["title": "Hi"])))
        XCTAssertEqual(link("stackbar://settings/nowhere"), .unknown(URL(string: "stackbar://settings/nowhere")!))
        XCTAssertEqual(link("https://stackbar.app"), .external(URL(string: "https://stackbar.app")!))
        XCTAssertNil(link("not a link"))
    }

    func testOnlyPagesAreFreeToOpen() {
        XCTAssertTrue(link("stackbar://settings")!.isPage)
        XCTAssertTrue(link("stackbar://store/dev.example.weather")!.isPage)
        XCTAssertFalse(link("stackbar://commands/dev.example.notes/new")!.isPage, "a command link can run something")
        XCTAssertFalse(link("https://example.com")!.isPage)
    }
}
