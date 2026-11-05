import XCTest
@testable import StackbarHostCore

final class SpotlightReplacementsTests: XCTestCase {
    func testEveryItemSaysHowAndNamesAStorePlugin() {
        XCTAssertGreaterThanOrEqual(SpotlightReplacements.items.count, 6)
        XCTAssertEqual(Set(SpotlightReplacements.items.map(\.title)).count, SpotlightReplacements.items.count, "titles identify rows")
        for item in SpotlightReplacements.items {
            XCTAssertFalse(item.how.isEmpty)
            XCTAssertTrue(item.pluginID.hasPrefix("io.navbytes.stackbar."), item.pluginID)
        }
        XCTAssertTrue(SpotlightReplacements.items.contains { $0.pluginID == "io.navbytes.stackbar.plugins.system-commands" })
        XCTAssertTrue(BundledStore.corePluginIDs.isSubset(of: Set(SpotlightReplacements.items.map(\.pluginID))), "the core plugins are each explained")
    }
}
