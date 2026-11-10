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
        let feed = try XCTUnwrap(Distribution.upstream.updates.feed)
        XCTAssertTrue(project.contains("SUFeedURL: \(feed.absoluteString)"), "project.yml and Packaging/distribution.json name the same feed")
    }

    /// The release has no provisioning profile, so the app group must be the
    /// macOS-style one that starts with the team id: a `group.` id leaves the
    /// sandboxed widget without the container and its plugin list empty.
    func testAppGroupNeedsNoProvisioningProfile() throws {
        let project = try read("project.yml")
        let team = try XCTUnwrap(project.components(separatedBy: "\n").first { $0.contains("DEVELOPMENT_TEAM:") }?
            .components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces))
        let group = WidgetSnapshotStore.appGroup
        XCTAssertTrue(group.hasPrefix(team + "."), group)
        let claims = project.components(separatedBy: "\n").filter { $0.contains("com.apple.security.application-groups:") }
        XCTAssertEqual(claims.count, 2, "the app and the widget both claim the group")
        for claim in claims { XCTAssertTrue(claim.hasSuffix("[\(group)]"), claim) }
        XCTAssertTrue(try read("Packaging/Stackbar.entitlements").contains("<string>\(group)</string>"))
        XCTAssertFalse(project.contains("group.io.navbytes"))
    }
}
