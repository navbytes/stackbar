# Running commands, and the context the user was in

## Why

Many Raycast extensions that developers use wrap a command-line tool:
Homebrew, Docker, git, kubectl, port killers. Many others start from what the
user had in front of them: the selected text, the frontmost app, the files
selected in Finder. Stackbar plugins can do neither today. They run sandboxed
and can't spawn processes. The `.run(commands:)` capability is declared in
`Manifest.swift` and shown on the install sheet, but no host call stands
behind it.

User scripts don't need this, because macOS Shortcuts runs shell scripts and
Spotlight runs Shortcuts. Plugins do need it.

## What changes

- **`Stackbar.run`** runs a command the manifest declared and the user
  approved, outside the plugin's sandbox, with argv only and no shell
  interpretation. It returns status, stdout and stderr. **`Stackbar.stream`**
  streams output for long-running commands and can be cancelled.
- **Approval names real paths.** At approval, each declared command name is
  resolved to an absolute path, and the approval records that path. A command
  that resolves somewhere else later needs approval again. Interpreters and
  shells get a "can run anything" warning on the sheet.
- **A new `.context` capability:**
  - `Stackbar.context()` returns the frontmost app, its focused window title
    and the selected text.
  - `Stackbar.finderSelection()` returns the paths selected in Finder.
- **Invocation context.** When a command, hotkey or Spotlight intent starts,
  the host captures the context *before* Stackbar's own UI takes focus. It
  passes the context with the invocation, only to plugins granted `.context`.
- **Simulated** in `stackbarctl` and tests: `--selected-text`,
  `--frontmost-app` and `STACKBAR_CONTEXT=<json>`. `stackbarctl` runs real
  commands, because the user is the one running it.

## Not in this change

- The active browser tab's URL or content. That needs Apple Events per
  browser, and comes later if a plugin needs it.
- Copying with ⌘C as a fallback for apps that don't expose selected text
  through Accessibility. Pressing ⌘C behind the user's back changes their
  clipboard and races with their typing. When an app doesn't expose it,
  `selectedText` is `nil` and the plugin says so.
