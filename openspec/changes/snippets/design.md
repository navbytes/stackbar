# Design

## The plugin

```swift
struct Snippet: Codable, Identifiable {
    var id: UUID
    var name: String
    var text: String          // template, at most 65,536 characters
    var keyword: String?      // kept for expansion later
    var tags: [String]
}
```

- **Manifest:**
  - surfaces `[.panel, .settings]` (headless);
  - capabilities `[.clipboard, .context, .storage(megabytes: 16)]`;
  - a default hotkey of `ctrl+option+s` for "Search Snippets", which the user
    can change.
- **One command per snippet** (`sn-<uuid>`). Its arguments come from the
  template. Running it renders the text and returns `.paste(text)`, carrying
  the cursor offset when the snippet has a `{cursor}`.
- **"Search Snippets"** (view):
  - The preview shows the rendered text with today's values.
  - Return pastes and ⌘C copies.
  - ⌘K: Paste, Copy, Edit, Duplicate, Delete.
  - Tags are filtered with ⌘P, the same as Quicklinks.
- **"Create Snippet":** a form with Name, Text (multi-line editor, showing the
  placeholder list underneath), Keyword and Tags. It checks that the template
  parses, that `{cursor}` appears at most once, and that the keyword has no
  whitespace, quotes or backticks (Raycast's rule).
- **`{snippet name="…"}`** is resolved by the plugin, one level deep. A
  snippet that names itself or nests deeper fails with a message.

## Paste, done properly

`HostCall.paste` gains `PasteOptions`: `restoreClipboard` (default true for
command results) and `cursorFromEnd: Int`. On the Mac, the host:

1. Saves the pasteboard's current items.
2. Writes the text and marks it `org.nspasteboard.TransientType`.
   Clipboard History already ignores that type (fluid-plugins design), so
   snippets don't fill the history.
3. Activates the app the user was in and sends ⌘V (existing code).
4. If `cursorFromEnd > 0`, sends that many ← key events. The count is in
   grapheme clusters, because one ← press moves over one composed character.
5. After 500 ms, if the pasteboard's `changeCount` is still the one it wrote,
   restores the saved items. If the user copied something meanwhile, it leaves
   their copy alone.

Accessibility is already required for pasting, so nothing new is asked.

## Storage grant

`Capability.storage(megabytes: Int)`, from 1 to 64. `StorageStore` reads the
quota from the granted manifest instead of the fixed 1 MB. The install sheet
says "Stores up to 16 MB". Plugins without it keep 1 MB.

## Import and export

- **Raycast JSON:** an array of `{name, text, keyword?}`. Duplicates (same
  name and text) are skipped. Raycast's `{date: YYYY-MM-DD}` shorthand is
  accepted as `{date format="YYYY-MM-DD"}`.
- **Export** writes the same format.
- The files come from `chooseFile` and `saveFile`, the same as Quicklinks.

## Keyword expansion (designed, not in 1.0)

- **Plugins never see keystrokes.** A host service, `ExpansionMonitor`, uses a
  listen-only `CGEventTap`, which needs Input Monitoring. It is off until the
  user turns it on in Settings.
- **Registration.** With a new `.textExpansion` capability, plugins register
  keywords with `Stackbar.setExpansions([keyword: commandID])`.
- **Matching.** The monitor keeps the last 32 typed characters. Clicks, app
  switches, arrow keys and modifier chords clear them. Secure input (password
  fields) stops the tap entirely. 1Password and Keychain Access are excluded
  by default, with a user list.
- **On a match**, after a delimiter or immediately (a setting), the host
  sends backspaces for the keyword and runs the command, which pastes.
- **Ships only after Naveen decides** (tasks 4.x).

## Tests

- Plugin: commands from snippets, nesting, the `{cursor}` offset in grapheme
  clusters, form validation, Raycast import samples, export round trip.
- Host: paste options in the simulated system (restore skipped when the
  change count moved), storage quota from the grant.
- Mac checklist: paste and cursor in TextEdit, Xcode, Slack, VS Code and
  Terminal; Clipboard History ignores snippet pastes.
