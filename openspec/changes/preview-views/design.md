# Design

## Eager, not lazy
Rows already reach the host with their previews in one `view` or `render`
message, so swapping the pane's content as the selection moves is a SwiftUI
subtree change with no round trip. A lazy mode (open a command view for the
selected row after a short dwell, cache it, time out to the text) needs
sessions per selection, placeholders and race handling; it can be added on
top later without changing this API. A selection event that re-renders the
whole list per arrow press was rejected: chatty, and arrowing would wait on
the plugin.

## Display-only
`PreviewNodeView` draws `NodeView` with `stackbarReadOnly` (as widgets do),
no widget buttons and no selected row, and a no-op `send`. Text fields,
editors and pickers then can't take the keyboard from the filter field, and
acting stays on the row's actions and ⌘K, as in Raycast's detail pane.

## Budget
Every row carries its preview in every render. `nodeCount` counts a row as
one node plus its accessories and preview view. The kit checks before
sending (one warning per plugin run), and `shownView` checks again on the
host, so a hand-written plugin can't send a huge pane to draw.

## Compatibility
`view` is optional, and Swift's synthesized decoding ignores keys it doesn't
know, so older hosts read the rest. The kit leaves `view` off when the host
said protocol < 29 in `hello`.
