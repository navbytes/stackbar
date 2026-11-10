import Foundation
import XCTest
@testable import StackbarProtocol

final class MarkdownTests: XCTestCase {
    private func styles(_ text: String) -> [(String, MarkdownStyler.Style)] {
        let string = text as NSString
        return MarkdownStyler.spans(in: text).map { (string.substring(with: NSRange(location: $0.location, length: $0.length)), $0.style) }
    }

    private func has(_ text: String, _ piece: String, _ style: MarkdownStyler.Style, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(styles(text).contains { $0.0 == piece && $0.1 == style }, "\(piece) is not \(style) in \(styles(text))", file: file, line: line)
    }

    func testLines() {
        XCTAssertEqual(MarkdownStyler.lines(of: "a\nbc\n"), [NSRange(location: 0, length: 1), NSRange(location: 2, length: 2), NSRange(location: 5, length: 0)])
        XCTAssertEqual(MarkdownStyler.lines(of: ""), [NSRange(location: 0, length: 0)])
        XCTAssertEqual(MarkdownStyler.lines(of: "x\r\ny"), [NSRange(location: 0, length: 1), NSRange(location: 3, length: 1)])
    }

    func testHeadingsQuotesAndRules() {
        has("# Title", "# Title", .heading(1))
        has("# Title", "# ", .marker)
        has("### Small **bold**", "### Small **bold**", .heading(3))
        has("### Small **bold**", "**bold**", .bold)
        has("> said", "> said", .quote)
        has("---", "---", .rule)
        XCTAssertTrue(styles("#hashtag").isEmpty)
    }

    func testInline() {
        has("a **b** c", "**b**", .bold)
        has("a **b** c", "**", .marker)
        has("an *em* word", "*em*", .italic)
        has("an _em_ word", "_em_", .italic)
        has("~~gone~~", "~~gone~~", .strikethrough)
        has("run `x *y*`", "`x *y*`", .code)
        XCTAssertFalse(styles("run `x *y*`").contains { $0.1 == .italic }, "no emphasis inside code")
        XCTAssertFalse(styles("snake_case_name").contains { $0.1 == .italic }, "underscores inside words are not emphasis")
        has("see [docs](https://a.b)", "docs", .link)
        has("see [docs](https://a.b)", "(https://a.b)", .linkURL)
    }

    func testListsAndTasks() {
        has("- item", "-", .listMarker)
        has("  12. item", "12.", .listMarker)
        has("- [ ] todo", "[ ]", .taskBox(checked: false))
        has("- [x] done it", "[x]", .taskBox(checked: true))
        has("- [x] done it", "done it", .done)
        XCTAssertFalse(styles("-not a list").contains { $0.1 == .listMarker })
    }

    func testFencedCode() {
        let text = "```swift\nlet **x** = 1\n```\nafter **b**"
        has(text, "let **x** = 1", .codeBlock)
        XCTAssertFalse(styles(text).contains { $0.0 == "**x**" }, "no emphasis inside a fence")
        has(text, "**b**", .bold)
    }

    func testOffsetsAreUTF16() {
        has("😀 **b**", "**b**", .bold)
        has("# é 😀 **b**", "**b**", .bold)
    }

    func testListItem() throws {
        let item = try XCTUnwrap(ListItem("\t3) [X] thing"))
        XCTAssertEqual(item.indent, "\t")
        XCTAssertEqual(item.marker, "3)")
        XCTAssertEqual(item.nextMarker, "4)")
        XCTAssertTrue(item.checked)
        XCTAssertEqual(item.contentStart, 8)
        XCTAssertEqual(ListItem("* x")?.nextMarker, "*")
        XCTAssertNil(ListItem("text"))
    }

    // MARK: Editing

