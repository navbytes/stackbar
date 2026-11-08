# Design

## Root search

`RootSearchGate.accepts(spec, text, preference)` decides who is asked:
root-search view, enabled, `inRootSearch`, and `rootPattern` (if any) matching
the whole text (`NSRegularExpression`, anchored, full range; a pattern that
doesn't compile takes nothing, and `CommandSpec.problems` reports it).
`PaletteSession.feedRootSearch` closes views that stop being accepted so rows
for older text don't linger.

Timing: `rootFedAt[key]` is set when a view is opened or given new text; the
first render that finds the view no longer searching records the elapsed
time in `CommandCenter.rootBudget`.

Ranking lives in `PaletteSection.rank` (host core, tested): stable sort by
`leads` (pattern matched), then the best `TextMatch.score` of the query over
the section's row titles; the split into leading and following sections keeps
the old prefix rule.

## Empty menu bar

`ViewNode.isNothing` is true only for stacks with no leaves, which is what
the runtime sends for empty content. A tree of panel-only nodes still shows
the plugin's name (`isBlankInMenuBar`), so nothing changes for existing
plugins. `menuBarIdle` is stored per source path so the item doesn't flash in
at launch, and `showsInMenuBar` includes it, which reuses the headless panel
path (palette "Open X", hotkey, centered panel).

## Agent consent

`agent-tools.json`: `[pluginID: [tool: Bool]]`, only choices that differ from
the default. The pseudo-tool `panel` stands for `stackbar_read`. `RuntimeTools`
filters listing and calls through it; `stackbarctl agent <files>` passes no
store and applies only the defaults.

## Widget presses

The extension can't reach plugins, and widget intents run in the extension.
`WidgetActionIntent.perform` writes one JSON file per press under
`<app group>/WidgetActions` and posts `io.navbytes.stackbar.widget-action`
on the Darwin center. The app drains the directory on that notification and at
launch, drops presses older than 60 s, and calls `PluginController.send`, as a
panel click would. Action ids are the same table the panel uses (the runtime
registers every surface's handlers in one context). The plugin's next widget
tree reloads the timeline. If Stackbar isn't running the press is dropped.

`NodeView` takes `stackbarWidgetButton` from the environment: in a read-only
surface, buttons, toggles (sending the flipped value), tappables and rows (the
first action, unless it navigates) are wrapped by it. Snapshots and the
panel never set it.

## Tests

`SurfaceFitTests` (gate, budget, ranking, preferences decoding, consent,
inbox, `isNothing`, ledger) and `AgentConsentGatewayTests` (a fixture plugin
behind the gateway). The widget and Settings UI build in the macOS and Xcode
CI jobs.

## Mac checks

1. Typing `ABC-123` shows Jira first; `safari` doesn't wake Jira.
2. Settings → Commands: turn off File Search's root search; files stop showing.
3. App Switcher with "Only when something's wrong" leaves the bar; its panel
   opens from the palette.
4. Settings → Agents: Clipboard History's tools are off until switched on.
5. Stay Awake widget: the button toggles it; Music widget: play/pause works.
