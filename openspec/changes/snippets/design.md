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

## Keyword expansion (built 2026-11-05, protocol 19)

- **Plugins never see keystrokes.** `MacTextExpansion` owns a listen-only
  session `CGEventTap` (key-downs and mouse-downs), created only while some
  plugin has keywords and the user hasn't switched expansion off. It needs
  Accessibility, which pasting already needs.
- **Registration.** With `.textExpansion`, a plugin calls
  `Stackbar.setExpansions([TextExpansion(keyword:command:)])`, replacing its
  set (`[]` removes it; stopping the plugin removes it too). Keywords are 1
  to 32 characters without whitespace, quotes or backticks; at most 1,000 a
  plugin. A keyword two plugins register belongs to the first
  (`TextExpansionRegistry`), and the other's status lists it as `taken`.
- **Matching** (`TextExpansionMatcher`, pure and tested). The last 33
  typed characters. A keyword expands as its last character is typed (as in
  Raycast), only at the start of a word unless it starts with punctuation,
  and the longest wins. Delete forgets a character; clicks, arrows, Return,
  Tab, Esc, ⌘ or ⌃ chords and app switches start over. Stackbar's own
  windows and the skipped apps (1Password, Bitwarden, Passwords, Keychain
  Access by default; the user's list) never expand. Secure Input blocks the
  tap entirely.
- **On a match**, the host waits 30 ms for the last character to land,
  posts one backspace per grapheme (marked so the tap ignores them), and
  runs the command through `CommandCenter.runFromExpansion` as a hotkey
  would; a command that needs arguments opens in the palette.
- **Settings › Privacy & Secrets › Text Expansion** (shown when a plugin has
  the capability): the switch, the status (keywords, plugins,
  Accessibility, Secure Input) and the skipped apps. Both settings travel in
  `.stackbarsettings`.

## Tests

- Plugin: commands from snippets, nesting, the `{cursor}` offset in grapheme
  clusters, form validation, Raycast import samples, export round trip.
- Host: paste options in the simulated system (restore skipped when the
  change count moved), storage quota from the grant.
- Mac checklist: paste and cursor in TextEdit, Xcode, Slack, VS Code and
  Terminal; Clipboard History ignores snippet pastes.
