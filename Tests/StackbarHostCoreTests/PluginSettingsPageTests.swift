import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

/// The plugin Settings page: what it says the plugin is doing, how it shows
/// declared secrets, and how it helps with a long settings surface.
final class PluginSettingsPageTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Activity line

    func testAChangeReadsApplyingUntilThePluginHandlesIt() {
        var activity = PluginActivity()
        activity.rendered(at: start)
        activity.settingChanged(target: 7, settled: 5, at: start)
        XCTAssertEqual(activity.line(now: start.addingTimeInterval(1), isRunning: true)?.kind, .applying)
        XCTAssertEqual(activity.line(now: start.addingTimeInterval(6), isRunning: true)?.kind, .slow)
        // Message 6 (a timer tick ahead of it) is not the change.
        activity.settled(count: 6)
        XCTAssertEqual(activity.line(now: start.addingTimeInterval(6), isRunning: true)?.kind, .slow)
        activity.settled(count: 7)
        XCTAssertEqual(activity.line(now: start.addingTimeInterval(7), isRunning: true)?.kind, .updated)
    }

    func testAChangeAlreadyHandledNeverShowsApplying() {
        var activity = PluginActivity()
        activity.settingChanged(target: 3, settled: 3, at: start)
        XCTAssertNil(activity.applyingSince)
    }

    func testAChangeThatNeverFinishesSaysSoInsteadOfSpinningForever() {
        var activity = PluginActivity()
        activity.settingChanged(target: 2, settled: 0, at: start)
        let line = activity.line(now: start.addingTimeInterval(PluginActivity.giveUpAfter + 1), isRunning: true)
        XCTAssertEqual(line?.kind, .problem)
        XCTAssertNil(activity.problem, "a stuck change offers Restart, not Try Again")
    }

    func testAFailedHandlerBecomesAPlainProblemUntilTheNextChange() {
        var activity = PluginActivity()
        activity.settingChanged(target: 2, settled: 1, at: start)
        activity.logged(.error, "action settings/useGh failed: gh is not installed", at: start)
        activity.settled(count: 2)
        let line = activity.line(now: start.addingTimeInterval(120), isRunning: true)
        XCTAssertEqual(line?.kind, .problem)
        XCTAssertEqual(line?.text, "Couldn't apply that: gh is not installed")
        XCTAssertEqual(line?.detail, "2 min ago")
        activity.settingChanged(target: 3, settled: 3, at: start)
        XCTAssertNil(activity.problem)
    }

    func testRefreshErrorsReadPlainlyAndWarningsAreIgnored() {
        var activity = PluginActivity()
        activity.logged(.warning, "no handler for action x", at: start)
        XCTAssertNil(activity.problem)
        activity.logged(.error, "refresh failed: GitHub answered 401", at: start)
        XCTAssertEqual(activity.problem?.message, "Couldn't refresh: GitHub answered 401")
        activity.logged(.error, "something odd", at: start)
        XCTAssertEqual(activity.problem?.message, "something odd")
    }

    func testARestartForgetsTheOldHelpersProblemAndChange() {
        var activity = PluginActivity()
        activity.settingChanged(target: 9, settled: 1, at: start)
        activity.logged(.error, "refresh failed: boom", at: start)
        activity.restarted()
        XCTAssertNil(activity.problem)
        XCTAssertNil(activity.applyingSince)
    }

    func testNothingIsSaidWhileNotRunningOrBeforeTheFirstDraw() {
        let activity = PluginActivity()
        XCTAssertNil(activity.line(now: start, isRunning: false))
        XCTAssertEqual(activity.line(now: start, isRunning: true)?.kind, .waiting)
    }

    func testAgo() {
        XCTAssertEqual(PluginActivity.ago(start, now: start.addingTimeInterval(10)), "just now")
        XCTAssertEqual(PluginActivity.ago(start, now: start.addingTimeInterval(90)), "2 min ago")
        XCTAssertEqual(PluginActivity.ago(start, now: start.addingTimeInterval(7_300)), "2 h ago")
        XCTAssertEqual(PluginActivity.ago(start, now: start.addingTimeInterval(90_000)), "yesterday")
        XCTAssertEqual(PluginActivity.ago(start, now: start.addingTimeInterval(-5)), "just now")
    }

    // MARK: Secrets

    func testOnlySecretsThePluginAskedForAreNeeded() {
        // Ask AI declares a key per provider; the user's provider is set.
        let declared = ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY", "LITELLM_API_KEY"]
        let none = SettingsPresentation.secretGroups(declared: declared, missing: [])
        XCTAssertEqual(none.needed, [])
        XCTAssertEqual(none.other, declared)
        let asked = SettingsPresentation.secretGroups(declared: declared, missing: ["OPENAI_API_KEY"])
        XCTAssertEqual(asked.needed, ["OPENAI_API_KEY"])
        XCTAssertEqual(asked.other.count, 3)
    }

    func testAnUnsetSecretNobodyAskedForIsNotAWarning() {
        XCTAssertFalse(SettingsPresentation.secretState(isSaved: false, isNeeded: false).isWarning)
        XCTAssertTrue(SettingsPresentation.secretState(isSaved: false, isNeeded: true).isWarning)
        XCTAssertEqual(SettingsPresentation.secretState(isSaved: true, isNeeded: true).text, "Saved")
    }

    // MARK: Long settings

    private func section(_ title: String, _ children: [ViewNode]) -> ViewNode {
        .section(title: title, children: children)
    }

    private var longTree: ViewNode {
        .stack(axis: .vertical, children: [
            section("Sign-in", [.toggle(title: "Sign in with gh", isOn: true, action: ActionID("a")), .text("Uses the token of the gh command-line tool")]),
            section("What to show", [.picker(title: "Updated within", options: ["Any time", "30 days"], selection: nil, action: ActionID("b"))]),
            section("Missing pull requests?", [.textField(placeholder: "Always check a repository (owner/name)", text: "", action: ActionID("c"))]),
            section("Notifications", [.toggle(title: "Notify me about changes", isOn: false, action: ActionID("d"))]),
            .text("A loose caption"),
            section("Server", [.labeled(label: "Server", value: "github.example.com")]),
        ])
    }

    func testAShortPageGetsNoOutline() {
        let outline = PluginSettingsOutline(.stack(axis: .vertical, children: [section("A", []), section("B", [])]))
        XCTAssertFalse(outline.isLong)
        XCTAssertFalse(PluginSettingsOutline(section("Only", [])).isLong)
    }

    func testALongPageListsItsTitledSections() {
        let outline = PluginSettingsOutline(longTree)
        XCTAssertTrue(outline.isLong)
        XCTAssertEqual(outline.titled.compactMap(\.title), ["Sign-in", "What to show", "Missing pull requests?", "Notifications", "Server"])
        XCTAssertEqual(outline.parts.count, 6)
        XCTAssertNil(outline.parts[4].title)
    }

    func testTheFilterFindsControlsCaptionsAndOptions() {
        let outline = PluginSettingsOutline(longTree)
        XCTAssertEqual(outline.filtered("gh").map(\.title), ["Sign-in"])
        XCTAssertEqual(outline.filtered("30 DAYS").map(\.title), ["What to show"])
        XCTAssertEqual(outline.filtered("owner repository").map(\.title), ["Missing pull requests?"])
        XCTAssertEqual(outline.filtered("example.com").map(\.title), ["Server"])
        XCTAssertEqual(outline.filtered("").count, 6)
        XCTAssertEqual(outline.filtered("nothing like this"), [])
    }

    func testFoldsAreRememberedPerPlugin() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PluginSettingsPageTests-\(UUID().uuidString)"))
        PluginSettingsFolds.save(["Server", "Notifications"], for: "a.plugin", defaults: defaults)
        XCTAssertEqual(PluginSettingsFolds.load("a.plugin", defaults: defaults), ["Server", "Notifications"])
        XCTAssertEqual(PluginSettingsFolds.load("b.plugin", defaults: defaults), [])
        PluginSettingsFolds.save([], for: "a.plugin", defaults: defaults)
        XCTAssertEqual(PluginSettingsFolds.load("a.plugin", defaults: defaults), [])
    }
}
