import XCTest
@testable import StackbarHostCore

final class MacOSAlternativesTests: XCTestCase {
    func testEveryItemSaysHowAndLinksASettingsPane() {
        XCTAssertGreaterThanOrEqual(MacOSAlternatives.items.count, 4)
        XCTAssertEqual(Set(MacOSAlternatives.items.map(\.title)).count, MacOSAlternatives.items.count, "titles identify rows")
        for item in MacOSAlternatives.items {
            XCTAssertFalse(item.how.isEmpty)
            if let settings = item.settings {
                XCTAssertTrue(settings.hasPrefix("x-apple.systempreferences:com.apple."), settings)
                XCTAssertTrue(settings.hasSuffix("-Settings.extension"), settings)
            }
        }
        XCTAssertTrue(MacOSAlternatives.items.contains { $0.title.contains("abbreviations") }, "Text Replacements stand in for keyword expansion")
    }
}
