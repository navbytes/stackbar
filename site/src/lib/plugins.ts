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
