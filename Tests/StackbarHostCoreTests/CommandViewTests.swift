import Foundation
import StackbarProtocol
@testable import StackbarHostCore
import XCTest

/// The rules an open view command follows, shared by the palette and
/// headless runs.
final class CommandViewTests: XCTestCase {
    private func query(_ text: String) -> CommandQuery { CommandQuery(text: text) }
    private let list = ViewNode.list(children: [])

    private func form(error: String?) -> ViewNode {
        .form(FormNode(fields: [FormField(name: "name", label: "Name", kind: .text(placeholder: nil), error: error)], action: ActionID("view/1/form/new")))
    }

    func testTypingWhileAnAnswerIsPendingSendsOnlyTheNewest() {
        var view = CommandView(session: 1, pluginName: "P", query: query(""))
        XCTAssertEqual(view.open(), [.open(seq: 1, query: query(""))])
        XCTAssertEqual(view.change(query("a")), [], "one query in flight")
        XCTAssertEqual(view.change(query("ab")), [])
        XCTAssertTrue(view.isSearching)
        let first = view.received(seq: 1, root: list)
        XCTAssertEqual(first.sends, [.update(seq: 2, query: query("ab"))], "the newest goes next")
        XCTAssertTrue(view.received(seq: 2, root: list).shown)
        XCTAssertFalse(view.isSearching)
        XCTAssertFalse(view.received(seq: 1, root: list).shown, "an older tree never replaces a newer one")
        XCTAssertEqual(view.answers, 2)
    }

    func testASubmittedFormFinishesOnlyWithoutErrors() {
        var view = CommandView(session: 1, pluginName: "P", query: query(""))
        _ = view.open()
        _ = view.received(seq: 1, root: form(error: nil))
        let submit = ActionID("view/1/form/new")
        XCTAssertEqual(view.perform(submit, .fields(["name": .text("")])), [.event(submit, .fields(["name": .text("")]))])
        XCTAssertFalse(view.received(seq: 1, root: form(error: "Give it a name")).finished)
        _ = view.perform(submit, .fields(["name": .text("Docs")]))
        XCTAssertTrue(view.received(seq: 1, root: form(error: nil)).finished)
        XCTAssertFalse(view.received(seq: 1, root: form(error: nil)).finished, "once per submit")
        _ = view.perform(ActionID("view/1/button/x"))
        XCTAssertFalse(view.received(seq: 1, root: form(error: nil)).finished, "a button isn't a submit")
    }

    func testARestartWaitsAndOpensAgainWithTheNewestQuery() {
        var view = CommandView(session: 1, pluginName: "Notes", query: query("a"))
        _ = view.open()
        _ = view.received(seq: 1, root: list)
        XCTAssertEqual(view.pluginState(.restarting(attempt: 1, inSeconds: 0.2)), [])
        XCTAssertEqual(view.problem, "Notes restarted; reconnecting…")
        XCTAssertTrue(view.isSearching)
        XCTAssertFalse(view.canAct)
        XCTAssertEqual(view.change(query("ab")), [], "held until it runs")
        XCTAssertEqual(view.perform(ActionID("view/1/row/x")), [], "no handler in the new process yet")
        XCTAssertEqual(view.pluginState(.running), [.open(seq: 2, query: query("ab"))])
        XCTAssertNil(view.problem)
        XCTAssertEqual(view.pluginState(.running), [], "already open")
        XCTAssertFalse(view.received(seq: 1, root: list).shown, "a late tree from the old process is dropped")
        XCTAssertTrue(view.received(seq: 2, root: list).shown)
    }

    func testAStoppedViewSaysSoAndTakesNothing() {
        var view = CommandView(session: 1, pluginName: "Notes", query: query(""))
        _ = view.open()
        _ = view.pluginState(.failed("crashed"))
        XCTAssertEqual(view.problem, "Notes stopped: crashed")
        XCTAssertFalse(view.isSearching, "not searching forever")
        XCTAssertTrue(view.isStopped)
        _ = view.pluginState(.stopped)
        XCTAssertEqual(view.problem, "Notes is turned off")
        XCTAssertEqual(view.pluginState(.running), [.open(seq: 2, query: query(""))], "turned on again: it opens again")
    }

    func testClosingSendsOneCloseAndThenNothing() {
        var view = CommandView(session: 1, pluginName: "P", query: query(""))
        _ = view.open()
        XCTAssertEqual(view.close(), [.close])
        XCTAssertEqual(view.close(), [])
        XCTAssertEqual(view.change(query("x")), [])
        XCTAssertEqual(view.perform(ActionID("a")), [])
        XCTAssertFalse(view.received(seq: 1, root: list).shown)
        XCTAssertEqual(view.pluginState(.running), [])
    }
}
