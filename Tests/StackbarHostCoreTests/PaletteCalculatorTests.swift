import XCTest
@testable import StackbarHostCore

final class PaletteCalculatorTests: XCTestCase {
    private func result(_ query: String) -> String? {
        PaletteCalculator.answer(query)?.display
    }

    func testSums() {
        XCTAssertEqual(result("12*(3+4)"), "84")
        XCTAssertEqual(result("2^10"), "1024")
        XCTAssertEqual(result("10 / 4"), "2.5")
        XCTAssertEqual(result("1/3"), "0.3333333333")
        XCTAssertEqual(result("-2 + 5"), "3")
        XCTAssertEqual(result("15% * 80"), "12")
        XCTAssertEqual(result("sqrt(2)"), "1.414213562")
        XCTAssertEqual(result("2 x 3"), "6")
        XCTAssertEqual(result("1,000 + 1"), "1001")
        XCTAssertEqual(result("0.1 + 0.2"), "0.3")
    }

    func testNoAnswerForPlainNumbersWordsOrNonsense() {
        XCTAssertNil(result("42"), "a number alone is a search, not a sum")
        XCTAssertNil(result("docker"))
        XCTAssertNil(result("open 2 tabs"))
        XCTAssertNil(result("1/0"), "infinity is no answer")
        XCTAssertNil(result("(1+2"))
        XCTAssertNil(result(""))
    }

    func testUnitConversions() {
        XCTAssertEqual(result("3h in min"), "180 min")
        XCTAssertEqual(result("5 km to mi"), "3.106855961 mi")
        XCTAssertEqual(result("72 f to c"), "22.22222222 °C")
        XCTAssertEqual(result("100 c in f"), "212 °F")
        XCTAssertEqual(result("12 in to cm"), "30.48 cm")
        XCTAssertEqual(result("2 fl oz in ml"), "59.14705912 ml")
        XCTAssertEqual(result("1 GiB in MB"), "1073.741824 MB")
        XCTAssertEqual(result("(1+2) kg in lb"), "6.613867866 lb")
        XCTAssertEqual(PaletteCalculator.answer("3h in min")?.expression, "3 h → min")
        XCTAssertEqual(PaletteCalculator.answer("3h in min")?.result, "180")
    }

    func testConversionsAcrossKindsOrUnknownUnitsGetNoAnswer() {
        XCTAssertNil(result("5 km in kg"))
        XCTAssertNil(result("5 parsecs in m"))
        XCTAssertNil(result("meet in 5 min"))
    }
}
