/// The plugin-authoring reference an agent reads before writing a plugin.
/// `stackbarctl docs` prints it, the authoring MCP server returns it from
/// `stackbar_docs`, and `llms.txt` at the repository root is a copy (a test keeps
/// them equal).
public enum AuthoringGuide {
    public static let text = #"""
# Stackbar plugin authoring

A Stackbar plugin is one Swift file that imports StackbarKit. Stackbar builds it, runs
it in its own process, and draws what it declares natively in the macOS menu
bar, a panel, a window, a widget and its own page in Settings. Agents can
call its tools.

## Shape

```swift
import StackbarKit
import Foundation

@main
final class Weather: StackbarPlugin {
    static let manifest = Manifest(
        id: "dev.example.weather",          // reverse-DNS, stable forever
        name: "Weather",
        summary: "Today's temperature.",
        surfaces: [.menuBar, .panel, .settings], // also .window, .widget
        triggers: [.launch, .minutes(15), .wake],
        capabilities: [.network("api.open-meteo.com")]
    )

    var temperature: Double?
    @Stored("unit") var unit = "C"          // saved by the host across restarts

    func refresh() async throws {          // runs when a trigger fires
        struct Reply: Decodable { struct Current: Decodable { let temperature_2m: Double }; let current: Current }
        let reply: Reply = try await Stackbar.getJSON("https://api.open-meteo.com/v1/forecast?latitude=52.5&longitude=13.4&current=temperature_2m")
        temperature = reply.current.temperature_2m
    }

    var menuBar: ViewContent {
        Label(temperature.map { "\(Int($0))°" } ?? "–", symbol: "thermometer.medium")
    }

    var panel: ViewContent {
        Text("Berlin").style(.headline)
        Text(temperature.map { "\(Int($0))°\(unit)" } ?? "–").style(.title)
    }

    var settings: ViewContent {             // Stackbar Settings → Plugins → Weather
        Section("Units") {
            Picker("Unit", options: ["C", "F"], selection: unit) { self.unit = $0 }
        }
    }

    var tools: [AgentTool] {
        AgentTool("temperature", description: "Current temperature in Berlin") { _ in "\(self.temperature ?? .nan)" }
    }
}
```

State is ordinary properties. After `refresh()`, an action, a tool call or a
topic message, Stackbar re-renders and sends only surfaces that changed. Code
never runs concurrently with itself, so no locks. Throwing from `refresh()`
logs the error and keeps the last render.

Keep the panel for doing things: it opens many times a day. Preferences
people set once go in `settings`, which Stackbar shows on the plugin's page in
its Settings window (the gear in the panel footer, or ⌘, while the panel is
open). Quick controls used mid-task, like Pause, stay in the panel.

A left click on the menu-bar item opens the panel. To make it do something
instead (start or stop a timer), return an action from `menuBarClick`; a
right click still opens the panel, and the title is the item's tooltip:

```swift
var menuBarClick: MenuBarAction? {
    running ? MenuBarAction("Click to stop") { self.stop() } : MenuBarAction("Click to start") { self.start() }
}
```

## Commands

Commands are what people find by name in the palette (⌃⌥Space), give an
alias or a hotkey in Settings → Commands, start from a
`stackbar://commands/<plugin-id>/<command-id>?arg=value` link, and (unless
`.stackbarOnly()`) from Spotlight and Shortcuts: commands show in ⌘Space
results, and "Run Stackbar Command" in Shortcuts takes any of them, with its
first argument as the input. A plugin can have commands
and no menu-bar item at all: leave `.menuBar` out of `surfaces`.

```swift
var commands: [Command] {
    // A run command does its work and says what happened.
    Command("toggle", title: "Toggle Stay Awake", symbol: "cup.and.saucer") { invocation in
        try await self.toggle()
        return .message(self.awake ? "Staying awake" : "Sleep allowed")
    }
    // Up to three arguments, typed inline in the palette.
    Command("convert", title: "Convert Temperature") { invocation in
        .copy(self.convert(invocation["degrees"] ?? "0", to: invocation["unit"]))
    }
    .argument("degrees", placeholder: "20")
    .argument("unit", required: false, default: "F", options: ["C", "F"])

    // A view command opens a live view in the palette. `search` runs when the
    // query or an argument changes (fetch here); `body` only reads state.
    Command("search", title: "Search Pull Requests", keywords: ["github"])
        .view(search: { invocation in
            self.results = try await self.find(invocation.text)
        }) { _ in
            List(self.results) { pr in
                Row(pr.title, key: pr.id)
                    .action("Open") { Stackbar.open(pr.url) }
                    .navigate("Details", to: "details", arguments: ["id": pr.id])
            }
        }
    Command("details", title: "Pull Request").view { invocation in
        Text(invocation["id"] ?? "")
    }
    .stackbarOnly()
}
```

Results: `.done`, `.message(text)`, `.open(url:app:)`, `.copy(text)`,
`.paste(text, cursorFromEnd:)` (needs `.clipboard`; puts the user's clipboard
back afterwards and keeps the paste out of clipboard history), `.failure(text)`.
The host performs them under the plugin's capabilities. Ids are lowercase letters,
digits and `-`, stable forever (aliases, hotkeys and links remember them);
titles can change. `invocation["name"]` is nil when an argument was left
empty; `invocation.source` says where it started (`.palette`, `.hotkey`,
`.link`, `.spotlight`, `.shortcuts`, ...) and `invocation.context` carries the
front app, window title and selected text for plugins with `.context`, read
when the command was triggered, before Stackbar's palette took focus.

A form in a view (or a panel) submits every field at once:

```swift
Form(submit: "Add") {
    FormField.text("Name", name: "name", error: nameError)
    FormField.multiline("Body", name: "body")
    FormField.picker("Kind", name: "kind", options: ["a", "b"])
    FormField.toggle("Pinned", name: "pinned")
    FormField.application("Open with", name: "app")
} onSubmit: { values in
    let name = values.string("name") ?? ""
    self.nameError = name.isEmpty ? "Give it a name" : nil
}
```

## Templates (quicklinks and snippets)

`Template` fills Raycast-style placeholders, so links and text can ask for
input and pick up what the user copied or selected:

```swift
let template = try Template("https://github.com/search?q={argument name=\"query\"}&type={argument name=\"type\" default=\"code\"}")
template.arguments            // query (required), type (default code): use them as the command's arguments
let url = try template.render(invocation.arguments, in: Template.Environment(clipboard: copied, selection: invocation.context?.selectedText), encoding: .url).text
```

Placeholders: `{argument name= default= options="a, b"}` (3 at most),
`{clipboard}`, `{selection}`, `{date}`, `{time}`, `{datetime}`, `{day}` (each with
`format="yyyy-MM-dd"`, `offset="+2d -3h"`, `locale="fr-FR"`), `{uuid}`,
`{cursor}` (`render(...).cursorFromEnd` for `.paste(text, cursorFromEnd:)`),
`{snippet name=}` (from `environment.snippets`, one level). Modifiers chain
after `|`: `uppercase`, `lowercase`, `trim`, `percent-encode`,
`json-stringify`, `raw`. With `encoding: .url` values are percent-encoded
(not the template's own text) unless `raw`. A brace group that isn't a
placeholder stays as written; `template.unrecognized` lists likely typos
for a form to flag. Errors name the placeholder that failed.

## Views (ViewContent bodies, SwiftUI-like; `if`, `for`, `switch` work)

- `Text(s).style(.title|.headline|.body|.caption|.monospaced).role(r)`
- `Label(title, symbol: "sf.symbol").role(r)`
- `VStack(spacing:) { }`, `HStack { }`, `Section("Title") { }`, `Divider()`
- `List(items, searchable: true) { item in Row(...) }`, `ForEach(items) { }`
- `Row(title, subtitle:, symbol:, key: stableID).badge(text, role:).progress(v).action("Open", shortcut: "cmd+return") { }`
  The first action is the click; all actions are in the context menu.
  In a searchable list the host adds the keyboard: typing filters, ↑↓ select,
  Return runs the first action, ⌘1–⌘9 the nth row's, and action shortcuts
  apply to the selected row. Don't declare ⌘1–⌘9 yourself. Matching is
  fuzzy ("gthb" finds "GitHub") and plain rows are ranked best first.
  `.preview(text:imageID:caption:)` shows the full text or a kept clipboard
  image under the list while the row is selected; search looks through it.
- `Row(...).appIcon("com.apple.Safari")` draws that app's icon instead of the symbol (the symbol stays as the fallback).
- `Badge(text, role:)`, `ProgressBar(label, value:, total:, style: .ring(lineWidth: 6))`, `LabeledContent(label, value:)`
- `Chart(label, values: [Double], kind: .line|.bar|.area|.donut|.heatmap, role:, labels: ["Mon", …], unit: "h", goal: 4, highlight: 6)`
  `labels` name the points (or a donut's slices), `unit` follows values, `goal`
  draws a target line, `highlight` emphasizes one point. `.heatmap` takes one
  value per day, oldest first and today last, and draws week columns like a
  contribution graph (minimumStackbar 0.11.0). Large values are shortened on
  axes (`1.9B`), and a donut lists each slice's share. A `Section` without
  rows is drawn as a card, so group charts and values in one; an `HStack` of
  such sections makes a row of stat tiles.
- `Button(title, symbol:, role:) { }`, `Toggle(title, isOn:) { newValue in }`
- `TextField(placeholder, text:) { submitted in }`, `Picker(title, options:, selection:, style: .segmented) { choice in }`
- `Slider(title, value:, in: 0...10, step:) { value in }`, `Link(title, url:)`
- `ContentUnavailableView(title, symbol:, message:)`

Roles: `.primary .secondary .accent .success .warning .critical`. Without
styling the host picks colors and sizes per surface and appearance, which is
right for most plugins. In the menu bar `.accent` and `.success` draw in the
bar's own color (blue vanishes on it), so show an active state with the
symbol, such as a filled variant.

### Custom look (minimumStackbar 0.12.0)

When a plugin wants its own look, style it like SwiftUI. Modifiers apply in
the order written:

- `.font(size:, weight: .heavy, design: .rounded, monospacedDigit: true)`, `.foreground(paint)`
- `.padding(8)`, `.padding(horizontal:, vertical:)`, `.frame(width:, height:, fillWidth: true, alignment: .center)`
- `.background(paint, in: .capsule | .circle | .rectangle | .roundedRectangle(cornerRadius: 12))`, `.border(paint, width:, in:)`
- `.clipShape(shape)`, `.cornerRadius(12)`, `.shadow(radius:, x:, y:)` (cast by the background's shape when there is one), `.opacity(0.5)`, `.animation(.spring)`
- `.accessibilityLabel("Start")`: give one to every button without text
- Paints: `.hex("#F28C38", dark: "#FF9F4F")` (always give a dark variant for
  backgrounds), `.role(.accent)`, `.gradient(["#F28C38", "#FFB36B"], angle: 90)`
- `ZStack { }` layers views; `VStack(alignment: .center)`, `HStack(alignment: .start)`; `Spacer()`
- `Circle()`, `Capsule()`, `Rectangle()`, `RoundedRectangle(cornerRadius:)` with `.fill(paint)` and `.stroke(paint, lineWidth:)`
- `Image(systemName: "play.fill")`, sized by `.font(size:)` and colored by `.foreground`
- `Button(key: "start") { … } label: { Image(systemName: "play.fill").frame(width: 72, height: 72).background(orange, in: .circle) }` makes anything a button
- `TimerText(TimeRange(start:, end:))` counts down to `0:00` on its own (`countsDown: false` counts up), and
  `ProgressBar(timing: range, style: .ring(lineWidth: 6))` fills with the clock. Render once when the
  timer starts, not every second; an `.every(.seconds(1))` trigger lets `refresh()` notice the end
  (re-renders that come out the same are not sent).
- `Stackbar.play(.glass)` plays a system sound (at most 10 a minute).

### The shared look (minimumStackbar 0.13.0)

Store plugins share one design system, so build panels from it rather than
from raw modifiers. Pick one `Theme` for the plugin (`.blue .indigo .violet
.pink .red .orange .amber .green .teal .cyan .graphite`); `.success`,
`.warning`, `.critical`, `.neutral` and `.info` are for states only. Every
theme passes 4.5:1 in both modes.

- `PanelHeader("3 running", subtitle: "Updated 10:42", symbol: "shippingbox.fill", theme: theme) { IconButton(…) }`
  first in the panel. The footer names the plugin, so the title is the state.
- `HeroCard(theme:) { }` the one thing an instrument panel is about (a track, a timer, the next meeting).
- `Card("Title", detail: "8") { }` groups charts and values; native `Row`s stay in a `List` or `Section`.
- `StatTile("Today", value: "1.2M", caption: "$4.12", symbol: "bolt.fill", theme:)` in an `HStack` of two or three.
- `Metric("4:32", unit: "left", caption: "Until 17:30")`, `Gauge(value:, total:, theme:) { Text("40%") }` (or `Gauge(timing:)`),
  `Meter("Memory", reading: "12 of 16 GB", value: 0.75, theme:)`
- `Pill("Failing", symbol: "xmark", theme: .critical)`, `StatusDot(.success)`, `Banner("Showing numbers from 5 min ago")`
- `IconButton("arrow.clockwise", label: "Refresh", theme:, prominence: .plain | .tinted | .filled) { }`,
  `ActionButton("Upgrade All", symbol:, theme:, prominent: true) { }`, `Chip("Running", theme:, selected:) { }`
- `EmptyState("Nothing running", symbol:, message:, theme:) { ActionButton(…) }` in place of `ContentUnavailableView` in panels
- `.typography(.hero | .metric | .stat | .title | .headline | .body | .caption | .captionNumber | .overline)`,
  `Space.xs…xl` (4–24), `Radius.small | .medium | .large`, `Paint.surface | .raised | .hairline`

Leave text in the system's `.primary` and `.secondary` roles and color it with
the theme only for emphasis. Keep the menu bar plain: a symbol, at most one
short value, `.secondary` when idle.

`stackbarctl render` flags text under 4.5:1 contrast in light or dark mode
(see-through backgrounds are measured over what is behind them) and buttons
without text. `render --png <dir>` draws it on a Mac, and
`--dark` draws dark mode. The menu bar ignores styling so the bar stays
legible, but shows symbols, timers and timed rings.

Action ids come from content: `button/<title>`, `toggle/<title>`,
`row/<key>/<action title>`, `field/<placeholder>`, `picker/<title>`,
`slider/<title>`. Pass `key:` when titles repeat or change.

## Host services (`Stackbar.*`), checked against capabilities

| Call | Needs |
| --- | --- |
| `try await Stackbar.getJSON(url, as: T.self, headers:)`, `Stackbar.get`, `Stackbar.http(HTTPRequest)` | `.network("host")`, `*.example.com` for subdomains |
| `try await Stackbar.secret("NAME")` returns `String?` (nil: the user hasn't entered it; Stackbar asks them) | `.secret(name: "NAME")`; names are letters, digits, `_`, `-`, `.` |
| A server the user picks (a self-hosted proxy, GitHub Enterprise): read its URL with `Stackbar.secret("NAME")`, then `Stackbar.getJSON` to it | `.userServer(secret: "NAME")`: the plugin may reach that URL's host only (minimumStackbar 0.11.0) |
| `try await Stackbar.oauthToken("github")` | `.oauth(OAuthProvider(name:, authorizeURL:, tokenURL:, clientID:, scopes:))` |
| `Stackbar.publish("topic", payload)`; receive with `.topic(name:)` trigger and `func receive(topic:payload:from:)` | nothing |
| `Stackbar.notify(title, body:, actions: [NotificationAction("Join", url:)])`, `Stackbar.alert(title, body:, actions:)` (full screen, one a minute), `Stackbar.open(url)`, `Stackbar.copy(text)` | nothing |
| `try await Stackbar.open(url, with: "com.apple.Safari")`; links other than https, http, mailto, tel and meeting apps, and files or folders | `.openURLs(schemes: ["slack"])`; `["*"]` for any scheme and paths |
| `try await Stackbar.run("brew", ["outdated", "--json=v2"], timeout: .seconds(120))` returns `RunResult` (status, stdout, stderr, text, truncated, timedOut); a non-zero exit is not thrown | `.run(commands: ["brew"])` |
| `for try await event in Stackbar.stream("docker", ["logs", "-f", id]) { switch event { case .stdout(let data), .stderr(let data): …; case .exit(let exit): … } }`; leaving the loop stops it | `.run(commands: ["docker"])` |
| `invocation.context` in commands, or `try await Stackbar.context()` now: frontmostApp, windowTitle, selectedText (nil when the app doesn't share it); `try await Stackbar.finderSelection()` returns paths | `.context` |
| `@Stored("key") var x = default` (any Codable, 1 MB per plugin) | nothing; `.storage(megabytes: 16)` for up to 64 MB |
| `try await Stackbar.chooseFile(types: ["json"])` returns `ChosenFile?` (name, data; 5 MB at most), `try await Stackbar.saveFile("x.json", data:)` returns the path; nil when the user cancels | nothing (the user picks) |
| `try await Stackbar.resolveApplication("Google Chrome")` returns a bundle id from an app's name, path or id | nothing |
| `try await Stackbar.clipboard()` returns `ClipboardItem?` (kind, text, files, imageID, contentID for formatted copies, sourceAppID, concealed, changeCount); hear every copy with the `.clipboard` trigger | `.clipboard` |
| `try await Stackbar.setClipboard(.text/.files/.image(id:)/.stored(id:))`, `try await Stackbar.paste(content, restoringClipboard: true, cursorFromEnd: n)` (into the app the user was in; needs Accessibility for Stackbar; restoring puts the user's copy back after half a second, marks the paste transient, and n ← presses place the caret) | `.clipboard` |
| `try await Stackbar.keepAwake(display:, reason:)`, `Stackbar.allowSleep()`; the host releases it if the plugin stops | `.power` |
| `try await Stackbar.systemStatus()`: batteryLevel, onACPower, lowPowerMode, runningApps, externalDisplays, networkBytesReceived, vpnActive | `.power` |
| `try await Stackbar.calendarEvents(from:, to:)` returns `[CalendarEvent]` (title, start, end, location, notes, url, participation), 31 days at most | `.calendar` |

Don't use URLSession, Process or files directly: plugins run sandboxed and
only host calls are allowed through. Errors from host calls say which
capability to add.

Commands run by the host, never through a shell: arguments arrive exactly as
given. A bare name is found in /opt/homebrew/bin, /usr/local/bin, /usr/bin,
/bin, /usr/sbin or /sbin (never the user's PATH), and the user approves the
path it resolves to; if it later resolves elsewhere, the run fails until they
approve again. The environment is PATH, HOME, LANG and TMPDIR (the plugin's
own temporary folder) plus `environment:`; the working directory is the
plugin's own folder unless `workingDirectory:` names one inside a `.files`
path. At most 4 at once, 8 MB of output a channel, a 60 second timeout by
default and 10 minutes at most; on timeout the whole process group is
stopped. Declaring a shell or interpreter (sh, zsh, python3, node,
osascript, ...) is allowed but the install sheet warns it can run any program;
prefer the tool itself.

Selected text comes through Accessibility and is cut to 100 KB. Apps built
on the standard macOS text views share it; others may not, so always handle
nil (offer the clipboard, or an argument, instead). On Linux and in `stackbarctl`, the context is simulated: pass
`--selected-text` and `--frontmost-app` (or `selected_text` and
`frontmost_app` to the MCP command tools).

Triggers: `.launch`, `.every(.seconds(30))`, `.minutes(5)`, `.wake`,
`.file(path: "~/x")`, `.topic(name: "t")`, `.clipboard`.

`Manifest(..., hotkey: "cmd+shift+v")` opens the panel from anywhere.
`minimumStackbar: "0.10.0"` names the oldest Stackbar whose StackbarKit the
source compiles against; a plugin index hides Install on older apps.
`homepage: "https://..."` links the plugin's README from the store.

## Loop

1. `stackbar_new` (or write the file), then `stackbar_build`: fix every diagnostic.
2. `stackbar_render` (text, or png on a Mac) and read the action ids.
3. `stackbar_send_event` with an id, render again; `stackbar_call_tool` for tools.
   Commands: `stackbar_list_commands`, `stackbar_run_command`, and
   `stackbar_render_command` for a view (then `stackbar_send_event` inside it;
   a form's value is an object of its fields).
4. `stackbar_logs` when something is off. Stray `print` goes to the log.

From a terminal: `stackbarctl build|render|manifest <file.swift>`,
`stackbarctl render <file> --event <id>`, `stackbarctl commands <file>`,
`stackbarctl run <file> <command> --arg name=value`,
`stackbarctl render <file> --command <id> --query <text>`. Outside the app the clipboard, battery
and calendar are simulated: `stackbarctl render <file> --copy "text"` (or the
`stackbar_simulate_copy` tool) pretends the user copied something, and
`STACKBAR_CALENDAR=events.json` sets the calendar (a sample day otherwise).
"""#
}
