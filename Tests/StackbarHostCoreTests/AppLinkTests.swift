import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class AppLinkTests: XCTestCase {
    func testLinksToSettingsAndTheStore() throws {
        XCTAssertEqual(AppLink(try XCTUnwrap(URL(string: "stackbar://settings"))), .settings(page: nil))
        XCTAssertEqual(AppLink(try XCTUnwrap(URL(string: "stackbar://Settings/Commands"))), .settings(page: "commands"))
        XCTAssertEqual(AppLink(try XCTUnwrap(URL(string: "stackbar://store"))), .store)
        XCTAssertNil(AppLink(try XCTUnwrap(URL(string: "stackbar://settings/nowhere"))), "only the app's own pages")
        XCTAssertNil(AppLink(try XCTUnwrap(URL(string: "stackbar://store/dev.t.a"))), "a plugin's page is a StoreLink")
        XCTAssertNil(AppLink(try XCTUnwrap(URL(string: "stackbar://commands/a/b"))))
        XCTAssertNil(AppLink(try XCTUnwrap(URL(string: "https://settings"))))
        for entry in PaletteIndex.appEntries {
            guard case .open(let url) = entry.kind else { return XCTFail("\(entry.title) isn't a link") }
            XCTAssertNotNil(AppLink(try XCTUnwrap(URL(string: url))), url)
        }
    }

    /// Typing "settings" and pressing Return opens Stackbar's Settings, not a
    /// file or a System Settings pane that also says "settings".
    func testTypingSettingsPutsStackbarSettingsUnderReturn() throws {
        var index = PaletteIndex()
        XCTAssertTrue(index.search("settings").isEmpty, "only the app lists its own places")
        index.includesAppEntries = true
        let panel = ViewNode.stack(axis: .vertical, children: [
            .button(title: "Settings", action: "button/Settings"),
            .button(title: "Copy Path: Settings", action: "button/Copy Path"),
        ])
        index.update(pluginID: "files", pluginName: "File Search", panel: panel)
        let found = index.search("settings")
        XCTAssertEqual(found.first?.title, "Stackbar Settings")
        XCTAssertEqual(index.search("store").first?.title, "Plugin Store")
        XCTAssertEqual(index.search("hotkeys").first?.title, "Commands & Hotkeys")

        let files = PaletteSection(title: "Files", entries: [PaletteIndex.Entry(pluginID: "files", pluginName: "File Search",
                                                                              title: "SettingsSearchReindexService.log", kind: .action("button/open", value: nil))])
        let sections = PaletteSection.group(found, query: "settings", plugins: [files]) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Results", "Files"])
        XCTAssertEqual(sections.first?.entries.first?.title, "Stackbar Settings")
        // Something that merely starts with the text still leads a fuzzy match.
        let partial = PaletteSection.group(index.search("sett"), query: "sett", plugins: [files]) { _ in false }
        XCTAssertEqual(partial.map(\.title), ["Files", "Results"])
    }
}
