// Splits the repository's CHANGELOG.md into released versions, newest first.
// Each `## x.y.z` section becomes one release; `## Unreleased` is left out.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const changelog = fileURLToPath(new URL('../../CHANGELOG.md', import.meta.url));

export function parseChangelog(text) {
  const releases = [];
  let current;
  for (const line of text.split('\n')) {
    const heading = line.match(/^## (.+?)\s*$/);
    if (heading) {
      current = /^\d+\.\d+\.\d+/.test(heading[1]) ? { version: heading[1].match(/^\d+\.\d+\.\d+\S*/)[0], lines: [] } : undefined;
      if (current) releases.push(current);
    } else if (current) {
      current.lines.push(line);
    }
  }
  return releases.map(({ version, lines }) => ({ version, body: lines.join('\n').trim() }));
}

export function readChangelog(path = changelog) {
  return parseChangelog(readFileSync(path, 'utf8'));
}
