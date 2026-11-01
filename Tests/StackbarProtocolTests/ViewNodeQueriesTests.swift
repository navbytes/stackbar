import XCTest
@testable import StackbarProtocol

final class ViewNodeQueriesTests: XCTestCase {
    private func row(_ key: String, _ title: String, subtitle: String? = nil, preview: String? = nil) -> ViewNode {
        .row(RowNode(key: key, title: title, subtitle: subtitle, preview: preview.map { RowPreview(text: $0) }))
    }

    private func keys(_ nodes: [ViewNode]) -> [String] {
        nodes.flatMap(\.rows).map(\.key)
    }

    func testFilterRanksPlainRowsAndKeepsEmptyQueries() {
        let children = [row("grape", "Grape", subtitle: "apple-ish"), row("banana", "Banana"), row("pie", "Apple pie"), row("note", "Note", preview: "an apple a day")]
        XCTAssertEqual(keys(RowFilter.filter(children, query: " apple ")), ["pie", "grape", "note"], "title beats subtitle beats preview")
        XCTAssertEqual(RowFilter.filter(children, query: "  "), children)
        XCTAssertEqual(RowFilter.filter(children, query: "zzz"), [])
    }

    func testFilterNarrowsSectionsInOrder() {
        let children: [ViewNode] = [
            .section(title: "Fruit", children: [row("banana", "Banana"), row("crab", "Crab apple")]),
            .section(title: "Other", children: [row("cherry", "Cherry")]),
            .section(title: "Pies", children: [row("pie", "Apple pie")]),
            .divider,
        ]
        XCTAssertEqual(RowFilter.filter(children, query: "apple"), [
            .section(title: "Fruit", children: [row("crab", "Crab apple")]),
            .section(title: "Pies", children: [row("pie", "Apple pie")]),
        ], "sections keep their order even when a later one matches better; empty ones and the divider go")
    }

    func testListItemsFlattenSectionsForTheKeyboard() {
        let list = ViewNode.list(searchable: true, children: [
            row("inbox", "Inbox"),
            .section(title: "Pinned", children: [row("apple", "Apple"), row("pear", "Pear")]),
            .section(title: nil, children: [row("apricot", "Apricot")]),
        ])
        XCTAssertEqual(RowFilter.items(in: list, query: ""), [
            .row(list.rows[0]), .header("Pinned"), .row(list.rows[1]), .row(list.rows[2]), .row(list.rows[3]),
        ])
        XCTAssertEqual(RowFilter.items(in: list, query: "ap")?.map(\.id), ["header|Pinned", "apple", "apricot"])
        XCTAssertEqual(RowFilter.items(in: .list(children: [row("a", "A")]), query: "zzz")?.map(\.id), ["a"], "a list that isn't searchable isn't filtered")
        XCTAssertNil(RowFilter.items(in: .stack(axis: .vertical, children: [row("a", "A")]), query: ""))
        XCTAssertNil(RowFilter.items(in: .list(children: [row("a", "A"), .button(title: "More", action: "button/More")]), query: ""))
        XCTAssertNil(RowFilter.items(in: .list(children: [.section(title: "S", children: [.divider])]), query: ""))
    }

    func testMapChildrenRebuildsEachContainerOnce() {
        let style = Style(opacity: 0.5)
        let upper: (ViewNode) -> ViewNode = { node in
            if case .text(let string, _, _) = node { return .text(string.uppercased()) }
            return node
        }
        XCTAssertEqual(ViewNode.stack(axis: .horizontal, spacing: 4, alignment: .start, children: [.text("a"), .stack(axis: .vertical, children: [.text("b")])]).mapChildren(upper),
                       .stack(axis: .horizontal, spacing: 4, alignment: .start, children: [.text("A"), .stack(axis: .vertical, children: [.text("b")])]), "direct children only")
        XCTAssertEqual(ViewNode.list(searchable: true, children: [.text("a")]).mapChildren(upper), .list(searchable: true, children: [.text("A")]))
        XCTAssertEqual(ViewNode.section(title: "T", children: [.text("a")]).mapChildren(upper), .section(title: "T", children: [.text("A")]))
        XCTAssertEqual(ViewNode.styled(.text("a"), style: style).mapChildren(upper), .styled(.text("A"), style: style))
        XCTAssertEqual(ViewNode.tappable(.text("a"), action: "button/a").mapChildren(upper), .tappable(.text("A"), action: "button/a"))
        XCTAssertEqual(ViewNode.text("a").mapChildren(upper), .text("a"))
    }

    func testTrimmedCutsEveryListForTheWidget() {
        let rows = (1...6).map { row("\($0)", "Row \($0)") }
        let tree = ViewNode.stack(axis: .vertical, children: [
            .text("Header"),
            .styled(.list(searchable: true, children: rows), style: Style(opacity: 1)),
            .section(title: "More", children: [.tappable(.list(children: rows), action: "button/open")]),
        ])
        XCTAssertEqual(tree.trimmed(maxRows: 2), .stack(axis: .vertical, children: [
            .text("Header"),
            .styled(.list(searchable: false, children: Array(rows.prefix(2))), style: Style(opacity: 1)),
            .section(title: "More", children: [.tappable(.list(children: Array(rows.prefix(2))), action: "button/open")]),
        ]))
    }

