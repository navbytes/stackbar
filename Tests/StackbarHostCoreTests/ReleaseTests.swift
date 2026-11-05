import Foundation
import XCTest
@testable import StackbarHostCore

/// What the Release workflow and Sparkle rely on.
final class ReleaseTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The release notes and the update window show this section.
    func testChangelogHasTheCurrentVersion() throws {
        let changelog = try read("CHANGELOG.md")
        XCTAssertTrue(changelog.contains("\n## \(StackbarVersion.current)\n"), "add a ## \(StackbarVersion.current) section to CHANGELOG.md")
    }

    /// Sparkle compares CFBundleVersion, so the app and widget carry the
    /// marketing version in both keys.
    func testXcodeProjectCarriesTheVersion() throws {
        let project = try read("project.yml")
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let lines = project.components(separatedBy: "\n").filter { $0.contains("\(key):") }
            XCTAssertEqual(lines.count, 2, key)
            for line in lines { XCTAssertTrue(line.hasSuffix("\"\(StackbarVersion.current)\""), line) }
        }
        XCTAssertTrue(project.contains("SUFeedURL: https://github.com/navbytes/stackbar/releases/latest/download/appcast.xml"))
    }
}
