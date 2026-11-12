# Usage charts and user-chosen servers

## Why
Naveen asked for a LiteLLM plugin (ported from vee-plugins' `litellm-cost`)
with "decent charts and graphs", modelled on a usage dashboard with stat
tiles, a daily activity heatmap, a trend chart and a model mix. Two things
were missing from Stackbar:

- **A heatmap.** `Chart` drew lines, bars, areas and donuts only, and axes
  printed raw numbers (`1940000000`), unreadable for token counts.
- **A server the user chooses.** `.network(hosts:)` is fixed in the manifest,
  but a LiteLLM proxy (like GitHub Enterprise or a self-hosted Jira) lives
  wherever the user runs it. The only way out was `.network("*")`, which hands
  the plugin, and the key it holds, the whole internet.

## What changes
- `ChartKind.heatmap`: one value per day, oldest first and today last, drawn
  as week columns with five shades and a Less/More legend.
- Charts shorten large numbers (`174.4M`, `1.9B`) and a donut lists each
  slice's share.
- `Capability.userServer(secret:)`: the user enters the server's URL as that
  secret; the plugin reads it with `Stackbar.secret` and may reach that
  URL's host and no other. Unset, nothing is reachable.
- Both need Stackbar 0.11.0, the version the first-party move ships in.
