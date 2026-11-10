import Foundation
@testable import StackbarHostCore
import XCTest

final class PluginEditorTests: XCTestCase {
    let file = URL(fileURLWithPath: "/Users/x/It's here/Todo.swift")
    let tool = "/Applications/Stackbar.app/Contents/MacOS/stackbarctl"

    func testClaudeCodeRegistersTheMCPServerAndQuotesPaths() {
        let script = PluginEditor.claudeCode.script(for: file, stackbarctl: tool)
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(script.contains(#"cd '/Users/x/It'\''s here'"#))
        XCTAssertTrue(script.contains("claude mcp add stackbar -- '\(tool)' mcp"))
        XCTAssertTrue(script.contains("exec claude 'Help me change the Stackbar plugin Todo.swift"))
    }

    func testCodexRegistersTheMCPServer() {
        let script = PluginEditor.codex.script(for: file, stackbarctl: tool)
        XCTAssertTrue(script.contains("codex mcp add stackbar -- '\(tool)' mcp"))
        XCTAssertTrue(script.contains("exec codex 'Help me"))
    }

    func testPresetsWithoutMCPOnlyStartTheAgent() {
        XCTAssertTrue(PluginEditor.opencode.script(for: file, stackbarctl: tool).contains("exec opencode --prompt 'Help me"))
        XCTAssertTrue(PluginEditor.pi.script(for: file, stackbarctl: tool).contains("exec pi 'Help me"))
        let cursor = PluginEditor.cursor.script(for: file, stackbarctl: tool)
        XCTAssertTrue(cursor.contains("exec cursor-agent 'Help me"))
        XCTAssertTrue(cursor.contains("exec agent 'Help me"))
        for editor in [PluginEditor.opencode, .cursor, .pi, .custom] {
            XCTAssertFalse(editor.registersMCP)
            XCTAssertFalse(editor.script(for: file, stackbarctl: tool, customCommand: "x").contains("mcp add"), editor.rawValue)
        }
    }

    func testAMissingAgentSaysWhereToGetIt() {
        let script = PluginEditor.pi.script(for: file, stackbarctl: tool)
        XCTAssertTrue(script.contains("if ! command -v pi >/dev/null 2>&1; then"))
        XCTAssertTrue(script.contains("https://pi.dev"))
    }

    func testCustomCommandPlaceholdersAreQuoted() {
        let script = PluginEditor.custom.script(for: file, stackbarctl: tool, customCommand: "aider {file} --message {prompt} # {other}")
        XCTAssertTrue(script.contains(#"aider '/Users/x/It'\''s here/Todo.swift' --message 'Help me change"#))
        XCTAssertTrue(script.contains("{other}"), "unknown placeholders stay as typed")
    }

    func testAnEmptyCustomCommandExplainsItself() {
        let script = PluginEditor.custom.script(for: file, stackbarctl: tool, customCommand: "  ")
        XCTAssertTrue(script.contains("Edit Plugins With"))
        XCTAssertTrue(script.contains("exit 1"))
    }

    func testScriptsRunInTheShell() throws {
        #if os(Linux) || os(macOS)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("editor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plugin = directory.appendingPathComponent("Todo.swift")
        let output = directory.appendingPathComponent("out.txt")
        let script = PluginEditor.custom.script(for: plugin, stackbarctl: tool, customCommand: "printf '%s|%s' {dir} {prompt} > \(output.path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertEqual(text, directory.path + "|" + PluginEditor.prompt(for: plugin))
        #endif
    }

    func testAgentNotesAreWrittenButNeverOverAUsersFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(AgentNotes.write(in: directory, stackbarctl: tool).map(\.lastPathComponent), ["AGENTS.md", "CLAUDE.md"])
        let agents = try String(contentsOf: directory.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(agents.hasPrefix(AgentNotes.marker))
        XCTAssertTrue(agents.contains("'\(tool)' docs"))
        XCTAssertTrue(try String(contentsOf: directory.appendingPathComponent("CLAUDE.md"), encoding: .utf8).contains("@AGENTS.md"))

        XCTAssertTrue(AgentNotes.write(in: directory, stackbarctl: tool).isEmpty, "unchanged files are left alone")
        XCTAssertEqual(AgentNotes.write(in: directory, stackbarctl: "/moved/stackbarctl").map(\.lastPathComponent), ["AGENTS.md"], "a moved app updates its own file")

        try "My own notes".write(to: directory.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        AgentNotes.write(in: directory, stackbarctl: tool)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("CLAUDE.md"), encoding: .utf8), "My own notes")
    }
}
