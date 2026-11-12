# Design

`PluginEditor` (StackbarHostCore) is an enum of the presets plus `custom`. It
builds the `.command` script, so every launch line is tested on Linux;
`Platform.editPlugin` writes it and hands it to `MacSystem.open(script:)`, the
same path Open in Terminal uses, so the chosen terminal applies.

Launch lines (checked against each tool's docs, 2026-11-10):
- Claude Code: `claude mcp get/add stackbar -- <ctl> mcp`, `claude <prompt>`
- Codex: `codex mcp get/add stackbar -- <ctl> mcp`, `codex <prompt>`
- opencode: `opencode --prompt <prompt>` (its `mcp add` is interactive only)
- Cursor: `cursor-agent <prompt>`, falling back to `agent` (the CLI's new name)
- pi: `pi <prompt>` (no MCP by design)

The prompt is the same for all: change `<file>`, read `AGENTS.md` first.
`AGENTS.md` is read by Codex, opencode, Cursor and pi; Claude Code reads the
`CLAUDE.md`, which is `@AGENTS.md`. The notes embed the absolute
`stackbarctl` path, since the CLI may not be on PATH; a moved app rewrites
them at next launch.

`AgentNotes.write` only replaces a file that starts with its marker, so a
user's own AGENTS.md or CLAUDE.md is never overwritten.

The choice is kept in UserDefaults (`pluginEditor`, `pluginEditorCommand`).
