import Foundation
import StackbarProtocol
@testable import StackbarHostCore
import XCTest

/// Opening a view command again draws its last list while the plugin
/// searches, and nothing in that list reaches the plugin.
final class ViewTreeCacheTests: XCTestCase {
    private let tabs = CommandKey(pluginID: "dev.navbytes.browser-tabs", commandID: "search")

    private func list(session: Int, _ titles: [String]) -> ViewNode {
        .list(children: titles.map { title in
            .row(RowNode(key: title, title: title, actions: [ActionRef(id: ActionID("view/\(session)/row/\(title)/Open"), title: "Open")]))
        })
    }

    func testAViewDrawsLastTimesListUntilItsFirstAnswerAndSendsNothingFromIt() {
        let old = list(session: 3, ["Inbox", "Docs"])
        var view = CommandView(session: 9, pluginName: "Browser Tabs", query: CommandQuery(), placeholder: old)
        XCTAssertEqual(view.open(), [.open(seq: 1, query: CommandQuery())])
        XCTAssertEqual(view.shownRoot, old)
        XCTAssertTrue(view.isShowingPlaceholder)
        XCTAssertTrue(view.isSearching)
        XCTAssertEqual(view.answers, 0)
        XCTAssertEqual(view.perform(ActionID("view/3/row/Inbox/Open")), [], "an old session's action goes nowhere")

        let fresh = list(session: 9, ["Inbox"])
        XCTAssertTrue(view.received(seq: 1, root: fresh).shown)
        XCTAssertFalse(view.isShowingPlaceholder)
        XCTAssertEqual(view.shownRoot, fresh)
        XCTAssertEqual(view.perform(ActionID("view/9/row/Inbox/Open")), [.event(ActionID("view/9/row/Inbox/Open"), nil)])
    }

    func testTheCacheKeepsListsByCommandAndQueryAndDropsTheOldest() {
        var cache = ViewTreeCache(capacity: 2)
        let empty = ViewTreeCache.Key(command: tabs, query: CommandQuery())
        cache.remember(list(session: 1, ["Inbox"]), for: empty)
        XCTAssertEqual(cache.tree(for: empty), list(session: 1, ["Inbox"]))
        XCTAssertNil(cache.tree(for: ViewTreeCache.Key(command: tabs, query: CommandQuery(text: "git"))), "another query is another list")

        let other = ViewTreeCache.Key(command: CommandKey(pluginID: "p", commandID: "a"), query: CommandQuery())
        let third = ViewTreeCache.Key(command: CommandKey(pluginID: "p", commandID: "b"), query: CommandQuery())
        cache.remember(list(session: 2, ["x"]), for: other)
        _ = cache.tree(for: empty) // used: the newest now
        cache.remember(list(session: 3, ["y"]), for: third)
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.tree(for: other), "the least recently used goes first")
        XCTAssertNotNil(cache.tree(for: empty))

        cache.forget(pluginID: "p")
        XCTAssertNil(cache.tree(for: third))
        XCTAssertEqual(cache.count, 1)
    }

    func testOnlyListsWithRowsAreKept() {
        var cache = ViewTreeCache()
        let key = ViewTreeCache.Key(command: tabs, query: CommandQuery())
        cache.remember(list(session: 1, ["Inbox"]), for: key)
        cache.remember(.empty(title: "No tabs open", symbol: nil, message: nil), for: key)
        XCTAssertNil(cache.tree(for: key), "an empty answer replaces the kept list")

        let form = ViewNode.form(FormNode(fields: [FormField(name: "n", label: "N", kind: .text(placeholder: nil))], action: ActionID("view/1/form/x")))
        cache.remember(.stack(axis: .vertical, spacing: nil, children: [form, list(session: 1, ["a"])]), for: key)
        XCTAssertNil(cache.tree(for: key), "a form is never drawn from old data")
    }
}

/// Protocol 30: the plugin's own "still fetching" flag and hidden keywords.
final class ViewLoadingTests: XCTestCase {
    func testThePluginsLoadingFlagKeepsTheBarAfterItAnswers() {
        var view = CommandView(session: 1, pluginName: "P", query: CommandQuery())
        _ = view.open()
        XCTAssertTrue(view.isLoading, "waiting for the first answer")
        _ = view.received(seq: 1, root: .list(children: []), loading: true)
        XCTAssertFalse(view.isSearching)
        XCTAssertTrue(view.isLoading, "answered, but the plugin is still fetching behind it")
        _ = view.received(seq: 1, root: .list(children: []), loading: false)
        XCTAssertFalse(view.isLoading)
        _ = view.received(seq: 1, root: .list(children: []), loading: true)
        _ = view.pluginState(.failed("boom"))
        XCTAssertFalse(view.isLoading, "a stopped plugin fetches nothing")
    }

    func testSearchableListsMatchHiddenKeywordsBelowWhatRowsShow() {
        let rows: [ViewNode] = [
            .row(RowNode(key: "1", title: "Inbox", keywords: ["https://mail.example.com/inbox"])),
            .row(RowNode(key: "2", title: "example notes")),
            .row(RowNode(key: "3", title: "Docs")),
        ]
        let kept = RowFilter.filter(rows, query: "example").compactMap { node -> String? in
            if case .row(let row) = node { return row.key } else { return nil }
        }
        XCTAssertEqual(kept, ["2", "1"], "a shown match ranks above a hidden one; no match is dropped")
    }

    func testOldMessagesWithoutLoadingStillDecode() throws {
        let old = #"{"view":{"session":1,"seq":2,"root":{"list":{"searchable":false,"children":[]}}}}"#
        let message = try JSONDecoder().decode(PluginMessage.self, from: Data(old.utf8))
        guard case .view(1, 2, _, let loading) = message else { return XCTFail("expected a view") }
        XCTAssertNil(loading)
    }
}
