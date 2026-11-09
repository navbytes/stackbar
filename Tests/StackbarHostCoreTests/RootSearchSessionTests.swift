import Foundation
import StackbarProtocol
@testable import StackbarHostCore
import XCTest

@MainActor
final class FakeRootView: RootSearchView {
    let entry: CommandRegistry.Entry
    var query: String { didSet { if query != oldValue { sent.append(query); isSearching = true } } }
    var isSearching = true
    var isStopped = false
    var isClosed = false
    var root: ViewNode?
    var answers = 0
    var answeredAt: Date?
    var sent: [String] = []

    init(_ entry: CommandRegistry.Entry, query: String) {
        self.entry = entry
        self.query = query
    }

    func answer(_ titles: [String], at time: Date? = nil) {
        root = .list(children: titles.map { .row(RowNode(key: $0, title: $0, actions: [ActionRef(id: ActionID("row/\($0)/\(answers)"), title: "Open")])) })
        answers += 1
        answeredAt = time
        isSearching = false
    }

    func close() { isClosed = true }
}

@MainActor
final class RootSearchSessionTests: XCTestCase {
    private func command(_ id: String, pattern: String? = nil) -> CommandRegistry.Entry {
        CommandRegistry.Entry(pluginID: "dev.t.\(id)", pluginName: id, spec: CommandSpec(id: id, title: id, kind: .view, rootSearch: true, rootPattern: pattern))
    }

    private let accepts: (CommandRegistry.Entry, String) -> Bool = { RootSearchGate.accepts($0.spec, text: $1) }

