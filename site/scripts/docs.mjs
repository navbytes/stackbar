// Reads the docs: src/docs/*.md (front matter: title, description, group,
// order) and the plugin reference from the repository's llms.txt.
import fs from 'node:fs';
import path from 'node:path';
import { repoRoot } from './kit.mjs';

const folder = path.join(repoRoot, 'site/src/docs');

/** Splits `---` front matter of `key: value` lines from the body. */
export function parseDoc(text, slug) {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(text);
  if (!match) throw new Error(`docs: ${slug}.md has no front matter`);
  const fields = Object.fromEntries(match[1].split('\n').filter(Boolean).map((line) => {
    const at = line.indexOf(':');
    if (at < 0) throw new Error(`docs: ${slug}.md: bad front matter line "${line}"`);
    const value = line.slice(at + 1).trim();
    return [line.slice(0, at).trim(), /^\d+$/.test(value) ? Number(value) : value];
  }));
  return { slug, ...fields, body: text.slice(match[0].length) };
}

/** llms.txt as a doc: its first heading is dropped, since the page has a title. */
export function authoringDoc(text) {
  return {
    slug: 'authoring',
    title: 'Plugin reference',
    description: 'The full Stackbar plugin authoring reference: views, commands, triggers, capabilities, host services and previews. The same text agents read as llms.txt.',
    group: 'Build plugins',
    order: 2,
    body: text.replace(/^# .*\n+/, ''),
  };
}

export function readDocs() {
  const docs = fs.readdirSync(folder).filter((f) => f.endsWith('.md')).sort()
    .map((f) => parseDoc(fs.readFileSync(path.join(folder, f), 'utf8'), f.replace(/\.md$/, '')));
  docs.push(authoringDoc(fs.readFileSync(path.join(repoRoot, 'llms.txt'), 'utf8')));
  return docs.sort((a, b) => (a.group === b.group ? a.order - b.order : a.group === 'Use Stackbar' ? -1 : 1));
}
