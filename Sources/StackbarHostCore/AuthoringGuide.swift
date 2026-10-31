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
- `Badge(text, role:)`, `ProgressBar(label, value:, total:)`, `LabeledContent(label, value:)`
- `Chart(label, values: [Double], kind: .line|.bar|.area|.donut, role:, labels: ["Mon", …], unit: "h", goal: 4, highlight: 6)`
  `labels` name the points (or a donut's slices), `unit` follows values, `goal`
  draws a target line, `highlight` emphasizes one point. A `Section` without
  rows is drawn as a card, so group charts and values in one.
- `Button(title, symbol:, role:) { }`, `Toggle(title, isOn:) { newValue in }`
- `TextField(placeholder, text:) { submitted in }`, `Picker(title, options:, selection:) { choice in }`
- `Slider(title, value:, in: 0...10, step:) { value in }`, `Link(title, url:)`
- `ContentUnavailableView(title, symbol:, message:)`

Roles: `.primary .secondary .accent .success .warning .critical`. Never pick
colors or sizes; the host does, per surface and appearance.

Action ids come from content: `button/<title>`, `toggle/<title>`,
`row/<key>/<action title>`, `field/<placeholder>`, `picker/<title>`,
`slider/<title>`. Pass `key:` when titles repeat or change.

## Host services (`Stackbar.*`), checked against capabilities

| Call | Needs |
| --- | --- |
| `try await Stackbar.getJSON(url, as: T.self, headers:)`, `Stackbar.get`, `Stackbar.http(HTTPRequest)` | `.network("host")`, `*.example.com` for subdomains |
| `try await Stackbar.secret("NAME")` returns `String?` (nil: the user hasn't entered it; Stackbar asks them) | `.secret(name: "NAME")`; names are letters, digits, `_`, `-`, `.` |
| `try await Stackbar.oauthToken("github")` | `.oauth(OAuthProvider(name:, authorizeURL:, tokenURL:, clientID:, scopes:))` |
| `Stackbar.publish("topic", payload)`; receive with `.topic(name:)` trigger and `func receive(topic:payload:from:)` | nothing |
| `Stackbar.notify(title, body:, actions: [NotificationAction("Join", url:)])`, `Stackbar.alert(title, body:, actions:)` (full screen, one a minute), `Stackbar.open(url)`, `Stackbar.copy(text)` | nothing |
| `@Stored("key") var x = default` (any Codable, 1 MB per plugin) | nothing |
| `try await Stackbar.clipboard()` returns `ClipboardItem?` (kind, text, files, imageID, contentID for formatted copies, sourceAppID, concealed, changeCount); hear every copy with the `.clipboard` trigger | `.clipboard` |
| `try await Stackbar.setClipboard(.text/.files/.image(id:)/.stored(id:))`, `try await Stackbar.paste(content)` (into the app the user was in; needs Accessibility for Stackbar) | `.clipboard` |
| `try await Stackbar.keepAwake(display:, reason:)`, `Stackbar.allowSleep()`; the host releases it if the plugin stops | `.power` |
| `try await Stackbar.systemStatus()`: batteryLevel, onACPower, lowPowerMode, runningApps, externalDisplays, networkBytesReceived, vpnActive | `.power` |
| `try await Stackbar.calendarEvents(from:, to:)` returns `[CalendarEvent]` (title, start, end, location, notes, url, participation), 31 days at most | `.calendar` |

Don't use URLSession, Process or files directly: plugins run sandboxed and
only host calls are allowed through. Errors from host calls say which
capability to add.

Triggers: `.launch`, `.every(.seconds(30))`, `.minutes(5)`, `.wake`,
`.file(path: "~/x")`, `.topic(name: "t")`, `.clipboard`.

`Manifest(..., hotkey: "cmd+shift+v")` opens the panel from anywhere.

## Loop

1. `stackbar_new` (or write the file), then `stackbar_build`: fix every diagnostic.
2. `stackbar_render` (text, or png on a Mac) and read the action ids.
3. `stackbar_send_event` with an id, render again; `stackbar_call_tool` for tools.
4. `stackbar_logs` when something is off. Stray `print` goes to the log.

From a terminal: `stackbarctl build|render|manifest <file.swift>`,
`stackbarctl render <file> --event <id>`. Outside the app the clipboard, battery
and calendar are simulated: `stackbarctl render <file> --copy "text"` (or the
`stackbar_simulate_copy` tool) pretends the user copied something, and
`STACKBAR_CALENDAR=events.json` sets the calendar (a sample day otherwise).
"""#
}
