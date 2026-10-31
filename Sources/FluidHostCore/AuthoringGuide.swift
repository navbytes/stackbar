/// The plugin-authoring reference an agent reads before writing a plugin.
/// `fluidctl docs` prints it, the authoring MCP server returns it from
/// `fluid_docs`, and `llms.txt` at the repository root is a copy (a test keeps
/// them equal).
public enum AuthoringGuide {
    public static let text = #"""
# Fluid plugin authoring

A Fluid plugin is one Swift file that imports FluidKit. Fluid builds it, runs
it in its own process, and draws what it declares natively in the macOS menu
bar, a panel, a window and a widget. Agents can call its tools.

## Shape

```swift
import FluidKit
import Foundation

@main
final class Weather: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.example.weather",          // reverse-DNS, stable forever
        name: "Weather",
        summary: "Today's temperature.",
        surfaces: [.menuBar, .panel],        // also .window, .widget
        triggers: [.launch, .minutes(15), .wake],
        capabilities: [.network("api.open-meteo.com")]
    )

    var temperature: Double?
    @Stored("unit") var unit = "C"          // saved by the host across restarts

    func refresh() async throws {          // runs when a trigger fires
        struct Reply: Decodable { struct Current: Decodable { let temperature_2m: Double }; let current: Current }
        let reply: Reply = try await Fluid.getJSON("https://api.open-meteo.com/v1/forecast?latitude=52.5&longitude=13.4&current=temperature_2m")
        temperature = reply.current.temperature_2m
    }

    var menuBar: ViewContent {
        Label(temperature.map { "\(Int($0))°" } ?? "–", symbol: "thermometer.medium")
    }

    var panel: ViewContent {
        Text("Berlin").style(.headline)
        Picker("Unit", options: ["C", "F"], selection: unit) { self.unit = $0 }
    }

    var tools: [AgentTool] {
        AgentTool("temperature", description: "Current temperature in Berlin") { _ in "\(self.temperature ?? .nan)" }
    }
}
```

State is ordinary properties. After `refresh()`, an action, a tool call or a
topic message, Fluid re-renders and sends only surfaces that changed. Code
never runs concurrently with itself, so no locks. Throwing from `refresh()`
logs the error and keeps the last render.

## Views (ViewContent bodies, SwiftUI-like; `if`, `for`, `switch` work)

- `Text(s).style(.title|.headline|.body|.caption|.monospaced).role(r)`
- `Label(title, symbol: "sf.symbol").role(r)`
- `VStack(spacing:) { }`, `HStack { }`, `Section("Title") { }`, `Divider()`
- `List(items, searchable: true) { item in Row(...) }`, `ForEach(items) { }`
- `Row(title, subtitle:, symbol:, key: stableID).badge(text, role:).progress(v).action("Open", shortcut: "cmd+return") { }`
  The first action is the click; all actions are in the context menu.
- `Badge(text, role:)`, `ProgressBar(label, value:, total:)`, `LabeledContent(label, value:)`
- `Chart(label, values: [Double], kind: .line|.bar)`
- `Button(title, symbol:, role:) { }`, `Toggle(title, isOn:) { newValue in }`
- `TextField(placeholder, text:) { submitted in }`, `Picker(title, options:, selection:) { choice in }`
- `Slider(title, value:, in: 0...10, step:) { value in }`, `Link(title, url:)`
- `ContentUnavailableView(title, symbol:, message:)`

Roles: `.primary .secondary .accent .success .warning .critical`. Never pick
colors or sizes; the host does, per surface and appearance.

Action ids come from content: `button/<title>`, `toggle/<title>`,
`row/<key>/<action title>`, `field/<placeholder>`, `picker/<title>`,
`slider/<title>`. Pass `key:` when titles repeat or change.

## Host services (`Fluid.*`), checked against capabilities

| Call | Needs |
| --- | --- |
| `try await Fluid.getJSON(url, as: T.self, headers:)`, `Fluid.get`, `Fluid.http(HTTPRequest)` | `.network("host")`, `*.example.com` for subdomains |
| `try await Fluid.secret("NAME")` returns `String?` (nil: the user hasn't entered it; Fluid asks them) | `.secret(name: "NAME")` |
| `try await Fluid.oauthToken("github")` | `.oauth(OAuthProvider(name:, authorizeURL:, tokenURL:, clientID:, scopes:))` |
| `Fluid.publish("topic", payload)`; receive with `.topic(name:)` trigger and `func receive(topic:payload:from:)` | nothing |
| `Fluid.notify(title, body:)`, `Fluid.open(url)`, `Fluid.copy(text)` | nothing |
| `@Stored("key") var x = default` (any Codable, 1 MB per plugin) | nothing |
| `try await Fluid.clipboard()` returns `ClipboardItem?` (kind, text, files, imageID, sourceAppID, concealed, changeCount); hear every copy with the `.clipboard` trigger | `.clipboard` |
| `try await Fluid.setClipboard(.text/.files/.image(id:))`, `try await Fluid.paste(content)` (into the app the user was in; needs Accessibility for Fluid) | `.clipboard` |
| `try await Fluid.keepAwake(display:, reason:)`, `Fluid.allowSleep()`; the host releases it if the plugin stops | `.power` |
| `try await Fluid.systemStatus()`: batteryLevel, onACPower, lowPowerMode, runningApps | `.power` |
| `try await Fluid.calendarEvents(from:, to:)` returns `[CalendarEvent]` (title, start, end, location, notes, url, participation), 31 days at most | `.calendar` |

Don't use URLSession, Process or files directly: plugins run sandboxed and
only host calls are allowed through. Errors from host calls say which
capability to add.

Triggers: `.launch`, `.every(.seconds(30))`, `.minutes(5)`, `.wake`,
`.file(path: "~/x")`, `.topic(name: "t")`, `.clipboard`.

`Manifest(..., hotkey: "cmd+shift+v")` opens the panel from anywhere.

## Loop

1. `fluid_new` (or write the file), then `fluid_build`: fix every diagnostic.
2. `fluid_render` (text, or png on a Mac) and read the action ids.
3. `fluid_send_event` with an id, render again; `fluid_call_tool` for tools.
4. `fluid_logs` when something is off. Stray `print` goes to the log.

From a terminal: `fluidctl build|render|manifest <file.swift>`,
`fluidctl render <file> --event <id>`. Outside the app the clipboard, battery
and calendar are simulated: `fluidctl render <file> --copy "text"` (or the
`fluid_simulate_copy` tool) pretends the user copied something, and
`FLUID_CALENDAR=events.json` sets the calendar (a sample day otherwise).
"""#
}
