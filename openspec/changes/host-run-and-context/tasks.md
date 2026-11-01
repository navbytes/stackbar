# Tasks

## 1. Run
- [x] 1.1 `RunRequest`, `RunResult`, `HostCall.run`/`cancelRun`, `HostMessage.runOutput`/`runExit`
- [x] 1.2 Command resolution on the fixed search path; ledger stores resolved paths; "moved, approve again"
- [x] 1.3 `CommandRunGate`: approved set, environment, working directory under `.files`, limits, process-group kill
- [x] 1.4 Install sheet: resolved paths, "can run any program" for interpreters
- [x] 1.5 Run audit in the host log and on the plugin's Settings page
- [x] 1.6 StackbarKit `Stackbar.run`, `Stackbar.stream` (cancel on loop exit)

## 2. Context
- [x] 2.1 `Capability.context`; `InvocationContext` filled; `SystemServices.context()`, `finderSelection()`
- [x] 2.2 MacSystem: AX selected text and window title; Finder via Apple Events; entitlement and usage string
- [x] 2.3 Capture at hotkey, palette open, deeplink and intent, before Stackbar takes focus
- [x] 2.4 Simulated context in `stackbarctl` and tests

## 3. Docs and tests
- [x] 3.1 Authoring guide and `llms.txt`; the selected-text coverage list
- [x] 3.2 Tests: resolution, refusal, timeout, truncation, cancel, environment isolation, context gating
- [ ] 3.3 Manual checklist on Naveen's Mac
