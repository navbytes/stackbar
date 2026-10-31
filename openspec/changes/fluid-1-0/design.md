## Decisions

- **Host calls are request/response on the same pipe.** Responses are routed
  from the plugin's reader thread straight to `HostClient`, outside the serial
  message loop, so a plugin awaiting a host call inside a handler cannot
  deadlock itself.
- **Capabilities are enforced in one place, `HostServices.handle`,** against
  what the user approved, not what the manifest asks for. Until a changed
  manifest is approved the plugin keeps its previous grants.
- **OAuth uses a loopback redirect and PKCE**, with tokens stored as secrets
  and refreshed by the host; the plugin only ever sees an access token.
- **All plugins build in one SwiftPM workspace**, one target per plugin
  version, so FluidKit compiles once. Builds are serialized with `flock`, and
  targets beyond the 64 most recent are pruned.
- **Helpers are process-group leaders started with `posix_spawn`.** Stopping
  a plugin snapshots its descendants first (Foundation's `Process` gives each
  child its own group), then signals the group and each descendant.
- **Limits per plugin** (calls, HTTP, in-flight calls, notifications, log
  lines, storage, bus payloads, response size) live next to the code they
  guard, with messages that say what the limit is.
- **No GitHub-hosted macOS runners**, for cost. `scripts/check.sh` is the one
  gate, run by the Linux job, the self-hosted Mac job and by hand.

## Risks

- The app, `FluidUI`, the widget, CryptoKit signing and the Keychain store
  have not been compiled yet; they only build on macOS.
- A crashed helper's `Process`-spawned children can outlive it (see the
  `ponytail:` in `PluginProcess`).
