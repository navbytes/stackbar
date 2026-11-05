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
