# Design: confirm destructive actions in the host

## Wire

```swift
// ActionRef
public var confirm: String?          // protocol 25
// ViewNode
case button(title: String, symbol: String? = nil, role: Role = .primary,
            action: ActionID, confirm: String? = nil)
case tappable(ViewNode, action: ActionID, confirm: String? = nil)
```

`tappable` carries it too, because the kit's `ActionButton` and `IconButton`
resolve to tappables. All three are optional, so synthesized decoding uses `decodeIfPresent` and old
plugins decode unchanged. `confirm` is a lower-case verb phrase ("stop web
(pid 412)", "clear 12 items"); the host owns the rest of the sentence so the
wording is the same everywhere. Kit limits it to 120 characters.

`ViewNode.actions` already walks buttons and rows; a sibling
`confirmations: [ActionID: String]` walks the same tree so the host can ask
"does this action confirm, and with what text?" in one place.

## State machine

```
idle ──press──▶ armed(at, text) ──press within 10 s──▶ sent (idle)
                      │
                      ├── 10 s pass ─────────────────▶ expired (idle, redraw)
                      ├── new render drops the action ▶ idle
                      ├── new render changes the text ▶ idle (redraw)
                      └── surface hidden ────────────▶ idle
```

- **Key:** `(pluginID, surface, ActionID)`. Never render position. Row ids
  are `row/<key>/<title>`; when two rows share a key the kit adds `#2` in
  render order, so the kit logs a warning when a confirmable action's id
  needed a suffix.
- **One arm per plugin.** Arming B disarms A, on any of the plugin's
  surfaces. Pressing a different action of the same plugin disarms too, so a
  stray arm never lingers. Each palette command view keeps its own.
- **Text check.** On the second press the host compares the action's current
  `confirm` text with the armed one. If it changed ("Remove 3" → "Remove 4")
  the press counts as a new first press. This is what keeps the scope of
  Docker's Prune honest.
- **Window:** 10 s, a host constant. Not per-plugin.

## Where it lives

`ActionConfirmer` (StackbarHostCore, `@MainActor`, platform-free so it is
tested on Linux) with an injected clock:

```swift
enum Outcome { case send, armed(text: String), rearmed(text: String) }
func press(_ action: ActionID, plugin: String, surface: Surface, in root: ViewNode) -> Outcome
func rendered(plugin: String, surface: Surface, root: ViewNode)  // drops vanished/changed arms
func hidden(plugin: String, surface: Surface)
var armed: [Key: Arm] { get }                                      // renderers read this
var onChange: (() -> Void)?                                        // fired on arm, expiry, drop
```

Expiry runs off one host timer per armed entry; `onChange` lets the app
redraw from the root it already has. No message goes to the plugin, which is
the point: the plugin cannot redraw itself.

Hook points (each already finds the action before sending it):

| Path | Today | With this change |
|---|---|---|
| Panel, window, settings | `PluginController.send` (already resolves `navigate`) | ask the confirmer first |
| Command view in the palette | `CommandView.perform` | ask the confirmer, surface `.panel`-like key per session |
| Palette rows derived from panels | `Palette` → `PluginController.send` | same as panel; Return twice |
| Widget button | `WidgetActionInbox` → event | confirmable action opens the panel instead |
| `stackbarctl render --event` | `PluginSession` | runs through the confirmer, so the first press is held and reported; the same `--event` again sends it, and `--confirm` sends every event at once |
| Soak | `Soak.safeActions` | skips any action in `confirmations` |
| Agent tools, notification buttons | never ActionIDs | unchanged |

## What armed looks like

- **Row / button / tappable:** the host rewrites the tree it draws
  (`ActionConfirmer.decorate`), so every renderer shows the state without
  knowing about it. A button's title becomes "Press again to <confirm>" in
  the critical role; a row's subtitle and the armed action's title say the
  same; a tappable gets that label beside its content. Ids never change. The
  original returns on expiry. (No countdown ring in v1.)
- **HUD:** "Press again within 10 s to <confirm>", once per arm.
- **VoiceOver:** the control's label changes to the armed text and the host
  posts an announcement with it; expiry announces "Cancelled".
- **Keyboard:** Return / the shortcut is the second press; Esc disarms.
- **Widget:** not armed; opens the panel.

`SurfaceParity` gains the armed treatment for `button` and `row` per column;
the ledger in `docs/surface-parity.md` is regenerated.

## Old hosts

The kit reads the host's protocol from `hello`. Below 25 it wraps the
handler (an old host ignores the unknown `confirm` field) in its own arm with the same text
(HUD on first press, 10 s, keyed by action id). It cannot redraw on expiry;
that is the old behaviour, now in one place instead of fifteen.

## Store check

`scripts/check.sh` (stackbar-plugins) greps each plugin for `.critical`
actions and fails one with neither `confirm:` nor `confirm: .none`. The kit
spells the opt-out as a `Confirm` type with `.none` and string-literal
conformance so `confirm: "stop web"` reads naturally.