    private func apply(_ edit: MarkdownEditing.Edit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.text), edit.selection)
    }

    func testReturnContinuesLists() throws {
        let bullet = try XCTUnwrap(apply(MarkdownEditing.newline(in: "- one", selection: NSRange(location: 5, length: 0)), to: "- one"))
        XCTAssertEqual(bullet.0, "- one\n- ")
        XCTAssertEqual(bullet.1, NSRange(location: 8, length: 0))
        XCTAssertEqual(apply(MarkdownEditing.newline(in: "  9. nine", selection: NSRange(location: 9, length: 0)), to: "  9. nine")?.0, "  9. nine\n  10. ")
        XCTAssertEqual(apply(MarkdownEditing.newline(in: "- [x] a", selection: NSRange(location: 7, length: 0)), to: "- [x] a")?.0, "- [x] a\n- [ ] ")
        // An empty item ends the list.
        let ended = try XCTUnwrap(apply(MarkdownEditing.newline(in: "- a\n- ", selection: NSRange(location: 6, length: 0)), to: "- a\n- "))
        XCTAssertEqual(ended.0, "- a\n")
        XCTAssertEqual(ended.1, NSRange(location: 4, length: 0))
        XCTAssertNil(MarkdownEditing.newline(in: "plain", selection: NSRange(location: 5, length: 0)))
        XCTAssertNil(MarkdownEditing.newline(in: "- one", selection: NSRange(location: 1, length: 0)), "before the text, Return just breaks")
    }

    func testToggleTask() {
        XCTAssertEqual(apply(MarkdownEditing.toggleTask(in: "- [ ] a", at: 4), to: "- [ ] a")?.0, "- [x] a")
        XCTAssertEqual(apply(MarkdownEditing.toggleTask(in: "x\n- [x] a", at: 3), to: "x\n- [x] a")?.0, "x\n- [ ] a")
        XCTAssertEqual(apply(MarkdownEditing.toggleTask(in: "- a", at: 3), to: "- a")?.0, "- [ ] a")
        XCTAssertEqual(apply(MarkdownEditing.toggleTask(in: "  buy milk", at: 5), to: "  buy milk")?.0, "  - [ ] buy milk")
        XCTAssertEqual(MarkdownEditing.toggleTask(in: "buy", at: 3)?.selection, NSRange(location: 9, length: 0))
    }

    func testIndent() {
        let text = "- a\n- b\nplain"
        XCTAssertEqual(apply(MarkdownEditing.indent(in: text, selection: NSRange(location: 6, length: 0), outdent: false), to: text)?.0, "- a\n\t- b\nplain")
        XCTAssertEqual(apply(MarkdownEditing.indent(in: "\t- b", selection: NSRange(location: 2, length: 0), outdent: true), to: "\t- b")?.0, "- b")
        XCTAssertEqual(apply(MarkdownEditing.indent(in: "    - b", selection: NSRange(location: 5, length: 0), outdent: true), to: "    - b")?.0, "- b")
        XCTAssertNil(MarkdownEditing.indent(in: text, selection: NSRange(location: 10, length: 0), outdent: false), "Tab on plain text types a tab")
        XCTAssertNil(MarkdownEditing.indent(in: "- a", selection: NSRange(location: 1, length: 0), outdent: true), "nothing to outdent")
    }

    func testWrap() {
        XCTAssertEqual(apply(MarkdownEditing.wrap(in: "a word", selection: NSRange(location: 2, length: 4), marker: "**"), to: "a word")?.0, "a **word**")
        XCTAssertEqual(MarkdownEditing.wrap(in: "a word", selection: NSRange(location: 2, length: 4), marker: "**").selection, NSRange(location: 4, length: 4))
        XCTAssertEqual(apply(MarkdownEditing.wrap(in: "a **word**", selection: NSRange(location: 4, length: 4), marker: "**"), to: "a **word**")?.0, "a word")
        XCTAssertEqual(apply(MarkdownEditing.wrap(in: "a **word**", selection: NSRange(location: 2, length: 8), marker: "**"), to: "a **word**")?.0, "a word")
        let empty = MarkdownEditing.wrap(in: "", selection: NSRange(location: 0, length: 0), marker: "*")
        XCTAssertEqual(empty.text, "**")
        XCTAssertEqual(empty.selection, NSRange(location: 1, length: 0))
    }

    func testLink() {
        let edit = MarkdownEditing.link(in: "see docs", selection: NSRange(location: 4, length: 4))
        XCTAssertEqual(apply(edit, to: "see docs")?.0, "see [docs]()")
        XCTAssertEqual(edit.selection, NSRange(location: 11, length: 0))
        XCTAssertEqual(MarkdownEditing.link(in: "", selection: NSRange(location: 0, length: 0)).selection, NSRange(location: 1, length: 0))
    }
}

final class EditorSyncTests: XCTestCase {
    func testTypingWinsUntilSent() {
        var sync = EditorSync(document: "a", text: "one")
        XCTAssertNil(sync.render(document: "a", text: "one"), "the same render changes nothing")
        sync.edited()
        XCTAssertNil(sync.render(document: "a", text: "changed elsewhere"), "typing in flight wins")
        XCTAssertEqual(sync.flush("one two"), "one two")
        XCTAssertNil(sync.render(document: "a", text: "one two"), "the plugin's echo changes nothing")
        XCTAssertNil(sync.flush("one two"), "nothing new to send")
    }

    func testOutsideChangeShowsWhenIdle() {
        var sync = EditorSync(document: "a", text: "one")
        XCTAssertEqual(sync.render(document: "a", text: "edited in another app"), "edited in another app")
        XCTAssertNil(sync.flush("edited in another app"))
    }

    func testStaleRenderIsIgnored() {
        var sync = EditorSync(document: "a", text: "one")
        XCTAssertEqual(sync.flush("one two"), "one two")
        XCTAssertNil(sync.render(document: "a", text: "one"), "a render made before the plugin heard the send")
    }

    func testNewDocumentReplaces() {
        var sync = EditorSync(document: "a", text: "one")
        sync.edited()
        XCTAssertEqual(sync.render(document: "b", text: "two"), "two")
        XCTAssertFalse(sync.isDirty)
        XCTAssertEqual(sync.document, "b")
    }
}
