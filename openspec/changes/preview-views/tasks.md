# Tasks

## 1. Host and kit
- [x] 1.1 `RowPreview.view`, `maxViewNodes`, `shownView`, `ViewNode.nodeCount`; protocol 29
- [x] 1.2 Palette `PalettePreview` and panel `PreviewPane` draw the view display-only (`PreviewNodeView`)
- [x] 1.3 StackbarKit `Row.preview(text:caption:view:)` with the budget and old-host fallback; `PreviewDetail`, `Metadata`
- [x] 1.4 `stackbarctl render` text shows a preview's view
- [x] 1.5 Tests, authoring guide + llms.txt, CHANGELOG

## 2. Plugins (stackbar-plugins, after the host release)
- [ ] 2.1 PR Cockpit: checks preview as a coloured list
- [ ] 2.2 Color Picker: a swatch
- [ ] 2.3 Release Radar (private): the release chain

## 3. Mac check
- [ ] 3.1 Arrowing through PR Cockpit checks redraws the pane with no lag
- [ ] 3.2 Nothing in the pane takes focus; Return and ⌘K still act on the row
- [ ] 3.3 Light and dark look right; long views scroll
