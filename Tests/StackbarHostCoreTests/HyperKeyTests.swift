import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class HyperKeyTests: XCTestCase {
    private let hidutilOutput = """
    (
            {
            HIDKeyboardModifierMappingDst = 30064771300;
            HIDKeyboardModifierMappingSrc = 30064771296;
        }
    )
    """

    func testReadsTheMappingsHidutilPrints() {
        XCTAssertEqual(HyperKey.mappings(fromHidutil: hidutilOutput), [HyperKey.Mapping(source: 30064771296, destination: 30064771300)])
        XCTAssertEqual(HyperKey.mappings(fromHidutil: "(null)"), [])
        XCTAssertEqual(HyperKey.mappings(fromHidutil: ""), [])
    }

    func testTurningOnAndOffKeepsSomeoneElsesRemaps() {
        let other = HyperKey.Mapping(source: 30064771296, destination: 30064771300)
        let on = HyperKey.mappings([other], hyper: true)
        XCTAssertEqual(on, [other, HyperKey.ours])
        XCTAssertEqual(HyperKey.mappings(on, hyper: true), on, "turning it on twice adds it once")
        XCTAssertEqual(HyperKey.mappings(on, hyper: false), [other])
    }

    func testTheJSONIsWhatHidutilTakes() throws {
        let json = HyperKey.hidutilJSON([HyperKey.ours])
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [[String: UInt64]]]
        XCTAssertEqual(object?["UserKeyMapping"]?.first?["HIDKeyboardModifierMappingSrc"], 0x7_0000_0039)
        XCTAssertEqual(object?["UserKeyMapping"]?.first?["HIDKeyboardModifierMappingDst"], 0x7_0000_006D)
        XCTAssertEqual(HyperKey.hidutilJSON([]), "{\"UserKeyMapping\":[]}")
    }

    func testHeldWithAKeyAddsTheModifiers() {
        var state = HyperKey.State(escapeOnTap: true)
        XCTAssertEqual(state.handle(.keyDown(code: HyperKey.f18KeyCode, at: 0)), .swallow)
        XCTAssertEqual(state.handle(.keyDown(code: HyperKey.f18KeyCode, at: 0.5)), .swallow, "auto-repeat")
        XCTAssertEqual(state.handle(.keyDown(code: 0, at: 0.6)), .withHyper)
        XCTAssertEqual(state.handle(.keyUp(code: HyperKey.f18KeyCode, at: 0.7)), .swallow, "used with a key: no Escape")
        XCTAssertEqual(state.handle(.keyUp(code: 0, at: 0.8)), .withHyper, "the key's release keeps Hyper")
        XCTAssertEqual(state.handle(.keyDown(code: 0, at: 1)), .pass)
        XCTAssertEqual(state.handle(.keyUp(code: 0, at: 1.1)), .pass)
    }

    func testATapIsEscapeOnlyWhenQuickAndWanted() {
        var state = HyperKey.State(escapeOnTap: true)
        _ = state.handle(.keyDown(code: HyperKey.f18KeyCode, at: 0))
        XCTAssertEqual(state.handle(.keyUp(code: HyperKey.f18KeyCode, at: 0.1)), .escape)
        _ = state.handle(.keyDown(code: HyperKey.f18KeyCode, at: 1))
        XCTAssertEqual(state.handle(.keyUp(code: HyperKey.f18KeyCode, at: 2)), .swallow, "held too long")

        var noEscape = HyperKey.State(escapeOnTap: false)
        _ = noEscape.handle(.keyDown(code: HyperKey.f18KeyCode, at: 0))
        XCTAssertEqual(noEscape.handle(.keyUp(code: HyperKey.f18KeyCode, at: 0.1)), .swallow)
    }
}

final class CommandFoldersTests: XCTestCase {
    func testAddedFoldersAreCleanedAndComeLast() {
        let home = NSHomeDirectory()
        XCTAssertEqual(CommandResolver.extraFolders("~/.cargo/bin: /opt/tools/ \n relative/bin\n/usr/bin\n~/.cargo/bin"),
                       [home + "/.cargo/bin", "/opt/tools"], "tilde expanded, relative and repeated folders dropped, built-in ones not added twice")
        XCTAssertEqual(CommandResolver.extraFolders(nil), [])
        XCTAssertEqual(Array(CommandResolver.searchPath.prefix(CommandResolver.builtInSearchPath.count)), CommandResolver.builtInSearchPath)
    }

    func testARunCommandCanAskForMoreTime() throws {
        let spec = CommandSpec(id: "build", title: "Build", timeout: 120)
        XCTAssertEqual(spec.runTimeout(standard: 30), 120)
        XCTAssertEqual(CommandSpec(id: "a", title: "A").runTimeout(standard: 30), 30)
        XCTAssertEqual(CommandSpec(id: "a", title: "A", timeout: 99_999).runTimeout(standard: 30), CommandSpec.maxTimeout)
        let decoded = try JSONDecoder().decode(CommandSpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(decoded.timeout, 120)
        let old = try JSONDecoder().decode(CommandSpec.self, from: Data(#"{"id":"a","title":"A","kind":"run"}"#.utf8))
        XCTAssertNil(old.timeout)
    }
}
