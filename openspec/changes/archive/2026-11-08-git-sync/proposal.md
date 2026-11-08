# Git Sync: are my local clones behind?

## Why

Developers keep many clones on their Mac and often start work on one that
is days behind its remote, or forget commits they never pushed. PR Cockpit
shows what is happening on GitHub but knows nothing about local clones. Git
Sync shows, in one place, which local repositories are behind, ahead,
diverged or dirty, and updates the safe ones with one click.

It is a separate store plugin, not part of PR Cockpit (Naveen, 11-08):

- PR Cockpit asks only for `api.github.com` and a token. Running `git` in
  the user's code folders is a much broader ask, and every PR Cockpit user
  would have to approve it on update.
- It works with any remote (GitHub, GitLab, Bitbucket, self-hosted) and
  needs no token.
- It refreshes on a different rhythm: cheap local checks often, network
  fetches rarely.

Store users have different setups, so where repositories live, what happens
to uncommitted work, and how pulls are done are all settings, with safe
defaults.

## What changes

### Host (Stackbar)

- **Folders the user picks.** `Stackbar.chooseFolder(prompt:)` shows an
  open panel for a folder. The pick itself is the consent, like
  `chooseFile`, so it needs no capability. The host remembers the grant per
  plugin, lists it on the plugin's Settings page with a Remove button, and
  `Stackbar.grantedFolders()` returns the folders still granted. Granted
  folders count as `.files` paths for `Stackbar.run(workingDirectory:)`.
- **SSH agent.** A new `.sshAgent` capability passes the host's
  `SSH_AUTH_SOCK` to the plugin's commands, so `git fetch` over SSH can use
  the user's agent (the macOS agent, 1Password, Secretive). The install
  sheet says "Uses your SSH keys through the SSH agent". Without it, runs
  keep today's environment.

### Plugin (stackbar-plugins `Developer/GitSync`)

- **Status per repository:** branch, ahead/behind its upstream,
  uncommitted changes, conflicts in progress (merge, rebase), no upstream,
  upstream gone, and when it was last fetched.
- **Surfaces:** menu bar (hidden when all synced by default, ↓N when
  behind), panel grouped by state, window with every local branch, widget
  with the count and an Update button, palette commands, settings, opt-in
  notifications, and a `repo_status` agent tool.
- **Worktrees:** a count on each repository, every worktree's branch and
  state under it, and a Clean Up view for merged ones left behind.
- **Actions:** Fetch, Pull, Push (never forced), Update All Safe, show the
  incoming commits, open in the editor, terminal or Finder, open the
  compare view on the web, copy the branch, prune branches whose upstream
  is gone.
- **Safe by default:** fetch runs on its own because it never touches the
  working tree. Pull is fast-forward only. A dirty repository is skipped
  unless the user chooses otherwise. Diverged repositories always wait for
  the user.

## Not in this change

- Merging, resolving conflicts or committing. Diverged and conflicted
  repositories open in the user's tools.
- Force push of any kind.
- Linking with PR Cockpit (a "local: 3 behind" badge on its rows, "Open
  PRs" here). A small follow-up once both exist.
- Policing `git -C` and similar arguments. An approved command runs
  outside the sandbox, as `host-run-and-context` already says; the
  working-directory rule is about intent, not a wall.
