# Design

## chooseFolder and granted folders

`HostCall.chooseFolder(prompt:)` opens an `NSOpenPanel` with
`canChooseDirectories` only and returns `ChosenFolder?` (path, name), nil
on cancel. Rate limit and "no time limit" match `chooseFile`.

The host stores grants in the plugin's ledger next to approved command
paths (`grantedFolders: [String]`, canonical paths). `CommandRunGate`
builds its allowed list from the plugin's `.files` paths plus these. The
plugin's Settings page shows a "Folders you chose" section with Remove;
removing one stops runs there at once and fires the plugin's `refresh()`
with reason `.settings`.

Refused picks: `/`, `/System`, `/Library`, `/Users` itself, `~` itself and
`~/Library`. Picking `~` is too broad for a pick to stand in for consent;
the panel says to pick a folder inside it.

`Stackbar.grantedFolders()` returns the current list so a plugin can drop
folders the user removed. The plugin's sandbox is unchanged: it never reads
these folders itself, only commands run there.

`stackbarctl` simulates the panel with `STACKBAR_CHOOSE_FOLDER=<path>[:<path>…]`
(like the other `STACKBAR_*` simulations) and keeps grants in its scratch
folder.

## SSH agent

`Capability.sshAgent`. `CommandRunGate.prepare` adds `SSH_AUTH_SOCK` from
the host's own environment when the plugin holds the capability and the
variable is set. `SSH_AUTH_SOCK` becomes a reserved variable, so a plugin
can't point it elsewhere. 1Password users who set `IdentityAgent` in
`~/.ssh/config` already work, because `HOME` is passed; the capability
covers the default agent. HTTPS remotes already work through the
`osxkeychain` credential helper in `~/.gitconfig`.

Protocol 24 (current is 23): one call, one reply type, one capability. Older
helpers never send the call; a manifest with `.sshAgent` needs
`minimumStackbar` of the release that ships it.

## Plugin

### Capabilities

`.run(commands: ["git", "find"])`, `.sshAgent` and `.openURLs(["*"])` to open folders in editors and the
compare view. `find` scans picked folders: run with `workingDirectory` set
to the folder, `find . -maxdepth N -name .git -prune` (or `-type d`, plus
`.git` files for worktrees).

Every `git` run sets `GIT_TERMINAL_PROMPT=0`, `GIT_SSH_COMMAND=ssh -o
BatchMode=yes -o ConnectTimeout=15` and `GIT_OPTIONAL_LOCKS=0` (status must
not take the index lock while the user works), and passes
`-c color.ui=false`.

### Status

Local check per repository, one command:

```
git status --porcelain=v2 --branch --untracked-files=no
```

gives branch, upstream, `+ahead -behind`, changed entries and unmerged
(`u`) entries. A merge or rebase in progress shows as unmerged entries or a
detached head; the row says "Merge in progress" or "Rebase in progress".

Last fetched: the plugin records when *it* fetched each repository, in
storage. A fetch the user ran in a terminal is not seen, so the row says
"not fetched by Git Sync yet" rather than guessing from `FETCH_HEAD`.

States, in panel order: Conflicts, Diverged, Behind, Ahead, Dirty, No
upstream, Up to date (collapsed). A repository can be both Behind and
Dirty; it shows under Behind with the dirty dot.

All-branches mode (window, or the setting) uses
`git for-each-ref --format='%(refname:short)%09%(upstream:short)%09%(upstream:track)' refs/heads`,
which also reports `[gone]` for prune.

### Fetch and pull

- Fetch: `git fetch --prune --no-tags --quiet` (tags off by default: some
  repos have thousands). At most 3 at once (the host allows 4; one is left
  for clicks), 120 s timeout, staggered so a 60-repo setup doesn't burst.
- Pull, fast-forward: `git merge --ff-only @{u}` after a fetch, not `git
  pull`, so the user's `pull.rebase` config can't change what happens.
- Pull, rebase (setting): `git rebase @{u}` only when the repository is
  clean; on a conflict, `git rebase --abort` and mark it Diverged.
- Dirty, "stash, pull, restore": `git stash push --include-untracked -m
  "Git Sync <date>"`, the pull, `git stash pop`. If pop conflicts, leave
  the stash, mark the repo Conflicts and say "your changes are in the
  stash".
