# Edit plugins with any coding agent

## Why
Naveen (2026-11-10): "Edit with Claude" only works for Claude Code users.
People who use opencode, pi, Codex or Cursor click it and get "Claude Code is
not installed". Everything the button relies on (`stackbarctl mcp`,
`stackbarctl docs`, `build`, `render`) already works with any agent; only the
launcher and its discoverability were Claude-only.

## What changes
- **Settings › Agents › Edit Plugins With** picks the agent: Claude Code
  (default), Codex CLI, opencode, Cursor CLI, pi, or a custom command line with
  `{file}`, `{dir}`, `{prompt}` and `{stackbarctl}` placeholders.
- The button reads **Edit with <agent>…** and runs in the terminal chosen in
  Settings › General (it used to ignore that setting).
- Claude Code and Codex get `stackbarctl mcp` registered first, as before.
  The others are started as-is: pi has no MCP, and opencode and Cursor keep
  MCP in config files Stackbar doesn't touch.
- **AGENTS.md in the plugins folder** (plus a CLAUDE.md that imports it) tells
  any agent how to read the guide and check its work with `stackbarctl` or the
  MCP tools. Stackbar writes them at launch and before each edit, only when
  missing or still its own (first-line marker).
- **Copy Agent Prompt** in a plugin's ⋯ menu, for any agent not listed.

## Not changing
- No protocol or StackbarKit change.
- The runtime gateway (`stackbarctl agent`) is unchanged; its Settings footer
  now says other MCP clients use the same command.
