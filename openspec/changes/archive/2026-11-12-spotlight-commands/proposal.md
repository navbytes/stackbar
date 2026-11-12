# Commands in Spotlight, Shortcuts and Quick Keys

## Why

Naveen's rule is to use macOS where it is good. Spotlight on macOS 26 is the
launcher people already have. It runs App Intents from any app, fills in their
parameters, gives them Quick Keys, and shows indexed app entities in its
results. Shortcuts can run the same intents, schedule them and bind them to
keys. If Stackbar's commands show up there, a Raycast user gets "type a few
letters and run my plugin" without a second launcher.

## What changes

- **App Intents in the app target.** `RunCommandIntent`, `OpenCommandIntent`
  and `OpenPluginIntent`, built over two entities, `CommandEntity` and
  `PluginEntity`, whose queries read the `CommandRegistry` from
  `plugin-commands`.
- **Core Spotlight index.** Commands are indexed with `IndexedEntity` and
  `CSSearchableIndex.indexAppEntities`. They then appear in ordinary ⌘Space
  results, and opening one runs `OpenCommandIntent`.
- **App Shortcuts** with phrases such as "Run Search Pull Requests in
  Stackbar". These are refreshed whenever commands change.
- **Donations.** Running a command from anywhere donates the intent, so
  Spotlight learns what the user runs.
- **Settings.** A "Show in Spotlight" switch per command (in the Commands page
  from `plugin-commands`) and an overall switch.
- **Builds.** App Intents metadata is produced only by an Xcode build. So
  `scripts/bundle.sh` moves to `xcodebuild`, which release task 3.3 already
  wants.

## Risk, settled first

App Intents are compiled in, but plugin commands are not. The design
therefore uses a few fixed intents whose parameter is a dynamic entity. A
one-day spike on macOS 26 (task 1) must confirm three things: that Spotlight's
Actions view lets you search those entities as you type, that a Quick Key can
be saved for an intent with a chosen entity, and that indexed entities show in
⌘Space results. If one of them fails, design.md records what we saw and the
plan adjusts before any other task starts.

## Not in this change

- Interactive snippets (an intent showing a live view inside Spotlight).
  Command views open in Stackbar's palette instead. Snippets can follow later
  if the spike shows they suit list views.
- Siri phrasing beyond the App Shortcuts phrases.
