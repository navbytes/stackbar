# Surface parity

Every node in the view vocabulary, and what each surface does with it. The
table is generated from `SurfaceParity` (Sources/StackbarHostCore/SurfaceParity.swift);
`SurfaceParityTests` fails when the two disagree and prints the table to paste.
Adding a node to `ViewNode` doesn't compile until `SurfaceParity`, the panel
renderer and the menu-bar renderer all handle it.

<!-- ledger:start -->
| Node | Panel | Window | Settings | Menu bar | Widget | Command view | Palette | Agent (text) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `text` | Text with style and role | Text with style and role | Text with style and role | Inline text | As panel | As panel | Not listed | Line (`# ` for titles) |
| `label` | Label with SF Symbol | Label with SF Symbol | Label with SF Symbol | Symbol and title | As panel | As panel | Not listed | `[symbol] title` |
| `stack` | VStack / HStack | VStack / HStack | VStack / HStack | Children on one line | As panel | As panel | Searched through | Lines, or one line when horizontal |
| `list` | List; filter field when searchable | List; filter field when searchable | List; filter field when searchable | Hidden (panel only) | First 4 rows, no filter | List filtered by the plugin as the user types | Searched through | `List` then indented rows |
| `section` | Captioned group | Captioned group | Captioned group | Hidden (panel only) | As panel | As panel | Searched through | `-- title --` |
| `row` | Row with app icon or symbol; click = first action, context menu = all | Row with app icon or symbol; click = first action, context menu = all | Row with app icon or symbol; click = first action, context menu = all | Hidden (panel only) | Row, not clickable | Row; Return = first action, ⌘K = all, navigate pushes | Entry per action, searchable by title and subtitle | `* title - subtitle <actions {ids}>` |
| `badge` | Capsule | Capsule | Capsule | Small capsule | As panel | As panel | Not listed | `[text]` |
| `button` | Button | Button | Button | Hidden (click opens the panel) | Drawn disabled | As panel | Entry, runs the button | `(title) {id}` |
| `toggle` | Toggle | Toggle | Toggle | Hidden (click opens the panel) | Drawn disabled | As panel | Entry, flips the toggle | `[x] title {id}` |
| `progress` | ProgressView | ProgressView | ProgressView | 12 pt ring | As panel | As panel | Not listed | `[####......] 40%` |
| `divider` | Divider | Divider | Divider | Hidden | As panel | As panel | Not listed | `----` |
| `labeled` | LabeledContent | LabeledContent | LabeledContent | Label and value | As panel | As panel | Not listed | `label: value` |
| `chart` | Swift Charts line, bar, area or donut, with labels, unit and goal; a day heatmap | Swift Charts line, bar, area or donut, with labels, unit and goal; a day heatmap | Swift Charts line, bar, area or donut, with labels, unit and goal; a day heatmap | 32 pt sparkline | As panel | As panel | Not listed | Block sparkline; donut as named values |
| `textField` | TextField; return submits | TextField; return submits | TextField; return submits | Hidden (click opens the panel) | Drawn disabled | As panel | Not listed | `[text____] {id}` |
| `picker` | Picker | Picker | Picker | Hidden (click opens the panel) | Drawn disabled | As panel | Not listed | `title: a | *b* {id}` |
| `slider` | Slider; sends on release | Slider; sends on release | Slider; sends on release | Hidden (click opens the panel) | Drawn disabled | As panel | Not listed | `title: v (min...max) {id}` |
| `link` | Link; host opens it | Link; host opens it | Link; host opens it | Hidden (click opens the panel) | Link (opens Stackbar's URL) | As panel | Entry, opens the URL | `<title> url` |
| `empty` | ContentUnavailableView | ContentUnavailableView | ContentUnavailableView | Symbol and title | As panel | As panel | Not listed | `[symbol] title - message` |
| `form` | Form; submit sends every field | Form; submit sends every field | Form; submit sends every field | Hidden (click opens the panel) | Drawn disabled | As panel | Not listed | `Form` then `label: [value____]` lines and `(submit) {id}` |
<!-- ledger:end -->
