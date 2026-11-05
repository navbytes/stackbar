import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Protocol 20: focusing a window, the front app's menus, and where the app
/// lives.
final class MenusAndWindowFocusTests: XCTestCase {
    func testShortcutGlyphs() {
        XCTAssertEqual(MenuSnapshot.shortcut(character: "s", modifiers: 0), "⌘S")
        XCTAssertEqual(MenuSnapshot.shortcut(character: "S", modifiers: 1), "⇧⌘S")
        XCTAssertEqual(MenuSnapshot.shortcut(character: "f", modifiers: 4 | 2), "⌃⌥⌘F", "⌃ ⌥ ⇧ ⌘ is macOS's order")
        XCTAssertEqual(MenuSnapshot.shortcut(character: "x", modifiers: 8 | 4), "⌃X", "8 takes ⌘ away")
        XCTAssertEqual(MenuSnapshot.shortcut(character: " ", modifiers: 4), "⌃⌘Space")
        XCTAssertNil(MenuSnapshot.shortcut(character: nil, modifiers: 0))
        XCTAssertNil(MenuSnapshot.shortcut(character: "", modifiers: 1))
    }

    func testMenuItemParts() {
        let item = MenuItemInfo(path: ["File", "Export", "PDF…"])
        XCTAssertEqual(item.title, "PDF…")
        XCTAssertEqual(item.location, "File › Export")
        let many = MenuSnapshot(appID: "a", appName: "A", items: Array(repeating: item, count: MenuSnapshot.maxItems + 5))
        XCTAssertEqual(many.items.count, MenuSnapshot.maxItems)
        XCTAssertEqual(try SystemCodec.decode(MenuSnapshot.self, from: SystemCodec.encode(many)), many)
    }

    func testWindowTargetMatchesTitleThenOrder() {
        let frame = WindowRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [
            WindowInfo(appID: "com.apple.Safari", appName: "Safari", title: "Docs", frame: frame, order: 0),
            WindowInfo(appID: "com.apple.Notes", appName: "Notes", title: "Notes", frame: frame, order: 1),
            WindowInfo(appID: "com.apple.Safari", appName: "Safari", title: "News", frame: frame, order: 2),
        ]
        let snapshot = WindowSnapshot(windows: windows)
        let target = WindowTarget(windows[2], in: snapshot)
        XCTAssertEqual(target, WindowTarget(appID: "com.apple.Safari", title: "News", ordinal: 1))
        XCTAssertEqual(target.index(in: windows), 2)
        XCTAssertEqual(WindowTarget(appID: "com.apple.Safari", title: "Renamed", ordinal: 1).index(in: windows), 2, "a changed title falls back to the order")
        XCTAssertEqual(WindowTarget(appID: "com.apple.Safari", title: "", ordinal: 9).index(in: windows), 0, "past the end: the app's first")
        XCTAssertNil(WindowTarget(appID: "com.apple.Mail").index(in: windows))
    }

    func testCallsNeedTheirCapabilities() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = SimulatedSystem()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system))
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        for call: HostCall in [.menuItems, .pressMenuItem(appID: "com.apple.Safari", path: ["File", "New Window"])] {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without .menus") }
            XCTAssertTrue(message.contains("add .menus"), message)
        }
        guard case .failure(let message) = await services.handle(.focusWindow(WindowTarget(appID: "x")), for: bare) else { return XCTFail("focus without .windows") }
        XCTAssertTrue(message.contains("add .windows"), message)

        let menus = Manifest(id: "dev.test.menus", name: "Menus", capabilities: [.menus])
        guard case .value(let json?) = await services.handle(.menuItems, for: menus) else { return XCTFail("menus refused") }
        let snapshot = try SystemCodec.decode(MenuSnapshot.self, from: json)
        XCTAssertEqual(snapshot.appName, "Safari")
        guard case .ok = await services.handle(.pressMenuItem(appID: snapshot.appID, path: ["File", "New Window"]), for: menus) else { return XCTFail("press refused") }
        XCTAssertEqual(system.appActions.last, "press com.apple.Safari File > New Window")
        guard case .failure(let dimmed) = await services.handle(.pressMenuItem(appID: snapshot.appID, path: ["Edit", "Undo"]), for: menus) else { return XCTFail("a dimmed item was chosen") }
        XCTAssertTrue(dimmed.contains("dimmed"), dimmed)
        guard case .failure = await services.handle(.pressMenuItem(appID: snapshot.appID, path: []), for: menus) else { return XCTFail("an empty path was accepted") }

        let windows = Manifest(id: "dev.test.windows", name: "Windows", capabilities: [.windows])
        let before = system.currentWindows
        let last = try XCTUnwrap(before.windows.last)
        guard case .ok = await services.handle(.focusWindow(WindowTarget(last, in: before)), for: windows) else { return XCTFail("focus refused") }
        XCTAssertEqual(system.currentWindows.windows.first?.title, last.title)
        XCTAssertEqual(system.currentWindows.windows.first?.appID, last.appID)
    }

    func testMoveToApplications() {
        let home = "/Users/sam"
        XCTAssertFalse(AppLocation.shouldOfferMove(bundlePath: "/Applications/Stackbar.app", home: home))
        XCTAssertFalse(AppLocation.shouldOfferMove(bundlePath: "/Users/sam/Applications/Stackbar.app", home: home))
        XCTAssertTrue(AppLocation.shouldOfferMove(bundlePath: "/Users/sam/Downloads/Stackbar.app", home: home))
        XCTAssertTrue(AppLocation.shouldOfferMove(bundlePath: "/private/var/folders/x/AppTranslocation/1234/d/Stackbar.app", home: home))
        XCTAssertTrue(AppLocation.shouldOfferMove(bundlePath: "/Volumes/Stackbar/Stackbar.app", home: home))
        XCTAssertFalse(AppLocation.shouldOfferMove(bundlePath: "/Users/sam/dev/.build/debug/Stackbar", home: home), "not a bundle")
    }

    func testCommandLineLinkIsQuoted() {
        XCTAssertEqual(AppLocation.linkCommand(to: "/Applications/Stackbar.app/Contents/MacOS/stackbarctl"),
                       "mkdir -p '/usr/local/bin' && ln -sf '/Applications/Stackbar.app/Contents/MacOS/stackbarctl' '/usr/local/bin/stackbarctl'")
        XCTAssertEqual(AppLocation.quoted("/Users/o'neil/Stackbar.app"), "'/Users/o'\\''neil/Stackbar.app'")
    }
}
