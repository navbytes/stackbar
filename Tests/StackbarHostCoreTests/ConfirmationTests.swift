import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Protocol 25: the host's "press again to confirm" (`ActionConfirmer`).
final class ConfirmationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_794_128_707)

    private func panel(prune: String = "remove 3 stopped containers") -> ViewNode {
        .section(title: nil, children: [
            .row(RowNode(key: "web", title: "web", subtitle: "running", actions: [
                ActionRef(id: "row/web/Open", title: "Open"),
                ActionRef(id: "row/web/Stop", title: "Stop", role: .critical, confirm: "stop web (pid 412)"),
            ])),
            .button(title: "Prune", role: .critical, action: "button/prune", confirm: prune),
            .tappable(.label("Reset", symbol: "arrow.counterclockwise"), action: "button/reset", confirm: "reset the session"),
            .button(title: "Refresh", action: "button/Refresh"),
        ])
    }

    func testTheFirstPressArmsAndTheSecondWithinTheWindowSends() {
        var confirmer = ActionConfirmer()
        guard case .armed(let arm) = confirmer.press("button/prune", surface: .panel, in: panel(), now: start) else {
            return XCTFail("the first press is held")
        }
        XCTAssertEqual(arm.prompt, "Press again within 10 s to remove 3 stopped containers")
        XCTAssertEqual(confirmer.press("button/prune", surface: .panel, in: panel(), now: start + 9), .send)
        XCTAssertNil(confirmer.arm, "sending disarms")
    }

    func testAnActionWithoutConfirmIsSentAndDisarms() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("button/prune", surface: .panel, in: panel(), now: start)
        XCTAssertEqual(confirmer.press("button/Refresh", surface: .panel, in: panel(), now: start + 1), .send)
        XCTAssertNil(confirmer.arm, "the user moved on")
        guard case .armed = confirmer.press("button/prune", surface: .panel, in: panel(), now: start + 2) else {
            return XCTFail("the old arm is gone, so this is a first press again")
        }
    }

    func testAPressAfterTheWindowArmsAgain() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("row/web/Stop", surface: .panel, in: panel(), now: start)
        guard case .armed(let again) = confirmer.press("row/web/Stop", surface: .panel, in: panel(), now: start + 10) else {
            return XCTFail("a stale arm counts as a first press")
        }
        XCTAssertEqual(again.at, start + 10)
    }

    func testExpiryDropsTheArmOnlyOnceItsDeadlinePasses() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("row/web/Stop", surface: .panel, in: panel(), now: start)
        XCTAssertFalse(confirmer.expire(now: start + 9.9))
        XCTAssertTrue(confirmer.expire(now: start + 10))
        XCTAssertNil(confirmer.arm)
        XCTAssertEqual(confirmer.decorate(panel(), surface: .panel), panel(), "nothing armed, nothing changed")
    }

    func testChangedTextMakesTheNextPressAFirstPress() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("button/prune", surface: .panel, in: panel(), now: start)
        let grown = panel(prune: "remove 4 stopped containers")
        guard case .armed(let arm) = confirmer.press("button/prune", surface: .panel, in: grown, now: start + 1) else {
            return XCTFail("the user never read the new count")
        }
        XCTAssertEqual(arm.text, "remove 4 stopped containers")
    }

    func testANewTreeDropsAnArmWhoseActionVanishedOrChanged() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("button/prune", surface: .panel, in: panel(), now: start)
        XCTAssertFalse(confirmer.rendered(panel(), surface: .panel), "the same tree keeps it")
        XCTAssertFalse(confirmer.rendered(.text("x"), surface: .window), "another surface's tree doesn't touch it")
        XCTAssertTrue(confirmer.rendered(panel(prune: "remove 4 stopped containers"), surface: .panel))
        XCTAssertNil(confirmer.arm)

        _ = confirmer.press("row/web/Stop", surface: .panel, in: panel(), now: start)
        XCTAssertTrue(confirmer.rendered(.section(title: nil, children: []), surface: .panel), "the row is gone")
    }

    func testTheSameIdOnAnotherSurfaceIsAFirstPress() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("button/prune", surface: .panel, in: panel(), now: start)
        guard case .armed = confirmer.press("button/prune", surface: .window, in: panel(), now: start + 1) else {
            return XCTFail("keyed by surface too")
        }
    }

    func testCancelForgetsTheArm() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("button/prune", surface: .panel, in: panel(), now: start)
        XCTAssertFalse(confirmer.cancel(surface: .window), "another surface closing leaves it")
        XCTAssertTrue(confirmer.cancel(surface: .panel))
        XCTAssertFalse(confirmer.cancel())
    }

    func testTheArmedControlSaysPressAgain() {
        var confirmer = ActionConfirmer()
        _ = confirmer.press("button/prune", surface: .panel, in: panel(), now: start)
        let drawn = confirmer.decorate(panel(), surface: .panel)
        XCTAssertTrue(drawn.affordances.contains { $0.title == "Press again to remove 3 stopped containers" })
        guard case .section(_, let children) = drawn, case .button(_, _, let role, let action, let confirm) = children[1] else {
            return XCTFail("the button stays a button")
        }
        XCTAssertEqual(role, .critical)
        XCTAssertEqual(action, "button/prune", "ids never change")
        XCTAssertEqual(confirm, "remove 3 stopped containers")
        XCTAssertEqual(confirmer.decorate(panel(), surface: .window), panel(), "only the armed surface")

        _ = confirmer.press("row/web/Stop", surface: .panel, in: panel(), now: start)
        let row = confirmer.decorate(panel(), surface: .panel).rows[0]
        XCTAssertEqual(row.subtitle, "Press again to stop web (pid 412)")
        XCTAssertEqual(row.actions.map(\.title), ["Open", "Press again to stop web (pid 412)"])
        XCTAssertEqual(row.actions.map(\.id), ["row/web/Open", "row/web/Stop"])

        _ = confirmer.press("button/reset", surface: .panel, in: panel(), now: start)
        let tappable = confirmer.decorate(panel(), surface: .panel)
        XCTAssertTrue(TreeTextRenderer.render(tappable).contains("Press again to reset the session"))
        XCTAssertEqual(tappable.actions, panel().actions)
    }

    func testConfirmIsOptionalOnTheWire() throws {
        let oldButton = #"{"button":{"title":"Go","role":"primary","action":"button/Go"}}"#
        guard case .button(_, _, _, _, let confirm) = try JSONDecoder().decode(ViewNode.self, from: Data(oldButton.utf8)) else {
            return XCTFail("a button")
        }
        XCTAssertNil(confirm)
        let oldRef = #"{"id":"row/a/Open","title":"Open","role":"primary"}"#
        XCTAssertNil(try JSONDecoder().decode(ActionRef.self, from: Data(oldRef.utf8)).confirm)
        let oldTappable = #"{"tappable":{"_0":{"divider":{}},"action":"button/x"}}"#
        guard case .tappable(_, _, let tapConfirm) = try JSONDecoder().decode(ViewNode.self, from: Data(oldTappable.utf8)) else {
            return XCTFail("a tappable")
        }
        XCTAssertNil(tapConfirm)

        let encoded = try JSONEncoder().encode(ViewNode.button(title: "Go", action: "button/Go"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("confirm"), "nil stays off the wire")
        let round = try JSONDecoder().decode(ViewNode.self, from: JSONEncoder().encode(panel()))
        XCTAssertEqual(round, panel())
        XCTAssertEqual(round.confirmations, [
            "row/web/Stop": "stop web (pid 412)",
            "button/prune": "remove 3 stopped containers",
            "button/reset": "reset the session",
        ])
    }

    func testSoakNeverPressesAnActionThatAsks() {
        let tree = ViewNode.section(title: nil, children: [
            .button(title: "Keep going", action: "button/keep"),
            .button(title: "Start new", action: "button/confirm", confirm: "end this session"),
        ])
        XCTAssertEqual(Soak.safeActions(in: tree), ["button/keep"])
    }

    func testTheAuthoringTextSaysWhatAsks() {
        let text = TreeTextRenderer.render(panel(), showActions: true)
        XCTAssertTrue(text.contains("Stop  {row/web/Stop} [asks: stop web (pid 412)]"), text)
        XCTAssertTrue(text.contains("(Prune) !critical  {button/prune} [asks: remove 3 stopped containers]") || text.contains("{button/prune} [asks: remove 3 stopped containers]"), text)
        XCTAssertFalse(TreeTextRenderer.render(panel(), showActions: false).contains("asks"), "agents read the panel without ids")
    }

    func testACommandViewAsksBeforeItsActionAndForgetsOnClose() {
        var view = CommandView(session: 1, pluginName: "Docker", query: CommandQuery())
        _ = view.open()
        _ = view.received(seq: 1, root: panel())
        guard case .armed = view.confirm("button/prune", now: start) else { return XCTFail("held") }
        XCTAssertTrue(view.shownRoot?.affordances.contains { $0.title.hasPrefix("Press again") } == true)
        XCTAssertEqual(view.confirm("button/prune", now: start + 1), .send)
        XCTAssertEqual(view.perform("button/prune"), [.event("button/prune", nil)])

        _ = view.confirm("button/prune", now: start + 2)
        XCTAssertTrue(view.cancelConfirmation(), "Esc")
        _ = view.confirm("button/prune", now: start + 3)
        _ = view.received(seq: 1, root: panel(prune: "remove 5 stopped containers"))
        XCTAssertNil(view.confirmer.arm, "a new answer that changes the text drops the arm")
        _ = view.confirm("button/prune", now: start + 4)
        _ = view.close()
        XCTAssertNil(view.confirmer.arm)
    }
}
