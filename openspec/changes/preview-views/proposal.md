# Views in row previews

## Why
Naveen (2026-11-10) chose to let a row's preview pane draw a real view, not
only text. It came up while specing Release Radar (a release chain as you
arrow through results); PR Cockpit's checks, Git Sync, Color Picker, Jira,
Linear and Docker could use it too. The analysis is in the thread "Decide on
rich views in palette previews" (doc: Rich views in palette previews). He
picked the simple version: the view travels with the row, display-only; a
lazy fetch on selection is deferred.

## What changes
- **`RowPreview.view: ViewNode?`** (protocol 29). The palette's split pane
  and the panel's pane under a searchable list draw it in place of the text,
  display-only: read-only like a widget, so nothing takes focus from the
  search field and controls show disabled.
- **Budget:** `RowPreview.maxViewNodes` (150). The kit drops a bigger view
  with one warning; the host draws the text for one that slips through.
- `text` stays what search matches and what hosts before protocol 29 show.
- `stackbarctl render` prints a preview's view under its row.
- StackbarKit: `Row.preview(text:caption:view:)`, `PreviewDetail`,
  `Metadata`.

## Out of scope
Fetching a preview when a row is selected (`preview(command:)`), and
interactive controls in the pane. PR Cockpit, Color Picker and Release Radar
adopt it in their own repos after the release.