- Push: `git push` with no flags; refused with no upstream (offer "Push and
  set upstream" as an explicit second action).
- Update All Safe: Behind + clean (or per the dirty setting) + not
  diverged, one at a time per repository, three repositories at once.
  Summary HUD: "Updated 7, skipped 2 (uncommitted changes)".

Before any pull the row can show incoming commits:
`git log --oneline --no-decorate -20 HEAD..@{u}`.

### Discovery

Sources, any mix:

1. Picked folders, scanned to a depth (1-4, default 2). First run suggests
   the common folders that exist (`~/Developer`, `~/code`, `~/src`,
   `~/Projects`, `~/repos`, `~/GitHub`, `~/workspace`); suggestions are
   buttons that call `chooseFolder` with that folder preselected, so the
   user still picks.
2. Recent editor projects: the folders VS Code, Cursor, Windsurf and
   VSCodium list as recent, kept when they are git repositories. This
   needs `sqlite3` and `.files` on the editors' storage, and capabilities
   are fixed in the manifest, so turning it on would mean everyone
   approves those. It ships in 1.1, and only if picked folders turn out not
   to cover most people.
3. Add one repository: `chooseFolder` on the repo itself.

Hidden repositories are kept by path in storage. Rescan on launch, on wake,
every hour, and from a button.


### Worktrees

A repository with linked worktrees is one entry, not one per folder. The
scan finds `.git` *files* (a linked worktree) as well as folders, and
groups each under its main repository by `git rev-parse --git-common-dir`.

Data, from the main repository:

```
git worktree list --porcelain
```

gives each worktree's path, HEAD, branch, and `locked` / `prunable`
(folder gone) / `detached`. Ahead/behind for every worktree's branch comes
from the same `for-each-ref` call as all-branches mode, because worktrees
share refs: no extra command per worktree. Uncommitted changes need
`git status` run *in* the worktree, so that runs only when the worktree is
inside a granted folder. Outside one, the row says "changes unknown: add
this folder" with a button that calls `chooseFolder` on its parent.

"Merged": the branch is merged into the default branch
(`git branch --merged origin/HEAD`) or its upstream is `[gone]`. A merged,
clean, unlocked worktree is "safe to remove".

Worktrees made by coding agents get a small label when their path matches a
known pattern (`.claude/worktrees/`, `.worktrees/`, Conductor's and
Codex's folders), because those pile up fastest.

UX:

- **Repository row:** a count badge, "3 worktrees", next to ↓↑. When
  some can be removed, it says "3 worktrees · 2 to clean up".
- **Expanded row:** one sub-row per worktree: folder name, branch, ↓↑,
  changes dot, last commit age, and labels (agent, locked, merged,
  missing). The main worktree is first and marked.
- **Per worktree:** Open (editor / terminal / Finder), Pull, Push, Copy
  path, Copy branch, Remove (clean only, confirms, never `--force`), Unlock.
  Missing ones offer Prune (`git worktree prune`).
- **Clean up:** a panel header button and a palette command, "Clean Up
  Worktrees", list every safe-to-remove worktree across repositories with
  checkboxes (all ticked), and remove the ticked ones; dirty or unmerged
  ones are listed below, unticked and explained.
- **New worktree…** on a repository: branch name (new or existing), folder
  from the setting below, then Open. `git worktree add <folder> -b <branch>`
  or without `-b` for an existing branch.
- **Window:** a Worktrees tab, a table across all repositories (repository,
  worktree, branch, state, last commit, labels) sortable by age, so the
  oldest abandoned ones float up.
- **Palette:** "Search Worktrees" by branch or folder name; Return opens it.
  Root search on branch names, so typing a branch jumps to its worktree.
- **Update All Safe** includes worktrees under the same rules (setting).

### Settings

| Setting | Options | Default |
| --- | --- | --- |
| Folders | list with Add / Remove; scan depth | none, with suggestions |
| Fetch every | 5, 15, 30, 60 min, manual | 15 min, and on wake |
| Pull | fast-forward only, rebase | fast-forward only |
| Uncommitted changes when updating | skip, stash and restore, ask | skip |
| Branches | current branch, all local branches | current |
| Menu bar | when something is behind, always, never | when behind |
| Count in menu bar | behind, behind + ahead | behind |
| Open in | Recent Projects-style editor list, Terminal, iTerm, Ghostty, Finder | Finder until set |
| Notifications | off, when repos fall behind, only when I have unpushed work too | off |
| Worktrees | under their repository, hidden | under their repository |
| Update All includes worktrees | on, off | on |
| New worktrees go in | next to the repository (`../repo-branch`), a `.worktrees` folder inside it, a folder you pick | next to the repository |
| Hidden repositories | list with Unhide | none |

### Surfaces

- **Menu bar:** `arrow.down.circle` + count; empty view (hidden) when
  nothing matches the setting.
- **Panel:** header with Fetch All and Update All Safe; sections by state;
  row = name, branch, ↓↑ badges, dirty dot, "fetched 5 min ago"; one
  primary button by state (Pull, Push, Open); ⌘K for the rest. Rows expand
  to the incoming commits.
- **Window:** table of repositories × branches with the same actions, and
  a Gone branches section with Prune.
- **Widget:** "4 behind, 2 unpushed" and an Update All Safe button.
- **Palette:** Search Local Repositories (status in the subtitle; Return
  opens, ⌘K actions), Update All Repositories, Fetch All Repositories.
  Root search on repository names.
- **Agent:** `repo_status` (read-only list of states). No write tools in
  1.0.

### Errors shown on the row

Not a repository any more (moved or deleted: offer Remove), authentication
failed (SSH or HTTPS: link to the README section), host unreachable, git not
installed (the Xcode Command Line Tools prompt: explain once at the top of
the panel), timed out.
