---
title: Agents and MCP
description: Let Claude Code and other MCP clients use your plugins' tools, and let them write plugins for you.
group: Build plugins
order: 3
---

Stackbar speaks the Model Context Protocol in two ways.

## Your plugins as tools

A plugin can offer tools (PR Cockpit lists your pull requests, Todo adds a
task). Settings › Agents turns the gateway on and shows the command to connect a
client, ready to copy. For Claude Code:

```sh
claude mcp add stackbar -- stackbarctl agent
```

The agent sees every running plugin's tools, and each call goes through the
app with the same sandbox and approvals as a click.

## An agent that writes plugins

`stackbarctl mcp` is an authoring server: an agent can scaffold a plugin,
build it, render each surface as text, press its buttons and read the logs,
without the app open. The [plugin reference](/docs/authoring/) is the same
text the server serves, and is also at [/llms.txt](/llms.txt).

## Editing a plugin with your coding agent

A plugin's ⋯ menu has **Edit with …**, which opens a coding agent in the
plugins folder, in the terminal you chose in Settings › General. Pick the
agent in Settings › Agents › Edit Plugins With:

| Agent | What Stackbar does |
| --- | --- |
| Claude Code (default) | Adds `stackbarctl mcp` to Claude Code, then starts `claude` |
| Codex CLI | Adds `stackbarctl mcp` to Codex, then starts `codex` |
| opencode | Starts `opencode --prompt …` |
| Cursor CLI | Starts `cursor-agent` |
| pi | Starts `pi` |
| Custom command | Runs your command line; `{file}`, `{dir}`, `{prompt}` and `{stackbarctl}` are filled in, quoted |

Every agent starts with the same prompt and finds an `AGENTS.md` in the
plugins folder (and a `CLAUDE.md` that imports it). It says how to read the
reference and how to build, render and press buttons with `stackbarctl`, so an
agent without MCP, like pi, works the same way. Stackbar keeps both files up to
date; delete their first line to make them yours, and Stackbar leaves them
alone.

To use an agent that isn't listed, or one in an editor, choose **Copy Agent
Prompt** from the ⋯ menu and paste it into the agent, started in the plugins
folder. Agents with MCP can add `stackbarctl mcp` as a stdio server to get the
same tools as tool calls.
