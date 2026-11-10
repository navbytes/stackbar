import Foundation
import XCTest
@testable import StackbarHostCore

/// What a build carries about its publisher (Distribution), and that an
/// upstream build is exactly navbytes' own.
final class DistributionTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// scripts/distribution.py writes Packaging/distribution.json into the
    /// app; the compiled-in fallback must say the same, or a test build and
    /// a release would trust different stores.
    func testUpstreamMatchesThePackagingFile() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Packaging/distribution.json"))
        XCTAssertEqual(try JSONDecoder().decode(Distribution.self, from: data), .upstream)
    }

    /// navbytes' store, key, team and feed, pinned: changing one of these is
    /// a release decision, not a side effect.
    func testUpstreamIsNavbytes() {
        let upstream = Distribution.upstream
        XCTAssertEqual(upstream.store.url.absoluteString, "https://navbytes.github.io/stackbar-plugins/index.json")
        XCTAssertEqual(upstream.store.publicKey, "4dpLtXEpFXdi+6cviY/KdYuUulJPbEmCxxIK0EEN2/w=")
        XCTAssertEqual(upstream.store.publisher, "navbytes")
        XCTAssertEqual(upstream.appGroup, "59J9RQXYYP.io.navbytes.stackbar")
        XCTAssertTrue(upstream.allowUserStores)
        XCTAssertEqual(upstream.updates.feed?.absoluteString, "https://github.com/navbytes/stackbar/releases/latest/download/appcast.xml")
        XCTAssertEqual(upstream.releasesURL.absoluteString, "https://github.com/navbytes/stackbar/releases")
        XCTAssertEqual(upstream.issuesURL.absoluteString, "https://github.com/navbytes/stackbar/issues")
    }

    /// Tests and `swift run` have no StackbarDistribution in their bundle.
    func testCurrentIsUpstreamOutsideAnApp() {
        XCTAssertEqual(Distribution.current, .upstream)
        XCTAssertEqual(OfficialIndex.url, Distribution.upstream.store.url)
        XCTAssertEqual(WidgetSnapshotStore.appGroup, Distribution.upstream.appGroup)
    }

    /// The Info.plist form: the merged JSON as one string.
    func testReadsTheInfoPlistValue() throws {
        let organization = Self.organization
        let text = String(decoding: try JSONEncoder().encode(organization), as: UTF8.self)
        XCTAssertEqual(Distribution.from(info: [Distribution.infoKey: text]), organization)
        XCTAssertNil(Distribution.from(info: [:]))
        XCTAssertNil(Distribution.from(info: nil))
        XCTAssertNil(Distribution.from(info: [Distribution.infoKey: "{}"]), "an incomplete value is not half-used")
    }

    /// An organization's store replaces navbytes' as the official one, gets
    /// its token, and can be the only store.
    func testOrganizationStore() {
        let organization = Self.organization
        let sources = PluginStore.sources(userURLs: ["https://example.com/a.json"], secret: { $0 == "CORP_STORE_TOKEN" ? "t0ken" : nil },
                                          distribution: organization)
        XCTAssertEqual(sources.map(\.url.absoluteString), ["https://plugins.corp.example/index.json"], "user stores are off")
        XCTAssertEqual(sources.first?.isOfficial, true)
        XCTAssertEqual(sources.first?.publicKey, organization.store.publicKey)
        XCTAssertEqual(StoreAuth.shared.authorization(for: URL(string: "https://plugins.corp.example/a/b.stackbarplugin")!), "Bearer t0ken")
        XCTAssertNil(StoreAuth.shared.authorization(for: URL(string: "https://example.com/index.json")!))

        var open = organization
        open.allowUserStores = true
        let both = PluginStore.sources(userURLs: ["https://example.com/a.json"], distribution: open)
        XCTAssertEqual(both.map(\.url.absoluteString), ["https://plugins.corp.example/index.json", "https://example.com/a.json"])
        StoreAuth.shared.set([:])
    }

    /// The app group follows the signing team.
    func testAppGroupFollowsTheTeam() {
        XCTAssertEqual(Self.organization.appGroup, "ABCDE12345.io.navbytes.stackbar")
    }

    static let organization = Distribution(
        teamID: "ABCDE12345",
        store: .init(name: "Corp Plugins", url: URL(string: "https://plugins.corp.example/index.json")!,
                     publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", publisher: "Example Corp",
                     repository: nil, website: nil, authSecret: "CORP_STORE_TOKEN"),
        allowUserStores: false,
        updates: .init(feed: nil, betaFeed: nil, manualNote: "Install updates from Self Service."),
        links: .init(website: nil, permissionsHelp: nil, repository: URL(string: "https://github.com/example-corp/stackbar")!))
}
