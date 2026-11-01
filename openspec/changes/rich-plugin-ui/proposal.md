# Rich plugin UI

## Why
Naveen moved on from Vee so plugin authors can build truly unique UI, not
script output in a menu. Stackbar's view vocabulary was deliberately
"meaning, never pixels": six roles, five text styles, V/H stacks and stock
controls. A Pomodoro mockup he shared (warm colors, a big countdown, a
progress ring around a round play button, a Focus/Break segmented toggle,
stat tiles, icon buttons) could not be built at all.

The analysis and the decisions are in the plan doc
(https://claude.ai/artifact/G6Howv1JeRznwjhKeRJvm6). Naveen decided on
2026-11-01:

- Retire "meaning, never pixels" in favour of guardrails.
- Free hex colors anywhere (each with an optional dark-mode variant), with
  contrast checked by tooling, not limited to a theme palette.
- Build Tier 1 (a richer declarative vocabulary) and run a spike for Tier 2
  (native SwiftUI views hosted out of process with ExtensionKit) in parallel.
- No web views for now.

## What changes
Tier 1, phase 1 (protocol 11):

- **Styling:** a `styled` node carries one `Style`: font (size, weight,
  design, monospaced digits), foreground and background paints (role, hex
  with a dark variant, or a linear gradient), padding, frame, border, clip
  shape, shadow, opacity, an accessibility label and an animation.
- **Layout:** layered stacks (`StackAxis.depth`, a ZStack), stack alignment,
  `spacer`.
- **Shapes and images:** `shape` (rectangle, rounded rectangle, capsule,
  circle; fill and stroke) and `image` (an SF Symbol sized and colored by
  its style).
- **Interaction:** `tappable` turns any subtree into a button; pickers can be
  segmented.
- **Time:** a `timer` node and timed progress (`TimeRange`) that the host
  animates, so a countdown and its ring move every frame without the plugin
  re-rendering. Progress can be drawn as a ring.
- **Sound:** `Stackbar.play(.glass)` plays a macOS system sound.
- **Guardrails:** `stackbarctl render` warns about text whose foreground and
  background fail WCAG AA (4.5:1) in light or dark mode, and about shapes and
  images without an accessibility label. Renders over a node cap are refused.

The Pomodoro plugin in stackbar-plugins is the acceptance test.

Tier 2: a spike (see design.md) decides whether native views ship on
ExtensionKit or on a plugin-owned panel.

## Not in this change
Bundled image assets and fonts, transitions, hover styles and grids
(phase 2); native views themselves (after the spike); web views.
