# Surface parity

Every node in the view vocabulary, and what each surface does with it. The
table is generated from `SurfaceParity` (Sources/StackbarHostCore/SurfaceParity.swift);
`SurfaceParityTests` fails when the two disagree and prints the table to paste.
Adding a node to `ViewNode` doesn't compile until `SurfaceParity`, the panel
renderer and the menu-bar renderer all handle it.

<!-- ledger:start -->
| Node | Panel | Window | Settings | Menu bar | Widget | Palette | Agent (text) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `text` | Text with style and role | Text with style and role | Text with style and role | Inline text | As panel | Not listed | Line (`# ` for titles) |
| `label` | Label with SF Symbol | Label with SF Symbol | Label with SF Symbol | Symbol and title | As panel | Not listed | `[symbol] title` |
| `stack` | VStack / HStack | VStack / HStack | VStack / HStack | Children on one line | As panel | Searched through | Lines, or one line when horizontal |
| `list` | List; filter field when searchable | List; filter field when searchable | List; filter field when searchable | Hidden (panel only) | First 4 rows, no filter | Searched through | `List` then indented rows |
| `section` | Captioned group | Captioned group | Captioned group | Hidden (panel only) | As panel | Searched through | `-- title --` |
| `row` | Row; click = first action, context menu = all | Row; click = first action, context menu = all | Row; click = first action, context menu = all | Hidden (panel only) | Row, not clickable | Entry per action, searchable by title and subtitle | `* title - subtitle <actions {ids}>` |
| `badge` | Capsule | Capsule | Capsule | Small capsule | As panel | Not listed | `[text]` |
| `button` | Button | Button | Button | Hidden (click opens the panel) | Drawn disabled | Entry, runs the button | `(title) {id}` |
| `toggle` | Toggle | Toggle | Toggle | Hidden (click opens the panel) | Drawn disabled | Entry, flips the toggle | `[x] title {id}` |
| `progress` | ProgressView | ProgressView | ProgressView | 12 pt ring | As panel | Not listed | `[####......] 40%` |
| `divider` | Divider | Divider | Divider | Hidden | As panel | Not listed | `----` |
| `labeled` | LabeledContent | LabeledContent | LabeledContent | Label and value | As panel | Not listed | `label: value` |
| `chart` | Swift Charts line, bar, area or donut, with labels, unit and goal | Swift Charts line, bar, area or donut, with labels, unit and goal | Swift Charts line, bar, area or donut, with labels, unit and goal | 32 pt sparkline | As panel | Not listed | Block sparkline; donut as named values |
| `textField` | TextField; return submits | TextField; return submits | TextField; return submits | Hidden (click opens the panel) | Drawn disabled | Not listed | `[text____] {id}` |
| `picker` | Picker | Picker | Picker | Hidden (click opens the panel) | Drawn disabled | Not listed | `title: a | *b* {id}` |
| `slider` | Slider; sends on release | Slider; sends on release | Slider; sends on release | Hidden (click opens the panel) | Drawn disabled | Not listed | `title: v (min...max) {id}` |
| `link` | Link; host opens it | Link; host opens it | Link; host opens it | Hidden (click opens the panel) | Link (opens Stackbar's URL) | Entry, opens the URL | `<title> url` |
| `empty` | ContentUnavailableView | ContentUnavailableView | ContentUnavailableView | Symbol and title | As panel | Not listed | `[symbol] title - message` |
<!-- ledger:end -->
