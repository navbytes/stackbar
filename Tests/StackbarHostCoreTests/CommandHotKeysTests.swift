import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class CommandHotKeysTests: XCTestCase {
    private let clipboard = "io.navbytes.stackbar.clipboard"

    private func entry(_ id: String, plugin: String) -> CommandRegistry.Entry {
        CommandRegistry.Entry(pluginID: plugin, pluginName: "Clipboard History", spec: CommandSpec(id: id, title: id, kind: .view))
    }

    private func manifest(hotkey: String?, command: String?) -> Manifest {
        Manifest(id: clipboard, name: "Clipboard History", surfaces: [.menuBar, .panel], hotkey: hotkey, hotkeyCommand: command)
    }

    func testAManifestCanGiveItsHotkeyToACommand() {
        let entries = [entry("search", plugin: clipboard), entry("pause", plugin: clipboard)]
        let manifests = [clipboard: manifest(hotkey: "cmd+shift+v", command: "search")]
        let wanted = CommandHotKeys.wanted(entries: entries, preference: { _ in .default }, manifests: manifests)
        XCTAssertEqual(wanted, [CommandKey(pluginID: clipboard, commandID: "search"): "cmd+shift+v"])
        XCTAssertFalse(CommandHotKeys.opensPanel(manifests[clipboard]), "the panel no longer takes it")
        XCTAssertTrue(CommandHotKeys.opensPanel(manifest(hotkey: "cmd+shift+v", command: nil)))
        XCTAssertFalse(CommandHotKeys.opensPanel(nil))
    }

    func testTheUsersOwnHotkeyAndSwitchWin() {
        let search = entry("search", plugin: clipboard)
        let manifests = [clipboard: manifest(hotkey: "cmd+shift+v", command: "search")]
        let own = CommandHotKeys.wanted(entries: [search], preference: { _ in CommandPreference(hotkey: "ctrl+option+v") }, manifests: manifests)
        XCTAssertEqual(own[search.key], "ctrl+option+v")
        let off = CommandHotKeys.wanted(entries: [search], preference: { _ in CommandPreference(enabled: false) }, manifests: manifests)
        XCTAssertTrue(off.isEmpty, "a command turned off has no hotkey")
    }

    func testHotkeyCommandNeedsAHotkey() {
        XCTAssertTrue(manifest(hotkey: nil, command: "search").problems.contains("hotkeyCommand needs a hotkey to open it"))
        XCTAssertTrue(manifest(hotkey: "cmd+shift+v", command: "search").problems.isEmpty)
    }
}