    /// A session whose opener hands back fake views at once, and the views.
    private func session(clock: @escaping () -> Date = Date.init) -> (RootSearchSession<FakeRootView>, () -> [FakeRootView], RootSearchSession<FakeRootView>.Opener) {
        let session = RootSearchSession<FakeRootView>(budget: RootSearchBudget(limit: 0.4, strikes: 2, bench: 600), now: clock)
        var made: [FakeRootView] = []
        let open: RootSearchSession<FakeRootView>.Opener = { entry, text in
            let view = FakeRootView(entry, query: text)
            made.append(view)
            return view
        }
        return (session, { made }, open)
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    func testSearchTextNeedsTwoCharactersAtTheRoot() {
        XCTAssertEqual(RootSearchSession<FakeRootView>.searchText(" ab ", atRoot: true), "ab")
        XCTAssertNil(RootSearchSession<FakeRootView>.searchText("a", atRoot: true))
        XCTAssertNil(RootSearchSession<FakeRootView>.searchText("abc", atRoot: false))
    }

    func testOpensMatchingViewsAndClosesOnesThatStopMatching() async {
        let (session, made, open) = session()
        let calc = command("calc", pattern: "[0-9+*/ ()-]+")
        let apps = command("apps")
        session.feed("12", commands: [calc, apps], accepts: accepts, canOpen: { _ in true }, open: open)
        await settle()
        XCTAssertEqual(Set(session.views.keys), [calc.key, apps.key])

        session.feed("sl", commands: [calc, apps], accepts: accepts, canOpen: { _ in true }, open: open)
        XCTAssertEqual(Array(session.views.keys), [apps.key], "calc's pattern no longer matches")
        XCTAssertTrue(made().first { $0.entry == calc }!.isClosed)
        XCTAssertEqual(made().first { $0.entry == apps }!.sent, ["sl"])

        session.feed(nil, commands: [calc, apps], accepts: accepts, canOpen: { _ in true }, open: open)
        XCTAssertTrue(session.views.isEmpty)
        XCTAssertEqual(session.rows(), [])
    }

    func testAPluginThatIsNotRunningIsNotStarted() async {
        let (session, made, open) = session()
        session.feed("sl", commands: [command("apps")], accepts: accepts, canOpen: { _ in false }, open: open)
        await settle()
        XCTAssertTrue(made().isEmpty)
    }

    func testAViewThatOpensAfterTheTextMovedOnIsDropped() async {
        let session = RootSearchSession<FakeRootView>(budget: RootSearchBudget())
        let calc = command("calc", pattern: "[0-9]+")
        var pending: CheckedContinuation<Void, Never>?
        var made: FakeRootView?
        let open: RootSearchSession<FakeRootView>.Opener = { entry, text in
            await withCheckedContinuation { pending = $0 }
            made = FakeRootView(entry, query: text)
            return made
        }
        session.feed("12", commands: [calc], accepts: accepts, canOpen: { _ in true }, open: open)
        await settle()
        session.feed("ab", commands: [calc], accepts: accepts, canOpen: { _ in true }, open: open)
        pending?.resume()
        await settle()
        XCTAssertTrue(session.views.isEmpty, "the pattern stopped matching while it opened")
        XCTAssertEqual(made?.isClosed, true)
    }

    func testAnswersAreTimedFromWhenTheTextWentOutToWhenTheyArrived() async {
        var clock = Date(timeIntervalSince1970: 0)
        let (session, made, open) = session(clock: { clock })
        let apps = command("apps")
        session.feed("sl", commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
        await settle()
        let view = made()[0]
        for typed in ["sla", "slac"] {
            session.feed(typed, commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
            view.answer(["Slack"], at: clock.addingTimeInterval(1))
            // Read much later (a redraw): the answer's own arrival counts.
            clock = clock.addingTimeInterval(30)
            _ = session.rows()
        }
        XCTAssertTrue(session.budget.isBenched(apps.key, now: clock), "two answers a second late bench it")

        session.feed("slack", commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
        XCTAssertTrue(session.views.isEmpty, "a benched command's view closes")
    }

    func testRowsAreFilteredOncePerAnswer() async {
        let (session, made, open) = session()
        let apps = command("apps")
        session.feed("sl", commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
        await settle()
        let view = made()[0]
        view.answer(["Slack", "Slides"])
        XCTAssertEqual(session.rows().first?.rows.map(\.key), ["Slack", "Slides"])
        view.root = .list(children: [])
        XCTAssertEqual(session.rows().first?.rows.map(\.key), ["Slack", "Slides"], "same answer, same text: the filtered rows are kept")
        view.answer(["Slack"])
        XCTAssertEqual(session.rows().first?.rows.map(\.key), ["Slack"])
        view.isStopped = true
        XCTAssertEqual(session.rows(), [], "a stopped view shows nothing")
    }

    func testReturnRunsTheRowFromTheFreshestAnswer() async {
        let (session, made, open) = session()
        let apps = command("apps")
        session.feed("sl", commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
        await settle()
        let view = made()[0]
        view.answer(["Slack", "Slides"])
        let shown = session.rows(of: view).first { $0.key == "Slides" }!.actions[0]
        let answered = await session.activation(of: view, key: "Slides", action: shown)
        XCTAssertEqual(answered, .perform(shown), "answered: run as shown")

        view.query = "sli"
        Task { @MainActor in view.answer(["Slides"]) }
        let fresh = await session.activation(of: view, key: "Slides", action: shown)
        XCTAssertNotEqual(fresh, .perform(shown))
        XCTAssertEqual(fresh, .perform(session.rows(of: view)[0].actions[0]), "the same row, from the newer answer")

        view.query = "slid"
        Task { @MainActor in view.answer(["Slider"]) }
        let gone = await session.activation(of: view, key: "Slides", action: shown)
        XCTAssertEqual(gone, .gone)

        view.query = "x"
        let late = await session.activation(of: view, key: "Slides", action: shown, wait: .milliseconds(30))
        XCTAssertEqual(late, .perform(shown), "no answer in time: the row as shown")

        view.isClosed = true
        view.isSearching = true
        let closed = await session.activation(of: view, key: "Slides", action: shown, wait: .milliseconds(30))
        XCTAssertNil(closed)
    }
}

final class RootPatternTests: XCTestCase {
    private func spec(_ pattern: String) -> CommandSpec {
        CommandSpec(id: "c", title: "c", kind: .view, rootSearch: true, rootPattern: pattern)
    }

    func testTheWholeTextMatchesEvenWhenAnEarlierAlternativeMatchesAPrefix() {
        let numbers = spec("\\d+|\\d+-\\d+")
        XCTAssertTrue(RootSearchGate.matches(numbers, text: "12-3"), "ICU's first alternative is `12`, but the whole text matches the second")
        XCTAssertTrue(RootSearchGate.matches(numbers, text: "12"))
        XCTAssertFalse(RootSearchGate.matches(numbers, text: "12-"))
        XCTAssertFalse(RootSearchGate.matches(numbers, text: "a12"))
        XCTAssertFalse(RootSearchGate.matches(spec("[0-9+*/ ()-]+"), text: "2+2 = x"))
        XCTAssertTrue(RootSearchGate.matches(spec("(?i)abc-\\d+"), text: "ABC-123"), "inline flags still apply")
        XCTAssertFalse(RootSearchGate.matches(spec("a)(b"), text: "ab"), "a pattern that doesn't compile as written never matches")
        XCTAssertFalse(RootSearchGate.matches(spec("abc"), text: "abc\nx"))
    }

    @MainActor
    func testAKeptRowIsFoundAgainOnceTheViewAnswers() async {
        let command = { (id: String) in CommandRegistry.Entry(pluginID: "dev.t.\(id)", pluginName: id, spec: CommandSpec(id: id, title: id, kind: .view, rootSearch: true)) }
        let view = FakeRootView(command("apps"), query: "Safari")
        Task { @MainActor in view.answer(["Safari", "Safari Technology Preview"]) }
        let action = await RootSearchSession<FakeRootView>.replay(view, key: "Safari")
        XCTAssertEqual(action?.id, ActionID("row/Safari/0"))

        let gone = FakeRootView(command("apps"), query: "Tower")
        Task { @MainActor in gone.answer([]) }
        let missing = await RootSearchSession<FakeRootView>.replay(gone, key: "Tower")
        XCTAssertNil(missing, "an uninstalled app")

        let stopped = FakeRootView(command("apps"), query: "Mail")
        stopped.isStopped = true
        let none = await RootSearchSession<FakeRootView>.replay(stopped, key: "Mail", wait: .seconds(5))
        XCTAssertNil(none, "a stopped plugin doesn't hold the palette")
    }
}
