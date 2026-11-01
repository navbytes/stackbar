# Design

## `Template` (StackbarKit, pure Swift, Linux-tested)

```swift
let template = try Template("https://github.com/{argument name=\"org\" default=\"navbytes\"}/{argument name=\"repo\"}/issues?q={argument name=\"q\" | percent-encode}")
template.arguments          // [ArgumentSpec(name: "org", default: "navbytes"), ("repo"), ("q")] → the command's arguments
let text = try template.render(values: ["repo": "stackbar", "q": "is:open"], in: environment, encoding: .url)
```

- **Grammar:**
  - Placeholders look like `{name key="value" key=value | modifier | modifier}`.
  - `\{` is a literal brace.
  - An unknown name stays as written, which is how Raycast treats a
    misspelled placeholder, so nobody's text is silently lost.
- **Placeholders, all in Raycast's syntax:**
  - `{argument name= default= options=}`: at most 3 distinct names.
    Repeats of a name share one value. `default` makes it optional, and
    `options` makes it a choice.
  - `{clipboard}`: needs `.clipboard`. `offset=N` for older entries is parsed
    but answers "needs Clipboard History sharing", which is not built yet.
  - `{selection}`: needs `.context`, after `host-run-and-context`. Before
    that, it renders empty and logs once.
  - `{date}`, `{time}`, `{datetime}`, `{day}`, each with `format=`,
    `offset="+2d -3h"` and `locale="fr-FR"`.
  - `{uuid}`.
  - `{cursor}` (snippets only) and `{snippet name=}` (snippets only, one level
    deep).
- **Modifiers:** `uppercase`, `lowercase`, `trim`, `percent-encode`,
  `json-stringify` and `raw`, chained left to right.
- **Encoding.** With `encoding: .url`, argument, clipboard and selection
  values are percent-encoded unless `raw` is given, as Raycast does for
  quicklinks. Text in the template itself is never touched.
- **Environment.** Clipboard, selection, now, time zone, locale and the uuid
  generator are injected, so tests are deterministic.
- **Errors.** A missing required argument, a bad offset and a bad format all
  say which placeholder failed and why.

## The Quicklinks plugin

```swift
struct Quicklink: Codable, Identifiable {
    var id: UUID
    var name: String
    var link: String          // template
    var openWith: String?     // bundle id
    var tags: [String]
    var symbol: String?
}
@Stored("quicklinks") var links: [Quicklink] = []
```

### Manifest

```swift
surfaces: [.panel, .settings]
capabilities: [.openURLs(schemes: ["*"]), .clipboard, .context]
hotkey: nil                   // the user can set one in Settings → Commands
```

### Commands

- **One per quicklink:** `ql-<uuid>`, titled with its name. Its arguments
  come from `template.arguments`, and its keywords are the tags and host.
  Running it renders the template and returns `.open(url, app: openWith)`.
  A rendering error returns `.failure` naming the placeholder.
- **"Search Quicklinks"** (view): rows with the name, the link shown with its
  placeholders, and tag badges.
  - Return opens the link, asking for any arguments inline.
  - ⌘K: Open, Open With…, Copy Link, Edit, Duplicate, Delete.
  - ⌘P filters by tag.
- **"Create Quicklink"** (view): a form with Name, Link, Open With (app
  field), Tags and Symbol. It checks that the template parses and that the
  link is a URL, an absolute path or `~/`.
- **"Import Quicklinks"** and **"Export Quicklinks"** (run).

### Links and paths

- `~/x` and `/x` become file URLs. Anything with `scheme://` or `scheme:` is
  a URL. Anything else gets `https://` in front, so `github.com` works.
- **`Stackbar.open(url, with: bundleID?)`** sends
  `HostCall.open(OpenRequest(url:, app:))`. The host:
  - resolves the bundle id with `NSWorkspace.urlForApplication(withBundleIdentifier:)`;
  - opens with `NSWorkspace.open(_:withApplicationAt:configuration:)`;
  - checks the scheme against the safe defaults (https, http, mailto, tel,
    meeting apps) plus `.openURLs`;
  - for file paths, checks they exist and refuses `.app` bundles and
    executables unless `openWith` is set, so a link can't quietly launch a
    program.
- The current `openURL` call stays as it is for older plugins.

### Import and export

- **Raycast JSON:** an array of `{name, link, iconName?, openWith?}`.
  - `openWith` may be an app name or path. The host resolves it to a bundle id
    with `HostCall.resolveApplication`, and an unknown app is imported without
    one, with a note.
  - Duplicates (same name and link) are skipped. The importer reports
    "Imported 42, skipped 3 duplicates".
- **Export** writes the same format, so the file goes back into Raycast too.
- **`HostCall.chooseFile(types:)`** returns the chosen file's contents (at
  most 5 MB). **`HostCall.saveFile(name:, data:)`** writes where the user
  says. Both show the standard panels and need no capability, because the
  user picks the file.

### Icons

Rows use an SF Symbol by kind: a globe for web, a folder for paths, an app
symbol for app schemes. The row shows the chosen app's icon when `openWith`
is set, through a new `RowNode.icon = .app(bundleID)` that the host draws.
Favicons would need network access to every host the user links to, so they
are left out.

## Tests

- Template: the grammar, every placeholder and modifier, URL encoding, a
  missing argument, unknown placeholders, offsets across month ends and time
  zones, Raycast samples taken from its manual.
- Plugin: commands generated from links, create and edit validation, import
  of Raycast samples including duplicates and unknown apps, export round trip.
- Host: open-request scheme checks, refusing executables, `chooseFile` and
  `saveFile` in the simulated system.
