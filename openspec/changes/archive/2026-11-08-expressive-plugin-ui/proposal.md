# Expressive plugin UI (protocol 12)

## Why

After the design system pass, Naveen said the plugins are functional but not
fancy enough. Standout menu-bar and widget apps make content the hero, with
real album art, avatars and favicons, light that follows the content,
numbers that roll, and glass controls. They also give each tool one signature
visual. Protocol 11 can't draw most of that: images are SF Symbols only,
gradients are linear only, and there is no glass, symbol motion, hover or
grid. This is phase 2 of `rich-plugin-ui`, which the Pomodoro thread handed
to this work. The per-plugin direction is in the Claude Doc "Stackbar
plugins: bold second pass".

## What changes

- **Paints:** `Paint.radialGradient`, `Paint.angularGradient` and
  `Paint.material` (ultra thin to thick, plus Liquid Glass for floating
  controls). `Paint.stops` gives the colors the contrast lint checks.
- **Images:** `ImageSource.url` (https) fills its frame, cropped. The host
  fetches the image through `HTTPService`, only from domains the plugin
  declared and the user approved. The limits are `RemoteImageLimits`: 4 MB
  each and 64 per tree. Images are kept in memory by `RemoteImageStore`.
  `render --png` fetches before drawing. Widgets show the placeholder.
- **Style:** `blur` (ordered after shadow), `symbol` (rendering mode,
  palette, effect, environment-like), `numericTransition`
  (environment-like) and `hover` (ordered last; panel and window only).
- **Nodes:** `grid(columns:spacing:children:)` and `ChartOptions.compact`
  for sparklines.
- **Kit:** `Image(url:placeholder:)`, `Grid`, `.blur`, `.symbolEffect`,
  `.symbolRendering`, `.numericTransition`, `.hover`. Design components
  `Backdrop`, `GlassBar`, `Avatar`, `AvatarStack`, `RingCluster`,
  `Sparkline`, `Tile` and `Sky`. `HeroCard(look: .glow | .vivid)`,
  `IconButton(prominence: .onMedia)`. Theme paints `glow`, `vivid`, `sweep`
  and `track`.
- Effects and transitions stop under Reduce Motion, and materials follow
  Reduce Transparency.
- Protocol 12, Stackbar 0.14.0. Plugins that use any of it set
  `minimumStackbar: "0.14.0"`.

Custom fonts are left out. Bundled font files need a store packaging change,
and rounded system numerals cover the look for now.
