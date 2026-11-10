# Tasks

## 1. Host
- [x] 1.1 `EditorNode`, `ViewNode.editor`, protocol 28; queries, affordances, tree text
- [x] 1.2 `MarkdownStyler` and `MarkdownEditing` with tests
- [x] 1.3 Mac editor view (NSTextView), sync rules, snapshot fallback; widget read-only; pending typing sent before any other press
- [x] 1.4 Windows fill with an editor
- [x] 1.5 `HostCall.pluginWindow`, StackbarKit `showWindow/hideWindow/toggleWindow`, app + stackbarctl
- [x] 1.6 StackbarKit `TextEditor`; surface parity, authoring guide + llms.txt, CHANGELOG

## 2. Plugins (stackbar-plugins, after the host release)
- [ ] 2.1 Notes 1.0.0 (notes in host storage, pins, search, Recently Deleted, export as Markdown)

## 3. Mac check
- [ ] 3.1 Hotkey toggles the Notes window above other apps; typing never jumps
- [ ] 3.2 Markdown styling, ⌘B/⌘I, Return continues lists, ⌘Return and clicks tick tasks
- [ ] 3.3 Closing the window mid-sentence keeps the text
- [ ] 3.4 Notes survive a restart and an app update
