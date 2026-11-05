# Contributing to Stackbar

Thanks for helping. Stackbar is the app and its Swift libraries; plugins for
the store live in [navbytes/stackbar-plugins](https://github.com/navbytes/stackbar-plugins),
which has its own CONTRIBUTING with the bar a plugin must clear.

## Reporting a problem

Open an issue with the bug template and paste the output of
`stackbarctl doctor`. It lists the toolchain, StackbarKit and data folders and
nothing personal. `stackbarctl logs -n 200` is the host log, if the problem
is a plugin that won't start.

Security problems go privately, as [SECURITY.md](SECURITY.md) says.

## Changing the app

1. Planned work lives in `openspec/changes/<name>/`: a proposal, a design and
   tasks. For anything larger than a fix, open an issue first so the plan can
   be agreed, then keep `tasks.md` ticked as you go.
2. Build and test before you open a pull request:

   ```sh
   swift build && swift test
   ```

   Everything but the `Stackbar` app target builds and tests on Linux too. The
   macOS CI job covers the app and the Xcode build.
3. A new host call or view bumps the protocol version
   (`StackbarProtocolVersion.current`), says which capability it needs in
   `HostCall+Description.swift`, and is documented in
   `Sources/StackbarHostCore/AuthoringGuide.swift` and `llms.txt` (the two
   must match; `scripts/generate-docs.sh` copies one to the other).
4. Keep to the house style: plain words in UI text and docs, no new
   dependencies without discussing them first, and tests next to the code they
   cover.

## Writing a plugin

A plugin is one `.swift` file that imports StackbarKit. Start with
`stackbarctl new MyPlugin.swift`, then `stackbarctl build`, `render` and
`render --event <id>` to check it without the app. `stackbarctl docs` is the
full reference.

## Licence

By contributing you agree that your work is released under the MIT licence
in [LICENSE](LICENSE).
