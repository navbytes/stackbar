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

## 2. Store
- [ ] 2.1 World Clock: widget times from `Clock`, so they don't go stale

## 3. Per-size layouts (protocol 31, if Naveen approves)
- [ ] 3.1 Decide
