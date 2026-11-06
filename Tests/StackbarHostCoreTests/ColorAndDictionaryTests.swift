import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Protocol 21: picking a color from the screen and the Mac's dictionary.
final class ColorAndDictionaryTests: XCTestCase {
    func testColorFormats() throws {
        let blue = try XCTUnwrap(PickedColor(hex: "#0A60C8"))
        XCTAssertEqual(blue.hex, "#0A60C8")
        XCTAssertEqual(blue.rgb, "rgb(10, 96, 200)")
        XCTAssertEqual(blue.hsl, "hsl(213, 90%, 41%)")
        XCTAssertEqual(PickedColor(hex: "fff")?.hex, "#FFFFFF")
        XCTAssertEqual(PickedColor(red: 0, green: 0, blue: 0).hsl, "hsl(0, 0%, 0%)")
        XCTAssertNil(PickedColor(hex: "#12345"))
        XCTAssertNil(PickedColor(hex: "zzzzzz"))
        XCTAssertEqual(PickedColor(red: 2, green: -1, blue: .nan).hex, "#FF0000", "out of range clamps")
    }

    func testCallsAnswerWithoutCapabilities() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = SimulatedSystem()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system))
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        XCTAssertNil(HostCall.pickColor.requirement)
        XCTAssertNil(HostCall.define("x").requirement)

        system.simulate(pickedColor: PickedColor(hex: "#FF8000"))
        system.simulate(pickedColor: nil)
        guard case .value(let json?) = await services.handle(.pickColor, for: bare) else { return XCTFail("pick refused") }
        XCTAssertEqual(try SystemCodec.decode(PickedColor.self, from: json).hex, "#FF8000")
        guard case .value(nil) = await services.handle(.pickColor, for: bare) else { return XCTFail("Escape answers nil") }

        guard case .value(let found?) = await services.handle(.define(" Serendipity "), for: bare) else { return XCTFail("define refused") }
        XCTAssertTrue(try SystemCodec.decode(Definition.self, from: found).text.contains("by chance"))
        guard case .value(nil) = await services.handle(.define("qwxzv"), for: bare) else { return XCTFail("an unknown word answers nil") }
        guard case .failure = await services.handle(.define(String(repeating: "a", count: Definition.maxQuery + 1)), for: bare) else { return XCTFail("a long query was accepted") }
        guard case .failure = await services.handle(.define("  "), for: bare) else { return XCTFail("an empty query was accepted") }
    }
}

final class CommunityAuthorTests: XCTestCase {
    func testCommunityAuthorComesFromTheID() {
        func entry(_ id: String) -> PluginIndex.Entry {
            PluginIndex.Entry(id: id, name: "X", version: "1.0.0", publisher: "p", bundle: "b", sha256: "s", capabilities: [])
        }
        XCTAssertEqual(entry("io.github.octocat.hacker-news").communityAuthor, "octocat")
        XCTAssertNil(entry("io.navbytes.stackbar.plugins.timers").communityAuthor)
        XCTAssertNil(entry("io.github..x").communityAuthor)
        XCTAssertNil(entry("io.github.octocat").communityAuthor)
        XCTAssertEqual(StoreListing.look(ofCategory: "Community").symbol, "person.2.fill")
    }
}
