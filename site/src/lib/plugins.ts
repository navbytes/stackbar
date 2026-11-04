import type { CollectionEntry } from 'astro:content';
import kit from '../generated/kit.json';

export type Plugin = CollectionEntry<'plugins'>['data'];

/** Store categories in the order the store lists them (scripts/lint.py). */
export const categories = ['Productivity', 'Developer', 'Monitoring', 'System', 'Network'] as const;

// A plugin wears its manifest's `accent`; one without takes its category's
// design-system hue.
const categoryHue: Record<string, string> = {
  Productivity: 'violet', Developer: 'indigo', Monitoring: 'green', System: 'amber', Network: 'teal',
};
export const hueOf = (plugin: { category: string; accent?: string }) =>
  (plugin.accent && plugin.accent in kit.hues ? plugin.accent : undefined) ?? categoryHue[plugin.category] ?? 'blue';

export const surfaceNames: Record<string, string> = {
  menuBar: 'Menu bar', panel: 'Panel', window: 'Window', widget: 'Desktop widget', settings: 'Settings page', palette: 'Command palette',
};

export const categorySlug = (category: string) => category.toLowerCase();

export function byName(a: { data: Plugin }, b: { data: Plugin }) {
  return a.data.name.localeCompare(b.data.name);
}

type Appearance = 'light' | 'dark';
const pick = (shot: { light?: string; dark?: string } | undefined, appearance: Appearance) =>
  shot ? shot[appearance] ?? shot[appearance === 'dark' ? 'light' : 'dark'] : undefined;

/**
 * The picture that stands for a plugin: its `hero` preview (sample data,
 * Stackbar 0.17.0) when it has one, else its first panel preview, else the
 * panel render, else the store screenshot.
 */
export function heroShot(plugin: Plugin, appearance: Appearance = 'dark'): string | undefined {
  const hero = plugin.previews.find((p) => p.name === 'hero') ?? plugin.previews.find((p) => p.surface === 'panel');
  return pick(hero, appearance) ?? pick(plugin.gallery.find((g) => g.surface === 'panel'), appearance) ?? plugin.screenshot;
}

/**
 * The plugin's demo loop of its panel, when it has one: an animated PNG to
 * play in place of the hero picture, and how long one pass lasts.
 */
export function heroDemo(plugin: Plugin, appearance: Appearance = 'dark'): { src: string; seconds: number } | undefined {
  const demo = plugin.demo;
  const src = demo && demo.surface === 'panel' ? pick(demo, appearance) : undefined;
  return src ? { src, seconds: demo!.seconds } : undefined;
}

/** The plugin's own menu-bar item, as rendered for the store. */
export function menuBarShot(plugin: Plugin, appearance: Appearance = 'dark'): string | undefined {
  return pick(plugin.gallery.find((g) => g.surface === 'menuBar'), appearance);
}
