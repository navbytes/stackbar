import XCTest
@testable import StackbarHostCore

/// Reported 2026-11-12: with PR Cockpit's Sign in with gh on, Stackbar kept
/// saying "Needs GITHUB_TOKEN" until a relaunch.
final class MissingSecretsTests: XCTestCase {
    func testAReadOfAnUnsetSecretFlagsItOnce() {
        var missing = MissingSecrets()
        XCTAssertTrue(missing.note(.asked("GITHUB_TOKEN")))
        XCTAssertFalse(missing.note(.asked("GITHUB_TOKEN")), "asked again, nothing changes")
        missing.note(.asked("OTHER"))
        XCTAssertEqual(missing.names, ["GITHUB_TOKEN", "OTHER"])
    }

    func testSavingClearsOnlyThatSecret() {
        var missing = MissingSecrets()
        missing.note(.asked("A"))
        missing.note(.asked("B"))
        missing.note(.saved("A"))
        XCTAssertEqual(missing.names, ["B"])
    }

    func testAnythingThatMayChangeWhatThePluginNeedsForgetsTheFlags() {
        for event in [MissingSecrets.Event.settingsChanged, .restarted, .reloaded, .turnedOff] {
            var missing = MissingSecrets()
            missing.note(.asked("GITHUB_TOKEN"))
            XCTAssertTrue(missing.note(event), "\(event)")
            XCTAssertEqual(missing.names, [], "\(event)")
            // A plugin that still needs it says so on its next read.
            missing.note(.asked("GITHUB_TOKEN"))
            XCTAssertEqual(missing.names, ["GITHUB_TOKEN"])
        }
    }
}
