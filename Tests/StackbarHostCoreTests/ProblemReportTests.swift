import Foundation
import XCTest
@testable import StackbarHostCore

final class ProblemReportTests: XCTestCase {
    private func fields(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testPrefillsTheBugForm() {
        let url = ProblemReport.issueURL(version: "0.23.0", macOS: "26.1", doctor: "✓ Swift toolchain\n✗ StackbarKit: missing & broken\n")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/navbytes/stackbar/issues/new")
        let fields = fields(url)
        XCTAssertEqual(fields["template"], "bug.yml")
        XCTAssertEqual(fields["version"], "0.23.0")
        XCTAssertEqual(fields["macos"], "26.1")
        XCTAssertEqual(fields["doctor"], "✓ Swift toolchain\n✗ StackbarKit: missing & broken")
    }

    func testCapsLongDoctorOutput() {
        let url = ProblemReport.issueURL(version: "1", macOS: "26", doctor: String(repeating: "x", count: 10_000))
        XCTAssertEqual(fields(url)["doctor"]?.count, 4000)
    }

    /// The ids the URL fills must stay in the bug form.
    func testFormHasTheFields() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let form = try String(contentsOf: root.appendingPathComponent(".github/ISSUE_TEMPLATE/bug.yml"), encoding: .utf8)
        for id in ["version", "macos", "doctor"] { XCTAssertTrue(form.contains("id: \(id)\n"), id) }
    }
}
