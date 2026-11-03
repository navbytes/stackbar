import Foundation
import XCTest
@testable import StackbarHostCore

final class StoreSiteTests: XCTestCase {
    /// The shape `scripts/publish.sh` in navbytes/stackbar-plugins writes.
    let published = #"""
    {
      "about": {
        "dev.t.clock": {
          "description": "Every time zone you care about,\nat a glance.\n\nClick one to copy it.",
          "facts": [{"label": "Needs", "text": "nothing"}, {"label": "Surfaces", "text": "menu bar, panel"}],
          "version": "1.2.0"
        }
      },
      "format": 1,
      "plugins": {
        "dev.t.clock": {
          "1.2.0": {
            "menuBar": {"dark": "P/shots/dev.t.clock/1.2.0/dark/menuBar.png", "light": "P/shots/dev.t.clock/1.2.0/light/menuBar.png"},
            "panel": {"dark": "P/shots/dev.t.clock/1.2.0/dark/panel.png", "light": "P/shots/dev.t.clock/1.2.0/light/panel.png"},
            "widget": {"light": "P/shots/dev.t.clock/1.2.0/light/widget.png"}
          }
        }
      }
    }
    """#

    func testReadsWhatThePluginsRepoPublishes() throws {
        let site = try XCTUnwrap(StoreSite.decode(Data(published.utf8)))
        XCTAssertEqual(site.renders("dev.t.clock", version: "1.2.0").map(\.surface), ["panel", "widget", "menuBar"])
        XCTAssertEqual(site.thumbnail("dev.t.clock", version: "1.2.0")?.path(dark: true), "P/shots/dev.t.clock/1.2.0/dark/panel.png")
        let widget = try XCTUnwrap(site.plugins["dev.t.clock"]?["1.2.0"]?["widget"])
        XCTAssertEqual(widget.path(dark: true), widget.light, "a missing appearance falls back to the other")
        XCTAssertTrue(site.renders("dev.t.clock", version: "9.9.9").isEmpty)
        XCTAssertNil(site.thumbnail("dev.t.other", version: "1.2.0"))

        let about = try XCTUnwrap(site.about("dev.t.clock"))
        XCTAssertEqual(about.paragraphs, ["Every time zone you care about, at a glance.", "Click one to copy it."])
        XCTAssertEqual(about.facts.map(\.label), ["Needs", "Surfaces"])
    }

    func testRendersOnlySiteJSONStillReads() throws {
        // site.json from before READMEs were added to it.
        let old = #"{"format": 1, "plugins": {"dev.t.a": {"1.0.0": {"panel": {"light": "a.png"}}}}}"#
        let site = try XCTUnwrap(StoreSite.decode(Data(old.utf8)))
        XCTAssertNil(site.about("dev.t.a"))
        XCTAssertEqual(site.thumbnail("dev.t.a", version: "1.0.0")?.path(dark: false), "a.png")
    }

    func testUnknownFormatIsIgnored() throws {
        XCTAssertNil(try StoreSite.decode(Data(#"{"format": 2, "plugins": {}}"#.utf8)))
    }

    func testSitesJSONSitsBesideTheIndex() {
        XCTAssertEqual(StoreSite.url(beside: OfficialIndex.url).absoluteString, "https://navbytes.github.io/stackbar-plugins/site.json")
    }

    func testFetchesFromAFileStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let index = folder.appendingPathComponent("index.json")
        let missing = await StoreSite.fetch(beside: index)
        XCTAssertNil(missing, "a store without site.json still lists its plugins")
        try Data(published.utf8).write(to: folder.appendingPathComponent("site.json"))
        let site = await StoreSite.fetch(beside: index)
        XCTAssertNotNil(site?.about("dev.t.clock"))
    }

    func testWebPageMatchesTheSitesSlug() {
        XCTAssertEqual(OfficialIndex.webPage(for: "io.navbytes.stackbar.plugins.world-clock").absoluteString, "https://stackbar.navbytes.io/plugins/world-clock/")
        let entry = PluginIndex.Entry(id: "io.navbytes.stackbar.clipboard", name: "C", version: "1", publisher: "navbytes", bundle: "b", sha256: "0", capabilities: [])
        let official = PluginStore.Catalog(source: .init(url: OfficialIndex.url, isOfficial: true), index: PluginIndex(name: "O", plugins: [entry]))
        let other = PluginStore.Catalog(source: .init(url: URL(string: "https://example.com/index.json")!), index: PluginIndex(name: "X", plugins: [entry]))
        XCTAssertEqual(official.webPage(for: entry)?.absoluteString, "https://stackbar.navbytes.io/plugins/clipboard/")
        XCTAssertNil(other.webPage(for: entry), "only the official index has pages on the website")
    }

    func testFindsWhatAStoreLinkOpens() throws {
        func entry(_ id: String, _ version: String, minimum: String? = nil) -> PluginIndex.Entry {
            PluginIndex.Entry(id: id, name: id, version: version, publisher: "navbytes", bundle: "b", sha256: "0", capabilities: [], minimumStackbar: minimum)
        }
        let official = PluginStore.Catalog(source: .init(url: OfficialIndex.url, isOfficial: true),
                                           index: PluginIndex(name: "O", plugins: [entry("dev.t.a", "1.0.0"), entry("dev.t.a", "1.1.0"), entry("dev.t.a", "2.0.0", minimum: "99.0")]))
        let other = PluginStore.Catalog(source: .init(url: URL(string: "https://example.com/index.json")!), index: PluginIndex(name: "X", plugins: [entry("dev.t.a", "5.0.0"), entry("dev.t.b", "1.0.0")]))
        let found = try XCTUnwrap(PluginStore.find("dev.t.a", in: [official, other], running: "1.0.0"))
        XCTAssertTrue(found.catalog.source.isOfficial, "the first store that lists it wins")
        XCTAssertEqual(found.entry.version, "1.1.0", "the version the store row shows")
        XCTAssertEqual(PluginStore.find("dev.t.b", in: [official, other])?.catalog.index.name, "X")
        XCTAssertNil(PluginStore.find("dev.t.missing", in: [official, other]))
    }

    func testStoreLinks() throws {
        let link = try XCTUnwrap(StoreLink(URL(string: "stackbar://store/io.navbytes.stackbar.plugins.world-clock")!))
        XCTAssertEqual(link.pluginID, "io.navbytes.stackbar.plugins.world-clock")
        XCTAssertEqual(link.url.absoluteString, "stackbar://store/io.navbytes.stackbar.plugins.world-clock")
        XCTAssertEqual(StoreLink(URL(string: "STACKBAR://Store/dev.t.a")!)?.pluginID, "dev.t.a")
        for bad in ["stackbar://store/", "stackbar://store", "stackbar://commands/dev.t.a/run", "stackbar://store/a/b", "https://store/dev.t.a", "stackbar://store/a%20b"] {
            XCTAssertNil(StoreLink(URL(string: bad)!), bad)
        }
    }
}
