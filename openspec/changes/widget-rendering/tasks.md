# Tasks

## 1. Host (no protocol change)
- [x] 1.1 `WidgetLayers`, `WidgetSize`, `changesWithTime` in StackbarProtocol, with tests
- [x] 1.2 Widget images: fetch for widget trees, downsample, write beside snapshots, prune; `WidgetSnapshot.images`
- [x] 1.3 Widget draws in snapshot mode; widget toggle as a switch look-alike; `SnapshotForm`
- [x] 1.4 Full-bleed container background, own content margins
- [x] 1.5 Minute timeline entries for clocks and timed progress (`stackbarNow`)
- [x] 1.6 Rows by size; `render --surface widget --png` draws all three sizes
- [x] 1.7 Ledger, authoring guide, llms.txt
- [ ] 1.8 Mac check: Music widget shows the cover full-bleed; World Clock and Pomodoro widgets keep time for an hour with Stackbar idle; System Monitor small/medium/large; a widget toggle and button still act

## 1b. Fixes from the first Mac check (2026-11-22)
- [x] 1.9 No `textSelection` in widgets: WidgetKit drew every plain text and labeled value as a yellow no-entry box
- [x] 1.10 Vibrant mode (desktop behind windows): style backgrounds draw as light veils instead of opaque fills that wash out to grey slabs

## 2. Store
- [x] 2.1 World Clock: widget times from `Clock`, so they don't go stale

## 3. Per-size layouts (protocol 31; Naveen approved 2026-11-20)
- [x] 3.1 Decide
- [x] 3.2 Protocol: `hello.widgetSizes`, `HostMessage.widgetSizes`, `PluginMessage.renderWidget`
- [x] 3.3 Kit: `widget(_ size: WidgetSize)`, defaulting to `widget`; rendered after the surfaces, only for sizes asked
- [x] 3.4 Host: supervisor asks plugins on 31+, keeps `widgetViews`; sessions ask for every size
- [x] 3.5 App: WidgetKit's placed sizes (at launch, after writes, and when the extension is drawn at a new size); snapshot `sizes`
- [x] 3.6 Extension: draws the size's tree; `render --png` and text show each size
- [x] 3.7 Guide and llms.txt
- [ ] 3.8 After release: give System Monitor, Music, Pomodoro, PR Cockpit and World Clock small and large layouts
