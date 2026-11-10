# Design

## The editor node
```swift
public struct EditorNode: Codable, Equatable, Sendable {
    public var text: String
    public var document: String      // identity of what is edited
    public var placeholder: String?
    public var markdown: Bool?       // style Markdown and add its keys
    public var minHeight: Double?    // panel height; windows fill
    public var focus: Bool?          // take focus when shown
    public var action: ActionID      // receives .text(whole text)
}
case editor(EditorNode)
```

**Who owns the text.** The host does while the user types. It sends the
whole text 0.6 s after the last keystroke, and at once when the editor loses
focus or leaves the screen, so closing a window never drops a word. When a
render arrives:
- a different `document` replaces the text and the undo history;
- the same document with text equal to what the host last sent changes
  nothing (the plugin is echoing);
- the same document with other text replaces it only when nothing is waiting
  to be sent (a file changed outside, or the plugin rewrote it). Otherwise
  the user's typing wins and is sent next.

**Markdown styling** is a pure function in StackbarProtocol,
`MarkdownStyler.spans(in:)`, returning ranges (UTF-16 offsets) and a style
kind per range, so it is tested on Linux. The Mac view applies them to the
NSTextStorage after each edit. Markers stay visible but are drawn in the
tertiary color; headings are larger, checked tasks dimmed and struck.

**Editing keys** are pure functions too, `MarkdownEditing`: what Return does
on a list line (continue it, or end the list on an empty item), toggling a
task on a line, indenting a list line, and wrapping a selection in markers.
Each returns the replaced range and the new text, applied through the text
view so undo works.

**Windows.** `PluginWindowView` drops its scroll view when the window's
tree holds an editor, and the editor takes the space left. Snapshots
(`render --png`) draw the text as plain styled `Text`, because ImageRenderer
can't draw an NSTextView.

## Window calls
`HostCall.pluginWindow(WindowRequest)` with `action` show, hide or toggle
and `keepOnTop: Bool?`. Needs `.window` in the manifest's surfaces. Toggle
hides the window when it is the key window of the active app, and shows it
otherwise. The app keeps the pin in `stackbar.pinned.<id>`; when that key is
unset, `keepOnTop` decides. On Linux and in `stackbarctl` the call prints
what it would do.
