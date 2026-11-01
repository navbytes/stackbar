# Design

## One modifier node, not twenty
SwiftUI's styling is a long list of modifiers. Mirroring each as its own
`ViewNode` case would add a dozen cases, a dozen rows in every renderer
switch and a dozen parity rows that all say the same thing. Instead a single
case, `styled(ViewNode, style: Style)`, carries every modifier as an optional
field. Every renderer handles it once.

`Style` applies its fields in a fixed order, which is the order a SwiftUI
author usually writes them:

    font, foreground → padding → frame → background → border → clip → shadow → opacity

`font`, `foreground`, `accessibilityLabel` and `animation` behave like
SwiftUI environment values: the innermost one wins. The kit's modifiers
(`.padding()`, `.background()`…) fold into the child's `Style` when that keeps
the same meaning, and wrap in a new `styled` node when it doesn't (a
`.padding()` after a `.background()`), so `.padding().background().padding()`
draws exactly as in SwiftUI. The rule lives in `Style.folding(_:)`, in
StackbarProtocol, so the kit and the tests share it.

A styled font and foreground override the child's semantic `TextStyle` and
`Role`: the host passes them down in the environment, and `text`, `label`,
`image`, `progress` and `shape` use them in place of their role color and
text style.

## Paint
`Paint` is a role (follows the system, as before), a hex color with an
optional dark variant, or a linear gradient of hex colors at an angle. Free
hex values were Naveen's choice over a declared theme palette. Hex strings
are parsed once in `HexColor` (StackbarProtocol), which also computes WCAG
relative luminance and contrast, so `stackbarctl render` can lint without
SwiftUI.

## Time on the host
A countdown re-rendered by the plugin every second costs a JSON round trip
per tick and still cannot animate a ring smoothly. `TimeRange(start, end)` is
sent once. `timer` draws `Text(timerInterval:)`, and progress with `timing`
computes its fraction from the clock in a `TimelineView`. WidgetKit supports
both natively, so the widget counts too. The agent text renders the value at
the moment it is asked.

## Surfaces
| Node | Panel, window, settings | Menu bar | Widget | Palette | Agent |
| --- | --- | --- | --- | --- | --- |
| `styled` | Child with the style applied | Child; color and decoration ignored, so the bar stays legible | As panel | Searched through | Child, or the accessibility label |
| `shape` | Filled or stroked shape | Hidden | As panel | Not listed | Nothing (label via `styled`) |
| `image` | SF Symbol | Symbol | As panel | Not listed | `[symbol]` |
| `timer` | Live timer text | Live timer text | As panel | Not listed | `12:34` as of now |
| `spacer` | Spacer | Hidden | As panel | Not listed | Nothing |
| `tappable` | Content as a plain button | Hidden (click opens the panel) | Drawn, not clickable | Entry named by its text | `(text) {id}` |

`SurfaceParity` is the authority; the table above is the intent.

## Guardrails
- Node cap: the host refuses a render over 5,000 nodes or 64 levels deep and
  shows the plugin's error state, so a runaway tree can't stall the UI.
- Lint (stackbarctl render): foreground/background pairs under 4.5:1 in
  either mode; `shape` and `image` outside any `styled` with an accessibility
  label.
- Sounds are the system's own names only (`SystemSound`), at most 10 a
  minute, like notifications. No arbitrary audio files.

## Tier 2 spike: native views with ExtensionKit
Questions the spike answers on a Mac (macOS 26), each with a yes/no:

1. Can `stackbarctl build` produce an `.appex` (with an `AppExtension` main)
   inside a generated container `.app`, ad-hoc signed like plugins are today?
2. Does LaunchServices register it from Stackbar's data folder
   (`lsregister`), and does `AppExtensionIdentity.matching(appExtensionPointIDs:)`
   find it?
3. Does `EXHostViewController` show its scene inside Stackbar's popover, and
   does the user-enablement step allow pre-approval or fold into Stackbar's
   own approval sheet?
4. Does it keep the App Sandbox entitlements Stackbar generates today?
5. Time to first frame under 150 ms, memory under 30 MB per extension.

Go: native views ship on ExtensionKit. No-go: on a plugin-owned borderless
panel positioned under the status item. The findings go in `spike.md`.
