import Foundation
import XCTest
@testable import FluidHostCore

final class SurfaceParityTests: XCTestCase {
    func testLedgerDocMatchesTheCode() throws {
        let doc = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/surface-parity.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        guard let start = text.range(of: "<!-- ledger:start -->\n"), let end = text.range(of: "\n<!-- ledger:end -->") else {
            return XCTFail("docs/surface-parity.md lost its ledger markers")
        }
        let current = String(text[start.upperBound..<end.lowerBound])
        let expected = SurfaceParity.ledger()
        XCTAssertEqual(current, expected, "docs/surface-parity.md is out of date. Paste this between the markers:\n\n\(expected)\n")
    }

    func testEveryNodeKindHasATreatmentEverywhere() {
        for kind in SurfaceParity.Kind.allCases {
            for column in SurfaceParity.Column.allCases {
                XCTAssertFalse(SurfaceParity.treatment(kind, on: column).isEmpty)
            }
        }
        XCTAssertEqual(SurfaceParity.Kind.allCases.count, 18)
    }
}
