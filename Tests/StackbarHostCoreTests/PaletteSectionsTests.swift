import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class PaletteSectionsTests: XCTestCase {
    private func command(_ id: String) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: "p", pluginName: "P", title: id, kind: .command(CommandSpec(id: id, title: id)))
    }

    private func action(_ id: String) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: "p", pluginName: "P", title: id, kind: .action(ActionID(id), value: nil))
    }

    func testEmptyQueryGroupsRecentThenCommandsThenActions() {
        let results = [action("a1"), command("c1"), command("c2"), action("a2")]
        let sections = PaletteSection.group(results, query: "") { $0.title == "a1" }
        XCTAssertEqual(sections.map(\.title), ["Recent", "Commands", "Panel Actions"])
        XCTAssertEqual(sections.map { $0.entries.map(\.title) }, [["a1"], ["c1", "c2"], ["a2"]])
    }

    func testRecentIsCappedAndEmptyGroupsAreLeftOut() {
        let results = (1...4).map { command("c\($0)") }
        let sections = PaletteSection.group(results, query: " ", recentLimit: 2) { _ in true }
        XCTAssertEqual(sections.map(\.title), ["Recent", "Commands"])
        XCTAssertEqual(sections[0].entries.map(\.title), ["c1", "c2"])
    }

    func testATypedQueryKeepsOneRankedList() {
        let results = [action("a1"), command("c1")]
        let sections = PaletteSection.group(results, query: "x") { _ in true }
        XCTAssertEqual(sections, [PaletteSection(title: "Results", entries: results)])
        XCTAssertEqual(PaletteSection.group([], query: "x") { _ in true }, [])
    }

    func testFavoritesLeadAnEmptyQueryAndAreNotRepeated() {
        let results = [command("c1"), command("c2"), action("a1")]
        let sections = PaletteSection.group(results, query: "", favorites: [action("a1")]) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Favorites", "Commands"])
        XCTAssertEqual(sections.map { $0.entries.map(\.title) }, [["a1"], ["c1", "c2"]])
    }

    func testStoreSuggestionsFollowATypedQuery() {
        let store = [PaletteIndex.Entry(pluginID: "s", pluginName: "Store", title: "Docker", kind: .open("stackbar://store/s"))]
        let sections = PaletteSection.group([command("c1")], query: "do", store: store) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Results", "From the Store"])
        XCTAssertEqual(PaletteSection.group([], query: "do", store: store) { _ in false }.map(\.title), ["From the Store"])
        XCTAssertEqual(PaletteSection.group([], query: "", store: store) { _ in false }, [], "no store rows before typing")
    }

    func testFavoritesTogglePersistAndSkipEntriesThatAreGone() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("favorites-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let favorites = PaletteFavorites(file: file)
        XCTAssertTrue(favorites.toggle("p/c2"))
        XCTAssertTrue(favorites.toggle("p/gone"))
        XCTAssertTrue(favorites.toggle("p/c1"))
        XCTAssertFalse(favorites.toggle("p/gone"))
        let reloaded = PaletteFavorites(file: file)
        XCTAssertEqual(reloaded.ids, ["p/c2", "p/c1"])
        XCTAssertEqual(reloaded.entries(in: [command("c1"), command("c2"), command("c3")]).map(\.title), ["c2", "c1"])
    }

    func testStoreSuggestionsSkipInstalledPluginsAndShortQueries() {
        func listing(_ id: String, _ name: String, summary: String) -> PluginIndex.Entry {
            var entry = PluginIndex.Entry(id: id, name: name, version: "1.0.0", publisher: "n", bundle: "b", sha256: "0", capabilities: [])
            entry.summary = summary
            entry.symbol = "shippingbox"
            return entry
        }
        let catalog = PluginStore.Catalog(source: .init(url: URL(string: "https://example.com/index.json")!), index: PluginIndex(name: "X", plugins: [
            listing("dev.t.docker", "Docker", summary: "Containers at a glance"),
            listing("dev.t.ports", "Ports", summary: "Who is listening"),
            listing("dev.t.dock", "Dock Tools", summary: "Tweak the Dock"),
        ]))
        let installed = StoreListing.Installed(versions: ["dev.t.dock": "1.0.0"])
        let found = StoreListing.paletteSuggestions([catalog], query: "dock", installed: installed)
        XCTAssertEqual(found.map(\.title), ["Docker"], "installed plugins are not suggested")
        XCTAssertEqual(found.first?.kind, .open("stackbar://store/dev.t.docker"))
        XCTAssertEqual(found.first?.symbol, "shippingbox")
        XCTAssertEqual(StoreListing.paletteSuggestions([catalog], query: "contain", installed: installed).map(\.title), ["Docker"], "a summary word matches")
        XCTAssertEqual(StoreListing.paletteSuggestions([catalog], query: "d", installed: installed), [])
    }

    private func app(_ name: String) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: "app", pluginName: "Application", title: name, kind: .open("file:///Applications/\(name).app"))
    }

    func testPluginSectionsLeadOnlyOnAPrefixMatch() {
        let apps = PaletteSection(title: "Applications", entries: [app("Safari")])
        let sum = PaletteSection(title: "Calculator", entries: [action("2+2 = 4")])
        let lead = PaletteSection.group([command("safe mode")], query: "saf", plugins: [apps]) { _ in false }
        XCTAssertEqual(lead.map(\.title), ["Applications", "Results"])
        XCTAssertEqual(PaletteSection.group([], query: "2+2", plugins: [apps, sum]) { _ in false }.map(\.title), ["Calculator", "Applications"])
        let follow = PaletteSection.group([command("notes")], query: "nts", plugins: [PaletteSection(title: "Applications", entries: [app("Notes")])]) { _ in false }
        XCTAssertEqual(follow.map(\.title), ["Results", "Applications"], "a fuzzy match goes after the command results")
    }

    func testMatchingRanksByNameThenUse() {
        let apps = [app("Safari"), app("Stocks"), app("Notes")]
        XCTAssertEqual(PaletteIndex.Entry.matching(apps, query: "saf").map(\.title), ["Safari"])
        XCTAssertEqual(PaletteIndex.Entry.matching(apps, query: "nts").map(\.title), ["Notes"])
        XCTAssertEqual(PaletteIndex.Entry.matching(apps, query: " "), [])
        var withKeyword = app("Visual Studio Code")
        withKeyword.keywords = ["vscode"]
        XCTAssertEqual(PaletteIndex.Entry.matching([withKeyword], query: "vscode").map(\.title), ["Visual Studio Code"])
    }

    func testFoundFilesSkipBundlesHiddenAndLibraryAndShortenHome() {
        let home = "/Users/n"
        let file = FileSearchFilter.found(path: "/Users/n/Documents/Q3 plan.pdf", home: home)
        XCTAssertEqual(file?.name, "Q3 plan.pdf")
        XCTAssertEqual(file?.folder, "~/Documents")
        XCTAssertEqual(FileSearchFilter.found(path: "/Users/n/plan.txt", home: home)?.folder, "~")
        XCTAssertNil(FileSearchFilter.found(path: "/Applications/Plan.app", home: home))
        XCTAssertNil(FileSearchFilter.found(path: "/Applications/Plan.app/Contents/Info.plist", home: home))
        XCTAssertNil(FileSearchFilter.found(path: "/Users/n/.config/plan.toml", home: home))
        XCTAssertNil(FileSearchFilter.found(path: "/Users/n/Library/Caches/plan.db", home: home))
        XCTAssertNil(FileSearchFilter.found(path: "/Users/n/code/x/node_modules/plan/index.js", home: home))
        XCTAssertNotNil(FileSearchFilter.found(path: "/Users/n/Library", home: home), "the Library folder itself is fine")
        XCTAssertEqual(FileSearchFilter.abbreviate("/Volumes/Data/plan", home: home), "/Volumes/Data/plan")
    }

    func testPluginRowsFollowResultsAndFallbacksComeLast() {
        let clipboard = PaletteSection(title: "Clipboard History", entries: [action("clip")])
        let store = [PaletteIndex.Entry(pluginID: "s", pluginName: "Store", title: "Hello", kind: .open("stackbar://store/s"))]
        let sections = PaletteSection.group([command("c1"), command("web")], query: "hello", store: store,
                                            plugins: [clipboard], fallbacks: [command("web"), command("ddg")]) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Results", "Clipboard History", "From the Store", PaletteSection.fallbackTitle("hello")])
        // A fallback the search found stays in Results only.
        XCTAssertEqual(sections.last?.entries.map(\.title), ["ddg"])
        XCTAssertEqual(PaletteSection.fallbackTitle("hello"), "Use \u{201C}hello\u{201D} with")
    }

    func testFallbacksAndPluginRowsWaitForAQuery() {
        let sections = PaletteSection.group([command("c1")], query: "", plugins: [PaletteSection(title: "X", entries: [action("x")])],
                                            fallbacks: [command("web")]) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Commands"])
    }
}
