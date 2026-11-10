import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Protocol 28: the multiline editor node, and the plugin's own window on call.
final class ProtocolTwentyEightTests: XCTestCase {
    private let note = ViewNode.editor(EditorNode(text: "# Groceries\n- [ ] milk", document: "n1", placeholder: "Start writing", markdown: true, action: "editor/body"))

    func testAnEditorIsInputForTheAgentAndHiddenInTheMenuBar() {
        XCTAssertEqual(TreeTextRenderer.render(note), "Editor (markdown)  {editor/body}\n  # Groceries\n  - [ ] milk")
        XCTAssertEqual(note.actions, ["editor/body"])
        XCTAssertTrue(note.isBlankInMenuBar)
        XCTAssertEqual(SurfaceParity.Kind(note), .editor)
        XCTAssertTrue(ViewNode.stack(axis: .vertical, children: [.text("Notes"), note]).containsEditor)
        XCTAssertFalse(ViewNode.text("Notes").containsEditor)
    }

    func testTheEditorRoundTripsWithOptionalFields() throws {
        XCTAssertEqual(try JSONDecoder().decode(ViewNode.self, from: JSONEncoder().encode(note)), note)
        let bare = #"{"editor":{"_0":{"text":"","document":"","action":"editor/text"}}}"#
        guard case .editor(let editor) = try JSONDecoder().decode(ViewNode.self, from: Data(bare.utf8)) else { return XCTFail("an editor") }
        XCTAssertNil(editor.markdown)
        XCTAssertNil(editor.minHeight)
    }

    func testWindowCallsNeedTheWindowSurface() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seen = Seen()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(window: { id, request in seen.add(id, request) }))
        let panelOnly = Manifest(id: "dev.test.panel", name: "Panel", surfaces: [.menuBar, .panel])
        guard case .failure(let message) = await services.handle(.pluginWindow(WindowRequest(.toggle)), for: panelOnly) else { return XCTFail("no window, no call") }
        XCTAssertTrue(message.contains(".window"), message)
        XCTAssertTrue(seen.all.isEmpty)

        let notes = Manifest(id: "dev.test.notes", name: "Notes", surfaces: [.menuBar, .window])
        let result = await services.handle(.pluginWindow(WindowRequest(.toggle, keepOnTop: true)), for: notes)
        XCTAssertEqual(result, .ok)
        XCTAssertEqual(seen.all.first?.0, "dev.test.notes")
        XCTAssertEqual(seen.all.first?.1, WindowRequest(.toggle, keepOnTop: true))
        XCTAssertNil(HostCall.pluginWindow(WindowRequest(.show)).requirement)
        XCTAssertNotNil(HostCall.pluginWindow(WindowRequest(.show)).budget)
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(String, WindowRequest)] = []
    func add(_ id: String, _ request: WindowRequest) { lock.withLock { calls.append((id, request)) } }
    var all: [(String, WindowRequest)] { lock.withLock { calls } }
}
