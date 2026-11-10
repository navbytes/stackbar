import Foundation

/// The coding agent that "Edit with …" opens on a plugin. Claude Code is the
/// default; the others are presets for agents people use instead, and
/// `custom` runs any command line.
///
/// Every choice starts in the plugin's folder, where `AgentNotes` keeps an
/// `AGENTS.md` that tells any agent how to read the authoring guide and check
/// its work with `stackbarctl`, so an agent without MCP still knows what to do.
public enum PluginEditor: String, CaseIterable, Codable, Sendable {
    case claudeCode
    case codex
    case opencode
    case cursor
    case pi
    case custom

    public static let defaultsKey = "pluginEditor"
    public static let customCommandKey = "pluginEditorCommand"

    /// The name in "Edit with <name>…".
    public var name: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "opencode"
        case .cursor: return "Cursor"
        case .pi: return "pi"
        case .custom: return "Agent"
        }
    }

    /// The name in the Settings picker.
    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex CLI"
        case .opencode: return "opencode"
        case .cursor: return "Cursor CLI"
        case .pi: return "pi"
        case .custom: return "Custom Command"
        }
    }

    /// Whether Stackbar registers its authoring MCP server with the agent
    /// before starting it. The others read `AGENTS.md` and use `stackbarctl`
    /// on the command line (pi has no MCP; opencode and Cursor keep MCP in
    /// config files Stackbar leaves alone).
    public var registersMCP: Bool { self == .claudeCode || self == .codex }

    /// The default placeholder command for `custom`.
    public static let customExample = "aider {file} --message {prompt}"

    /// What the agent is asked to do first. Also what "Copy Agent Prompt" copies.
    public static func prompt(for file: URL) -> String {
        "Help me change the Stackbar plugin \(file.lastPathComponent) in this folder. Read AGENTS.md here first: "
            + "it says how to load the plugin authoring guide and how to build and render the plugin to check every change."
    }

    /// A Terminal `.command` script that opens this agent on the plugin.
    /// `customCommand` is used by `custom`; `{file}`, `{dir}`, `{prompt}` and
    /// `{stackbarctl}` in it are replaced by shell-quoted values.
    public func script(for file: URL, stackbarctl: String, customCommand: String = "") -> String {
        let directory = file.deletingLastPathComponent().path
        let prompt = Self.prompt(for: file)
        let quotedPrompt = shellQuote(prompt)
        let quotedTool = shellQuote(stackbarctl)
        var lines = [
            "#!/bin/sh",
            "# Opened by Stackbar: \(title) on \(file.lastPathComponent).",
            "cd \(shellQuote(directory)) || exit 1",
        ]
        switch self {
        case .claudeCode:
            lines += missing("claude", install: "https://claude.com/claude-code")
            lines.append("claude mcp get stackbar >/dev/null 2>&1 || claude mcp add stackbar -- \(quotedTool) mcp")
            lines.append("exec claude \(quotedPrompt)")
        case .codex:
            lines += missing("codex", install: "https://developers.openai.com/codex/cli")
            lines.append("codex mcp get stackbar >/dev/null 2>&1 || codex mcp add stackbar -- \(quotedTool) mcp")
            lines.append("exec codex \(quotedPrompt)")
        case .opencode:
            lines += missing("opencode", install: "https://opencode.ai")
            lines.append("exec opencode --prompt \(quotedPrompt)")
        case .cursor:
            lines.append("if command -v cursor-agent >/dev/null 2>&1; then exec cursor-agent \(quotedPrompt); fi")
            lines += missing("agent", install: "https://cursor.com/cli")
            lines.append("exec agent \(quotedPrompt)")
        case .pi:
            lines += missing("pi", install: "https://pi.dev")
            lines.append("exec pi \(quotedPrompt)")
        case .custom:
            let command = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if command.isEmpty {
                lines.append("echo 'Choose the command to run in Stackbar Settings > Agents > Edit Plugins With.'")
                lines.append("exit 1")
            } else {
                lines.append(Self.expand(command, values: [
                    "file": file.path, "dir": directory, "prompt": prompt, "stackbarctl": stackbarctl,
                ]))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Replaces `{name}` placeholders with shell-quoted values; anything else
    /// in braces is left as typed.
    static func expand(_ command: String, values: [String: String]) -> String {
        var result = command
        for (name, value) in values {
            result = result.replacingOccurrences(of: "{\(name)}", with: shellQuote(value))
        }
        return result
    }

    private func missing(_ command: String, install: String) -> [String] {
        [
            "if ! command -v \(command) >/dev/null 2>&1; then",
            "    echo \(shellQuote("\(title) (\(command)) is not installed: \(install)"))",
            "    echo 'Pick another agent in Stackbar Settings > Agents > Edit Plugins With.'",
            "    exit 1",
            "fi",
        ]
    }
}

func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// The `AGENTS.md` (and a `CLAUDE.md` that imports it) Stackbar keeps in the
/// plugins folder, so any coding agent started there knows how to work on a
/// plugin. Stackbar only writes a file that is missing or that it wrote
/// itself: delete the first line to make a file yours.
public enum AgentNotes {
    public static let marker = "<!-- Written by Stackbar, which rewrites this file. Delete this line to keep your own version. -->"

    public static func agentsFile(stackbarctl: String) -> String {
        let tool = shellQuote(stackbarctl)
        return """
        \(marker)
        # Stackbar plugins

        Each `.swift` file in this folder is one Stackbar plugin: a single Swift file that
        imports StackbarKit. Stackbar rebuilds a plugin when its file is saved.

        ## Before you change a plugin

        Read the authoring guide. It is the whole API: manifest, views, storage,
        commands, capabilities.

        - With Stackbar's MCP server connected, call `stackbar_docs`.
        - Otherwise run: `\(tool) docs`

        ## Check every change

        | Step | Command line | MCP tool |
        | --- | --- | --- |
        | Build | `\(tool) build <Plugin>.swift` | `stackbar_build` |
        | Render a surface | `\(tool) render <Plugin>.swift --surface panel` | `stackbar_render` |
        | Press a button | `\(tool) render <Plugin>.swift --event <action-id>` | `stackbar_send_event` |
        | Run a command | `\(tool) run <Plugin>.swift <command>` | `stackbar_run_command` |

        Surfaces are `menuBar`, `panel`, `window` and `widget`. `\(tool)` with no
        arguments lists every option.

        To give an agent the MCP tools, register this stdio server with it:
        `\(tool) mcp`

        ## Rules

        - Keep a plugin to its one `.swift` file; don't add a Package.swift or other files.
        - Don't change the manifest `id`: it keys the plugin's saved data and approvals.
        - Ask before adding capabilities (network hosts, files, secrets): the user approves each one.
        - Build and render after every change, and fix what they report before you stop.

        """
    }

    public static let claudeFile = """
    \(marker)
    @AGENTS.md

    """

    /// Writes both files into `directory` where they are missing or Stackbar's
    /// own. Returns the files it wrote.
    @discardableResult
    public static func write(in directory: URL, stackbarctl: String) -> [URL] {
        var written: [URL] = []
        for (name, text) in [("AGENTS.md", agentsFile(stackbarctl: stackbarctl)), ("CLAUDE.md", claudeFile)] {
            let file = directory.appendingPathComponent(name)
            if let existing = try? String(contentsOf: file, encoding: .utf8) {
                guard existing.hasPrefix(marker), existing != text else { continue }
            }
            if (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil { written.append(file) }
        }
        return written
    }
}
