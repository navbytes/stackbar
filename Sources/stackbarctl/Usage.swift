/// What `stackbarctl` prints for a command it doesn't know or can't read.
let usage = """
usage:
  stackbarctl new <plugin.swift> [--name "Display Name"] [--id dev.example.x]
  stackbarctl build <plugin.swift>
  stackbarctl manifest <plugin.swift | helper> [--json]
                                    --json prints {manifest, problems, publishingProblems}
  stackbarctl render <plugin.swift | helper> [--surface menuBar|panel|window|widget]
                  [--event <action-id>[=value]]... [--tool name[:json]] [--copy <text>]...
                  [--json] [--png <dir> [--dark]] [--verbose] [--preview <name>]
                  [--command <id> [--query <text>] [--arg name=value]...]
                  [--frames <out.png> [--hold <s>] [--wait <s>]...]
                  --frames writes an animated PNG of one surface (panel unless --surface):
                  a frame after the first render and after every step; --hold sets how long
                  the last frame shows (1 s by default), --wait pauses and adds a frame.
                  Without macOS it prints each frame as text.
                  --command opens a view command; --event then presses things inside it
                  --confirm sends events that ask for a second press at once; without it
                  their first --event is held, as in the app, and the same --event again sends it
                  --preview shows one of the plugin's previews (sample data, no refreshes)
                  --copy pretends you copied text in another app (clipboard plugins);
                  the clipboard, battery, calendar, windows and apps are simulated (STACKBAR_CALENDAR=<events.json>, STACKBAR_REMINDERS=<reminders.json>, STACKBAR_WINDOWS=<snapshot.json>, STACKBAR_APPS=<apps.json>)
  stackbarctl commands <plugin.swift | helper>        lists the plugin's commands
  stackbarctl previews <plugin.swift | helper> [--json]  lists the plugin's previews
  stackbarctl run <plugin.swift | helper> <command> [--arg name=value]...
                                    runs a command and prints its result
                  render and run take --selected-text <text> and --frontmost-app <bundle id>
                  for plugins with .context (or STACKBAR_CONTEXT=<json>)
  stackbarctl mcp                      authoring MCP server on stdio (for coding agents)
  stackbarctl agent [<plugin>...]      runtime MCP gateway on stdio: bridges to the running
                                    app, or runs the given plugins itself when it isn't
  stackbarctl secret set|get|delete <NAME> [value]
  stackbarctl call <plugin> <command> [--arg name=value]...
                                    runs a command in the running app and prints its result;
                                    like a stackbar:// link, it asks once unless the command
                                    has Links May Run It Without Asking (Settings › Commands)
  stackbarctl settings export <file> [--only plugins,data,commands,palette,preferences]
                                    writes the app's setup (no secrets or approvals) to a file
  stackbarctl settings import <file> [--replace]
                                    merges a settings file into the app's setup (quit Stackbar
                                    first); --replace puts the file's copies in place instead
  stackbarctl helper kit               the StackbarKit digest and protocol plugins build against here
  stackbarctl helper build <plugin.swift> --key <file> -o <binary> [--url <url>] [--cache <dir>]
                                    builds a helper to publish and prints its signed record (macOS)
  stackbarctl helper prebuild <dir> <plugin.swift | bundle.stackbarplugin>... [--cache <dir>]
                                    builds helpers into <dir> under the names the app looks for
  stackbarctl keygen [--key <file>]                   an Ed25519 publisher key (macOS)
  stackbarctl sign <plugin.swift> --publisher <name> [--key <file>] [-o <out.stackbarplugin>]
  stackbarctl verify <bundle.stackbarplugin>
  stackbarctl install <bundle.stackbarplugin | https://…> | --index <url> <plugin-id>
  stackbarctl index build <dir> [--name <name>] [--homepage <url>] [--revoked <file.json>] [--key <file>]
                                    writes <dir>/index.json from every bundle under <dir>;
                                    a subfolder is the category; --key signs it (macOS);
                                    sign and index build refuse a manifest with publishingProblems
  stackbarctl index verify <index.json | https://…> --public-key <base64>
  stackbarctl index search <url> [query] [--public-key <base64>]
  stackbarctl index fetch <dir> [--index <url>] [--public-key <base64>]
                                    downloads the first-party plugins' signed bundles
                                    (the official store by default) for the app to carry
  stackbarctl docs                     the plugin authoring reference
  stackbarctl parity                   the surface parity ledger
  stackbarctl soak <plugin> [--minutes 10] [--interval 1] [--press] [--growth 15]
                                    runs a plugin under load and fails if its memory grows
  stackbarctl logs [-n <lines>]        the end of the host log (the app's and stackbarctl's)
  stackbarctl doctor                   checks the toolchain, StackbarKit and data directories
  stackbarctl version

A .swift path is built first (cached by content); anything else is run as an
already-built helper. On macOS, render, commands, run, mcp, agent and soak run
plugins in the App Sandbox their manifest allows, as the app does; --no-sandbox
runs them unsigned. Plugins' saved values go to a scratch folder
(stackbarctl/Storage in Stackbar's cache), never the app's own; --real-storage
uses the app's. STACKBAR_PACKAGE overrides where StackbarKit is found, and
STACKBAR_HOME where Stackbar keeps its data (saved values included).
"""
