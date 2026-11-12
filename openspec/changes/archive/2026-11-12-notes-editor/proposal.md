# A live text editor, and plugin windows you can summon

## Why
Naveen (2026-11-10) chose to build a rival to Raycast Notes, one of the
features people name when they say why they stay on Raycast. Research is in
the thread "Build a Raycast Notes rival": a floating window on a hotkey,
one Markdown note at a time, checklists, pins, search, Recently Deleted.

Stackbar can't host that today. Plugins get a one-line `textField` and a
form's multiline box that saves only on submit; nothing edits a long text
live. Plugin windows open only from the panel's window button, so a hotkey
can't bring one up, and a plugin can't suggest that its window float.

## What changes
- **`ViewNode.editor(EditorNode)`** (protocol 28): a multiline editor the
  host owns. It sends the whole text as `.text` after a pause in typing and
  when it loses focus or closes. With `markdown` it styles Markdown as you
  type (headings, bold, italic, strikethrough, code, quotes, lists, task
  boxes, links) and adds the editing keys: ⌘B, ⌘I, ⇧⌘X, ⌘E, ⌘K, ⌘Return
  ticks a task, Return continues a list, Tab and ⇧Tab indent it, and a click
  on a task box ticks it. `document` names what is being edited: a new
  document replaces the text, the same one keeps the user's typing.
- In a window, an editor fills the window instead of sitting in a scroll
  view. In the panel it is `minHeight` tall (160 by default). Widgets draw
  its text; the menu bar hides it; the palette doesn't list it.
- **`Stackbar.showWindow()`, `hideWindow()`, `toggleWindow()`** (protocol
  28): a command (and so a hotkey) or a menu-bar click can bring up the
  plugin's window. `keepOnTop: true` suggests it floats; the title-bar pin
  is still the user's, and once they set it their choice wins.
- StackbarKit: `TextEditor(text:document:placeholder:markdown:minHeight:onChange:)`.

## Out of scope
Images in the editor, drag-to-reorder list items, a rendered (non-source)
Markdown view. The Notes plugin itself lives in stackbar-plugins.
