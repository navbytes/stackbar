# Tasks

> Archived 2026-11-08. The unticked Mac checks below are tracked in `openspec/mac-checks.md`.

## 1. Host (stackbar)
- [x] 1.1 Protocol 24: `HostCall.chooseFolder(prompt:)`, `ChosenFolder`, `HostCall.grantedFolders`, `Capability.sshAgent`
- [x] 1.2 Folder grants in the plugin ledger; refused picks (`/`, `~`, `~/Library`, system folders); `CommandRunGate` allows granted folders as working directories
- [x] 1.3 Settings page: "Folders you chose" with Remove (refresh with reason `.settings`)
- [x] 1.4 `SSH_AUTH_SOCK` passed for `.sshAgent`, reserved for plugins; install sheet line
- [x] 1.5 MacSystem open panel; SimulatedSystem and `STACKBAR_CHOOSE_FOLDER` for `stackbarctl`
- [x] 1.6 StackbarKit `Stackbar.chooseFolder`, `Stackbar.grantedFolders`
- [x] 1.7 Tests: grant, refusal, removal stops runs, agent variable present only with the capability
- [x] 1.8 AuthoringGuide + llms.txt, CHANGELOG

## 2. Plugin (stackbar-plugins `Developer/GitSync`, 1.0.0)
- [x] 2.1 Discovery: picked folders with depth, single repos, hidden list (suggestions from recent editor projects left for later)
- [x] 2.2 Status from `git status --porcelain=v2 --branch`; all-branches mode with `for-each-ref`
- [x] 2.2a Worktrees: grouping, `worktree list`, per-worktree status, merged / missing / agent labels, Remove / Prune (Unlock left to `git worktree unlock`), Clean Up, New Worktree, Search Worktrees
- [x] 2.3 Fetch scheduler (interval setting, wake, 3 at once, staggered)
- [x] 2.4 Pull (ff-only / rebase), dirty handling (skip / stash / ask), push, Update All Safe
- [x] 2.5 Panel, menu bar, window, widget, palette commands, root search, settings
- [x] 2.6 Notifications (opt-in) and `repo_status` agent tool
- [x] 2.7 Row errors (moved, auth, offline, no git, timeout)
- [x] 2.8 README, preview scenes with sample data, `scripts/check.sh`

## 3. Ship
- [x] 3.1 Release the host (minimumStackbar for Git Sync)
- [x] 3.2 Publish Git Sync 1.0.0 (stackbar-plugins #64, with Stackbar 0.34.0)
- [ ] 3.3 Check on Naveen's Mac: SSH remote, HTTPS remote, a dirty repo, a diverged repo
