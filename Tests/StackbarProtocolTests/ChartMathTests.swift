import XCTest
import StackbarProtocol

final class ChartMathTests: XCTestCase {
    func testNumbersAreShortened() {
        XCTAssertEqual(ChartNumber.format(3), "3")
        XCTAssertEqual(ChartNumber.format(3.46), "3.5")
        XCTAssertEqual(ChartNumber.format(9_999), "9999")
        XCTAssertEqual(ChartNumber.format(12_345), "12.3K")
        XCTAssertEqual(ChartNumber.format(174_400_000), "174.4M")
        XCTAssertEqual(ChartNumber.format(750_000_000), "750M")
        XCTAssertEqual(ChartNumber.format(1_940_000_000), "1.9B")
        XCTAssertEqual(ChartNumber.format(-2_500_000), "-2.5M")
    }

    func testHeatmapEndsOnTodaysRow() {
        // Ten days ending on a Wednesday (row 3) start on the Monday of the
        // week before.
        let layout = HeatmapLayout(count: 10, todayRow: 3)
        XCTAssertEqual(layout.columns, 2)
        XCTAssertTrue(layout.cell(0) == (0, 1))
        XCTAssertTrue(layout.cell(9) == (1, 3))
        XCTAssertEqual(HeatmapLayout(count: 1, todayRow: 6).columns, 1)
        XCTAssertEqual(HeatmapLayout(count: 0, todayRow: 0).columns, 1)
    }

    func testHeatmapLevelsUseQuartilesOfActiveDays() {
        XCTAssertEqual(HeatmapLayout.levels([0, 1, 2, 3, 4, 1000]), [0, 1, 1, 2, 3, 4])
        XCTAssertEqual(HeatmapLayout.levels([0, 0]), [0, 0])
    }
}
