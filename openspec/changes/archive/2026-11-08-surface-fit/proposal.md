# Each plugin on the surfaces that fit it

## Why

Naveen asked (2026-11-04) which surfaces each store plugin should use, and
approved the report "Stackbar plugin surfaces report"
(https://claude.ai/artifact/PLxYJnrSPwvxVejyqeMkor). Stackbar may grow into a
Spotlight and Raycast replacement, so the palette becomes the main surface
and many plugins answer what is typed at its root. Four gaps in the host stop
plugins from landing where they fit:

1. Root search has no ranking beyond "first row starts with the text", no
   way to keep text of the wrong shape from a plugin, no time limit, and no
   switch for the user.
2. A plugin that lists `.menuBar` always has an item, even a background
   service whose grey icon never changes.
3. Agent tools are all-or-nothing; Clipboard History's tools return full
   clipboard text.
4. Widgets are read-only, so a widget for a toggle (Stay Awake) or a player
   (Music) can't do the one thing people want from it.

## What changes

Host (Stackbar 0.21.0, protocol 17):

- **Root patterns.** `Command.rootSearch(section:matching:)` sets
  `CommandSpec.rootPattern`, a regular expression the whole typed text must
  match before the host sends it (`ABC-123`, a port number, `:smile`). A
  matching section leads the results.
- **Ranking.** Plugin sections lead when their pattern matched or their first
  row starts with the text; within leads and follows, pattern first, then best
  `TextMatch` score over the section's rows.
- **Time budget.** `RootSearchBudget`: three answers over 0.4 s in a row bench
  the command from root search for ten minutes; a quick answer clears it; a
  plugin restart forgets it.
- **User switch.** `CommandPreference.inRootSearch` (Settings → Commands, the
  row's menu) turns a command's root search or fallback off.
- **Empty menu bar.** A `menuBar` with no nodes takes the item out of the bar
  (`PluginController.menuBarIdle`); the panel opens from the palette, as for
  panel-only plugins.
- **Opt-in tools.** `AgentTool(...).optIn()` sets `ToolSpec.optIn`;
  `AgentConsent` keeps per-tool choices (Settings → Agents has a switch per
  tool and for reading the panel). A plugin with an opt-in tool keeps its
  panel from `stackbar_read` until allowed.
- **Widget buttons.** Buttons, toggles, tappables and rows in a widget run
  `WidgetActionIntent`, which leaves a `WidgetAction` in the app group and
  posts a Darwin notification; the app sends it to the plugin as a panel
  click. Fields, pickers and sliders stay disabled.

Plugins (stackbar-plugins), per the report and Naveen's follow-up:

- Root search: Ports (a port number), World Clock (a city), Jira and Linear
  (an issue key), PR Cockpit (a repository or `#123`), Emoji (`:name`).
- Fallbacks: Todo ("Add todo: …"), Translate.
- First commands: LiteLLM (spend), System Monitor (top processes).
- Widgets: Jira, Linear; Stay Awake, Homebrew and Music widgets gain buttons.
- Docker gets a window with a live log tail.
- Pomodoro: click the menu bar item to start or pause.
- Menu bar off unless needed: Workspaces, App Switcher, Clipboard History.
- Clipboard History's tools become opt-in.

## Not in scope

Taking over ⌘Space, and the Spotlight exposure of commands; Naveen is still
weighing a full Spotlight replacement.
