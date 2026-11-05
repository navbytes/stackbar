import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Keyword expansion: what counts as typing a keyword, who holds a keyword,
/// the host calls and their capability.
final class TextExpansionTests: XCTestCase {
    private func entry(_ keyword: String, _ command: String = "sn-1", plugin: String = "dev.snippets") -> TextExpansionRegistry.Entry {
        TextExpansionRegistry.Entry(keyword: keyword, pluginID: plugin, pluginName: "Snippets", command: command)
    }

    private func typeEach(_ text: String, into matcher: inout TextExpansionMatcher) -> [TextExpansionMatcher.Match] {
        text.compactMap { matcher.type(String($0)) }
    }

    func testAKeywordExpandsAsItsLastCharacterIsTyped() {
        var matcher = TextExpansionMatcher([entry(";sig")])
        XCTAssertNil(matcher.type(";"))
        XCTAssertNil(matcher.type("s"))
        XCTAssertNil(matcher.type("i"))
        let match = matcher.type("g")
        XCTAssertEqual(match, .init(keyword: ";sig", pluginID: "dev.snippets", command: "sn-1", deleteCount: 4))
        XCTAssertNil(matcher.type("g"), "it starts over after a match")
    }

    func testOnlyAtTheStartOfAWord() {
        var matcher = TextExpansionMatcher([entry("addr")])
        XCTAssertTrue(typeEach("xaddr", into: &matcher).isEmpty, "not inside a word")
        matcher.reset()
        XCTAssertEqual(typeEach("my addr", into: &matcher).map(\.keyword), ["addr"])
        matcher.reset()
        XCTAssertEqual(typeEach("(addr", into: &matcher).map(\.keyword), ["addr"], "after punctuation")

        var punctuated = TextExpansionMatcher([entry(";sig")])
        XCTAssertEqual(typeEach("hello;sig", into: &punctuated).map(\.keyword), [";sig"], "a keyword that starts with punctuation expands anywhere")
    }

    func testTheLongestKeywordWins() {
        var matcher = TextExpansionMatcher([entry(";s", "short"), entry(";sig", "long")])
        // ";s" completes first, so a keyword that another starts with
        // expands at once, as in Raycast.
        XCTAssertEqual(typeEach(";s", into: &matcher).map(\.command), ["short"])
        var ending = TextExpansionMatcher([entry("ig", "short"), entry(";sig", "long")])
        XCTAssertEqual(typeEach(";sig", into: &ending).map(\.command), ["long"], "when one keyword ends another, the longer one wins")
    }

    func testBackspaceAndInterruptions() {
        var matcher = TextExpansionMatcher([entry(";sig")])
        _ = typeEach(";six", into: &matcher)
        matcher.deleteBackward()
        XCTAssertEqual(matcher.type("g")?.keyword, ";sig", "fixing a typo still expands")

        _ = typeEach(";si", into: &matcher)
        matcher.reset()
        XCTAssertNil(matcher.type("g"), "a click or an arrow key starts over")
    }

    func testGraphemesAndMemory() {
        var matcher = TextExpansionMatcher([entry(":café")])
        XCTAssertEqual(typeEach(":café", into: &matcher).first?.deleteCount, 5, "one backspace per character, not per scalar")
        var long = TextExpansionMatcher([entry("x")])
        _ = typeEach(String(repeating: "a", count: 200), into: &long)
        XCTAssertNil(long.type("x"), "x follows a letter")
        XCTAssertEqual(long.type(" ").map(\.keyword), nil)
        XCTAssertEqual(long.type("x")?.keyword, "x")
    }

    func testKeywordRules() {
        XCTAssertTrue(TextExpansion.isValidKeyword(";sig"))
        XCTAssertTrue(TextExpansion.isValidKeyword("!!date"))
        for bad in ["", "a b", "say\"", "it's", "`x`", String(repeating: "a", count: 33)] {
            XCTAssertFalse(TextExpansion.isValidKeyword(bad), bad)
        }
        let doubled = [TextExpansion(keyword: ";a", command: "1"), TextExpansion(keyword: ";a", command: "2")]
        XCTAssertEqual(TextExpansion.problems(doubled), ["keyword \";a\" is registered twice"])
    }

    func testTheFirstPluginHoldsAKeyword() throws {
        let registry = TextExpansionRegistry()
        try registry.set([TextExpansion(keyword: ";sig", command: "a1"), TextExpansion(keyword: ";hi", command: "a2")], pluginID: "dev.a", pluginName: "A")
        try registry.set([TextExpansion(keyword: ";sig", command: "b1"), TextExpansion(keyword: ";yo", command: "b2")], pluginID: "dev.b", pluginName: "B")
        XCTAssertEqual(registry.live.map { "\($0.keyword)=\($0.command)" }, [";sig=a1", ";hi=a2", ";yo=b2"])
        XCTAssertEqual(registry.taken(for: "dev.b"), [";sig"])
        XCTAssertEqual(registry.taken(for: "dev.a"), [])

        try registry.set([TextExpansion(keyword: ";sig", command: "a9")], pluginID: "dev.a", pluginName: "A")
        XCTAssertEqual(registry.live.first?.command, "a9", "replacing keeps its place in line")
        try registry.set([], pluginID: "dev.a", pluginName: "A")
        XCTAssertEqual(registry.live.map(\.command), ["b1", "b2"], "letting go hands the keyword on")
        XCTAssertThrowsError(try registry.set([TextExpansion(keyword: "a b", command: "x")], pluginID: "dev.c", pluginName: "C"))
    }

    func testCallsNeedTheCapabilityAndStoppingLetsGo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = SimulatedSystem()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system))
        let keywords = [TextExpansion(keyword: ";sig", command: "sn-1")]

        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        for call: HostCall in [.setExpansions(keywords), .expansionStatus] {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without .textExpansion") }
            XCTAssertTrue(message.contains("add .textExpansion"), message)
        }
        guard case .value = await services.handle(.setExpansions([]), for: bare) else { return XCTFail("letting go needs nothing") }

        let granted = Manifest(id: "dev.test.snippets", name: "Snippets", capabilities: [.textExpansion])
        guard case .value(let json?) = await services.handle(.setExpansions(keywords), for: granted) else { return XCTFail("keywords refused") }
        let status = try SystemCodec.decode(ExpansionStatus.self, from: json)
        XCTAssertTrue(status.listening)
        XCTAssertEqual(status.keywords, 1)
        XCTAssertEqual(system.expansions.live.map(\.keyword), [";sig"])

        guard case .failure = await services.handle(.setExpansions([TextExpansion(keyword: "two words", command: "x")]), for: granted) else { return XCTFail("a bad keyword is refused") }
        services.release(pluginID: granted.id)
        XCTAssertTrue(system.expansions.isEmpty, "a stopped plugin's keywords go with it")
    }

    func testStatusRoundTrip() throws {
        let status = ExpansionStatus(listening: false, keywords: 3, turnedOff: true, needsAccessibility: true, secureInputApp: "1Password", taken: [";a"])
        XCTAssertEqual(try SystemCodec.decode(ExpansionStatus.self, from: SystemCodec.encode(status)), status)
    }
}
