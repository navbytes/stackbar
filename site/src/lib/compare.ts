// The /compare/ table. Competitor facts come from their own pages (or, where
// marked, a review), checked on `checked`. Update the date when you re-check.
export const checked = '2026-11-05';

export type Tone = 'good' | 'some' | 'none';
export type Cell = { text: string; tone: Tone };
export type Product = { key: 'stackbar' | 'raycast' | 'alfred' | 'spotlight'; name: string; note: string };

export const products: Product[] = [
  { key: 'stackbar', name: 'Stackbar', note: 'Open source launcher' },
  { key: 'raycast', name: 'Raycast', note: 'Launcher with AI plans' },
  { key: 'alfred', name: 'Alfred', note: 'Launcher with Powerpack' },
  { key: 'spotlight', name: 'Spotlight', note: 'Built into macOS 26' },
];

type Row = { label: string } & Record<Product['key'], Cell>;
const good = (text: string): Cell => ({ text, tone: 'good' });
const some = (text: string): Cell => ({ text, tone: 'some' });
const none = (text: string): Cell => ({ text, tone: 'none' });

export const rows: Row[] = [
  { label: 'Price', stackbar: good('Free'), raycast: some('Free; Pro $10 a month'), alfred: some('Free; Powerpack £34'), spotlight: good('Included') },
  { label: 'Account', stackbar: good('None'), raycast: some('For paid plans and sync'), alfred: good('None'), spotlight: good('None') },
  { label: 'Open source', stackbar: good('Yes, MIT'), raycast: some('Extensions only'), alfred: none('No'), spotlight: none('No') },
  { label: 'Extensions in', stackbar: good('Swift, one file'), raycast: good('TypeScript and React'), alfred: good('Workflows and scripts'), spotlight: some('App Intents and Shortcuts') },
  { label: 'Apps, files, sums', stackbar: good('Yes'), raycast: good('Yes'), alfred: good('Yes'), spotlight: good('Yes') },
  { label: 'Clipboard history', stackbar: good('Yes'), raycast: good('Yes'), alfred: some('With Powerpack'), spotlight: good('Yes') },
  { label: 'Snippets', stackbar: some('Paste by name; no typed expansion yet'), raycast: good('Yes, with expansion'), alfred: some('With Powerpack'), spotlight: none('No') },
  { label: 'Window layouts', stackbar: good('Yes'), raycast: good('Yes'), alfred: some('With workflows'), spotlight: none('No') },
  { label: 'Live menu bar items', stackbar: good('Yes'), raycast: good('Yes'), alfred: none('No'), spotlight: none('No') },
  { label: 'Desktop widgets', stackbar: good('Yes'), raycast: none('No'), alfred: none('No'), spotlight: none('No') },
  { label: 'Built-in AI chat', stackbar: none('No; bring your agent'), raycast: good('With paid plans'), alfred: some('With workflows'), spotlight: none('No') },
  { label: 'Tools for your AI agents (MCP)', stackbar: good('Every plugin tool'), raycast: some('Uses MCP servers in its AI'), alfred: none('No'), spotlight: none('No') },
  { label: 'Plugin isolation', stackbar: good('Own sandboxed process, approved access'), raycast: some('Reviewed store'), alfred: some('Runs as you'), spotlight: good('Apps\' own sandbox') },
  { label: 'Platforms', stackbar: some('macOS 26, Apple Silicon'), raycast: good('Mac, Windows, iOS'), alfred: good('Mac'), spotlight: good('Mac') },
];

export const sources = [
  { label: 'Raycast plans and pricing', url: 'https://manual.raycast.com/billing' },
  { label: 'Raycast extension API (React, TypeScript)', url: 'https://developers.raycast.com/' },
  { label: 'Alfred Powerpack', url: 'https://www.alfredapp.com/shop/' },
  { label: 'Spotlight in macOS Tahoe (MacRumors)', url: 'https://www.macrumors.com/how-to/do-more-with-spotlight-in-macos-tahoe/' },
];