    func testMenuBarBlanknessLooksThroughStacksAndStyles() {
        XCTAssertFalse(ViewNode.text("9:41").isBlankInMenuBar)
        XCTAssertFalse(ViewNode.stack(axis: .horizontal, children: [.button(title: "Go", action: "button/Go"), .styled(.image(.symbol("cup")), style: Style(opacity: 1))]).isBlankInMenuBar)
        XCTAssertTrue(ViewNode.stack(axis: .horizontal, children: [.button(title: "Go", action: "button/Go"), .divider, .spacer()]).isBlankInMenuBar)
        XCTAssertTrue(ViewNode.section(title: nil, children: [.text("panel only")]).isBlankInMenuBar)
        XCTAssertTrue(ViewNode.tappable(.text("Go"), action: "button/Go").isBlankInMenuBar)
        XCTAssertTrue(ViewNode.stack(axis: .vertical, children: []).isBlankInMenuBar)
    }

    func testFormErrorsAreFoundAnywhereInTheTree() {
        let clean = FormNode(fields: [FormField(name: "name", label: "Name", kind: .text(placeholder: nil))], action: "form/save")
        var failed = clean
        failed.fields[0].error = "Required"
        XCTAssertFalse(ViewNode.form(clean).hasFormErrors)
        XCTAssertTrue(ViewNode.stack(axis: .vertical, children: [.text("Edit"), .section(title: nil, children: [.form(failed)])]).hasFormErrors)
        XCTAssertFalse(ViewNode.stack(axis: .vertical, children: [.text("Saved")]).hasFormErrors)
    }

    /// One of everything that can be pressed.
    private static let controls = ViewNode.stack(axis: .vertical, children: [
        .row(RowNode(key: "1", title: "Fix bug", symbol: "ladybug", actions: [
            ActionRef(id: "row/1/Open", title: "Open"),
            ActionRef(id: "row/1/Details", title: "Details", navigate: CommandTarget(command: "details", arguments: ["id": "1"])),
        ])),
        .button(title: "Save", symbol: "tray", action: "button/Save"),
        .toggle(title: "Sound", isOn: false, action: "toggle/Sound"),
        .textField(placeholder: "Search", text: "", action: "field/Search"),
        .picker(title: "Mode", options: ["a", "b"], selection: nil, action: "picker/Mode"),
        .slider(title: "Volume", value: 0, min: 0, max: 1, action: "slider/Volume"),
        .form(FormNode(fields: [], submitTitle: "Add", action: "form/Add")),
        .link(title: "Docs", url: "https://example.com"),
        .tappable(.stack(axis: .horizontal, children: [.text("Start"), .button(title: "Inner", action: "button/Inner")]), action: "button/Start"),
        .tappable(.image(.symbol("play.fill")), action: "button/Play"),
        .section(title: "More", children: [.styled(.button(title: "Styled", action: "button/Styled"), style: Style(opacity: 1))]),
    ])

    func testAffordancesNameEverythingPressable() {
        var inner = Affordance(title: "Inner", kind: .action("button/Inner", value: nil))
        inner.isInsideTappable = true
        XCTAssertEqual(Self.controls.affordances, [
            Affordance(title: "Fix bug", subtitle: "Open", symbol: "ladybug", kind: .action("row/1/Open", value: nil)),
            Affordance(title: "Details: Fix bug", symbol: "ladybug", kind: .navigate(CommandTarget(command: "details", arguments: ["id": "1"]), action: "row/1/Details")),
            Affordance(title: "Save", symbol: "tray", kind: .action("button/Save", value: nil)),
            Affordance(title: "Turn on Sound", symbol: "switch.2", kind: .action("toggle/Sound", value: .bool(true))),
            Affordance(title: "Search", kind: .input("field/Search")),
            Affordance(title: "Mode", kind: .input("picker/Mode")),
            Affordance(title: "Volume", kind: .input("slider/Volume")),
            Affordance(title: "Add", kind: .input("form/Add")),
            Affordance(title: "Docs", subtitle: "https://example.com", symbol: "link", kind: .open("https://example.com")),
            Affordance(title: "Start Inner", kind: .tappable("button/Start")),
            inner,
            Affordance(title: "", kind: .tappable("button/Play")),
            Affordance(title: "Styled", kind: .action("button/Styled", value: nil)),
        ])
    }

    func testActionsAreEveryAffordanceButLinks() {
        XCTAssertEqual(Self.controls.actions, [
            "row/1/Open", "row/1/Details", "button/Save", "toggle/Sound", "field/Search", "picker/Mode", "slider/Volume",
            "form/Add", "button/Start", "button/Inner", "button/Play", "button/Styled",
        ], "the same ids, in the same order, as before affordances")
        XCTAssertEqual(ViewNode.link(title: "Docs", url: "https://example.com").actions, [])
    }
}
