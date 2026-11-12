## Why

Phase 0 proved the model: one Swift file, built by the host, run in its own
process, drawn natively. Naveen asked for the whole app, all phases, and then
for it to be made production quality (2026-10-31). This change records phases
1 to 3 of the design doc's roadmap and the hardening that followed.

## What Changes

- **Phase 1, services and surfaces:** protocol 2 with host calls; storage,
  secrets, HTTP, an OAuth broker, pub/sub, notifications; enforced
  capabilities with a network audit; a wider vocabulary (charts, fields,
  pickers, sliders, links); renderers for menu bar, panel, window and widget;
  the surface parity ledger; the authoring MCP server.
- **Phase 2, reach:** the command palette, the runtime MCP gateway over a Unix
  socket, widget snapshots, watched-file and topic triggers, four more examples.
- **Phase 3, trust and distribution:** capability approvals, signed
  `.fluidplugin` bundles with publisher pinning, a static plugin index,
  install and uninstall, forking.
- **Hardening:** one shared build workspace, process-group spawning, host call
  and log limits, a rolling host log, `fluidctl soak`, `doctor`, `logs`.
- **CI:** Linux on GitHub; macOS only on a self-hosted runner.

## Impact

- Vee is untouched.
- Plugins built against protocol 1 must be rebuilt; the host logs a warning.
