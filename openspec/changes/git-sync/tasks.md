# Tasks

## 1. Host (stackbar)
- [ ] 1.1 Protocol 24: `HostCall.chooseFolder(prompt:)`, `ChosenFolder`, `HostCall.grantedFolders`, `Capability.sshAgent`
- [ ] 1.2 Folder grants in the plugin ledger; refused picks (`/`, `~`, `~/Library`, system folders); `CommandRunGate` allows granted folders as working directories
- [ ] 1.3 Settings page: "Folders you chose" with Remove (refresh with reason `.settings`)
- [ ] 1.4 `SSH_AUTH_SOCK` passed for `.sshAgent`, reserved for plugins; install sheet line
- [ ] 1.5 MacSystem open panel; SimulatedSystem and `stackbarctl --choose-folder`
- [ ] 1.6 StackbarKit `Stackbar.chooseFolder`, `Stackbar.grantedFolders`
- [ ] 1.7 Tests: grant, refusal, removal stops runs, agent variable present only with the capability
- [ ] 1.8 AuthoringGuide + llms.txt, CHANGELOG

## 2. Plugin (stackbar-plugins `Developer/GitSync`, 1.0.0)
- [ ] 2.1 Discovery: picked folders with depth, single repos, hidden list, suggestions
- [ ] 2.2 Status from `git status --porcelain=v2 --branch`; all-branches mode with `for-each-ref`
- [ ] 2.3 Fetch scheduler (interval setting, wake, 3 at once, staggered)
- [ ] 2.4 Pull (ff-only / rebase), dirty handling (skip / stash / ask), push, Update All Safe
- [ ] 2.5 Panel, menu bar, window, widget, palette commands, root search, settings
- [ ] 2.6 Notifications (opt-in) and `repo_status` agent tool
- [ ] 2.7 Row errors (moved, auth, offline, no git, timeout)
- [ ] 2.8 README, preview scenes with sample data, `scripts/check.sh`

## 3. Ship
- [ ] 3.1 Release the host (minimumStackbar for Git Sync)
- [ ] 3.2 Publish Git Sync 1.0.0
- [ ] 3.3 Check on Naveen's Mac: SSH remote, HTTPS remote, a dirty repo, a diverged repo
