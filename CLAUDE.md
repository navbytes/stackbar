# Stackbar — notes for AI sessions

Stackbar is a native macOS menu-bar host for live plugins written in Swift. It is
a separate app from Vee (navbytes/vee) and shares no code with it yet.
`README.md` explains the architecture.

**Planned work lives in `openspec/`.** A change with a directory under
`openspec/changes/` has its proposal, design and tasks there. Those are the
authority, so keep `tasks.md` ticked as you go.

**Writing a plugin?** It is one `.swift` file that imports StackbarKit. Use
`stackbarctl build`, then `render`, then `render --event <id>` to check it
without the app.

Run this check before you call a change done:

```sh
swift build && swift test
```

The `Stackbar` app target only compiles on macOS. On Linux everything else builds
and is tested, and the macOS CI job covers the app.
