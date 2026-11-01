# Snippets

## Why

macOS Text Replacements only swap one fixed string for another. Developers
keep snippets with placeholders: today's date, the clipboard, a cursor
position, a filled-in argument. Raycast users have libraries of them and want
to bring them along.

## What changes

- **A bundled Snippets plugin** on the `Template` engine from `quicklinks`:
  - Every snippet is a command that pastes its rendered text into the app the
    user was in.
  - "Search Snippets" lists them with a live preview of the rendered text.
  - "Create Snippet" is a form with a multi-line editor.
  - Import and export of Raycast JSON.
- **Paste with a cursor.** `{cursor}` puts the caret where the snippet says,
  after pasting.
- **Paste restores the clipboard.** The host puts back what the user had on
  the clipboard, and marks its own write as transient so Clipboard History
  ignores it.
- **A storage grant.** `.storage(megabytes:)` lets a plugin ask, on the
  install sheet, for more than the default 1 MB. Snippets asks for 16 MB,
  enough for thousands of snippets at Raycast's 65,536-character limit.

## Needs a decision later: typing a keyword to expand

Expanding `;sig` as you type needs a system-wide keystroke monitor and the
Input Monitoring permission. That is a real trust cost for a developer tool,
and Text Replacements already covers plain keywords. Naveen decided on 2026-11-01 not to add one yet, because a system-wide keyboard
monitor would worry many people. Keyword expansion stays designed here
(design.md, "Keyword expansion") but is not built. Keywords imported from
Raycast are kept, so they work the day it ships.

## Depends on

`plugin-commands` and `quicklinks` (for `Template`).
