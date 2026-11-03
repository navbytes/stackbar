import Foundation
import XCTest
@testable import StackbarHostCore

final class StoreListingTests: XCTestCase {
    func entry(_ id: String, _ version: String, category: String? = "Productivity", updated: String? = nil, minimum: String? = nil) -> PluginIndex.Entry {
        PluginIndex.Entry(id: id, name: String(id.split(separator: ".").last!), version: version, publisher: "navbytes", bundle: "b", sha256: "0",
                          capabilities: [], category: category, minimumStackbar: minimum, updated: updated)
    }

    lazy var official = PluginStore.Catalog(source: .init(url: OfficialIndex.url, isOfficial: true), index: PluginIndex(name: "O", plugins: [
        entry("dev.t.zebra", "1.0.0", updated: "2026-11-01"),
        entry("dev.t.alpha", "1.0.0", category: "Developer", updated: "2026-10-01"),
        entry("dev.t.alpha", "1.1.0", category: "Developer", updated: "2026-11-02"),
        entry("dev.t.beta", "2.0.0", category: "Developer", updated: "2026-11-03", minimum: "99.0"),
        entry("dev.t.misc", "1.0.0", category: nil),
    ]))
    lazy var other = PluginStore.Catalog(source: .init(url: URL(string: "https://example.com/index.json")!),
                                         index: PluginIndex(name: "X", plugins: [entry("dev.t.zebra", "3.0.0", category: "Fun", updated: "2026-11-03")]))

    func testListsEveryStoreByName() {
        let items = StoreListing.all([official, other], running: "1.0.0")
        XCTAssertEqual(items.map(\.entry.name), ["alpha", "beta", "misc", "zebra", "zebra"])
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "the same plugin in two stores still gets its own row")
        XCTAssertEqual(items.first?.entry.version, "1.1.0")
    }

    func testFiltersByCategoryInstalledAndUpdates() {
        let installed = StoreListing.Installed(versions: ["dev.t.alpha": "1.0.0", "dev.t.beta": "1.0.0", "dev.t.zebra": "1.0.0"], loaded: ["dev.t.misc"])
        func names(_ filter: StoreListing.Filter, category: String? = nil, query: String = "") -> [String] {
            StoreListing.items([official], query: query, category: category, filter: filter, installed: installed, running: "1.0.0").map(\.entry.name)
        }
        XCTAssertEqual(names(.all, category: "Developer"), ["alpha", "beta"])
        XCTAssertEqual(names(.all, category: "Other"), ["misc"])
        XCTAssertEqual(names(.installed), ["alpha", "beta", "misc", "zebra"])
        XCTAssertEqual(names(.updates), ["alpha"], "beta's update needs a newer Stackbar, zebra is current")
        XCTAssertEqual(names(.all, query: "zeb"), ["zebra"])
    }

    func testCategoriesFollowTheSitesOrder() {
        XCTAssertEqual(StoreListing.categories([official, other], running: "1.0.0"), ["Productivity", "Developer", "Fun", "Other"])
    }

    func testRecentIsNewestFirstAndOnePerPlugin() {
        let now = ISO8601DateFormatter().date(from: "2026-11-04T00:00:00Z")!
        let recent = StoreListing.recent([official, other], now: now, days: 14, running: "1.0.0")
        XCTAssertEqual(recent.map { "\($0.entry.name) \($0.entry.version)" }, ["beta 2.0.0", "zebra 3.0.0", "alpha 1.1.0"])
        XCTAssertTrue(StoreListing.recent([official], now: now, days: 1, running: "1.0.0").map(\.entry.name) == ["beta"])
    }

    func testReleaseNotesForAVersion() throws {
        let json = #"{"format":1,"plugins":{},"about":{"dev.t.a":{"description":"d","facts":[],"changes":[{"version":"1.2.0","notes":["Faster","Fixed"]},{"version":"1.1.0","notes":[]}]}}}"#
        let about = try XCTUnwrap(StoreSite.decode(Data(json.utf8))?.about("dev.t.a"))
        XCTAssertEqual(about.notes(for: "1.2.0"), ["Faster", "Fixed"])
        XCTAssertNil(about.notes(for: "1.1.0"), "an empty section has nothing to show")
        XCTAssertNil(about.notes(for: "9.0.0"))
    }

    func testFeaturedIsTheNewestPluginNotInstalled() {
        XCTAssertEqual(StoreListing.featured([official], running: "1.0.0")?.entry.name, "alpha",
                       "beta is newer but needs a newer Stackbar")
        let installed = StoreListing.Installed(versions: ["dev.t.alpha": "1.1.0"])
        XCTAssertEqual(StoreListing.featured([official], installed: installed, running: "1.0.0")?.entry.name, "zebra")
        let everything = StoreListing.Installed(versions: ["dev.t.alpha": "1", "dev.t.beta": "1", "dev.t.zebra": "1", "dev.t.misc": "1"])
        XCTAssertEqual(StoreListing.featured([official], installed: everything, running: "1.0.0")?.entry.name, "beta")
        XCTAssertNil(StoreListing.featured([], running: "1.0.0"))
    }
}
