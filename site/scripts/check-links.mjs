// Fails when a page in dist/ links to a page or file inside the site that the
// build did not produce. External links are left to a scheduled check.
import fs from 'node:fs';
import path from 'node:path';

const dist = path.resolve(process.argv[2] ?? 'dist');
const base = (process.env.SITE_BASE ?? '/stackbar').replace(/\/$/, '');
const pages = fs.readdirSync(dist, { recursive: true }).filter((f) => f.endsWith('.html'));
const broken = [];
for (const page of pages) {
  const html = fs.readFileSync(path.join(dist, page), 'utf8');
  for (const [, link] of html.matchAll(/(?:href|src)="([^"#?]+)/g)) {
    if (!link.startsWith('/') || link.startsWith('//')) continue;
    if (base && !link.startsWith(`${base}/`) && link !== base) { broken.push(`${page}: ${link} (outside ${base}/)`); continue; }
    const target = path.join(dist, decodeURIComponent(link.slice(base.length)));
    const exists = fs.existsSync(target) && (fs.statSync(target).isFile() || fs.existsSync(path.join(target, 'index.html')));
    if (!exists) broken.push(`${page}: ${link}`);
  }
}
if (broken.length) { console.error(`Broken links:\n${[...new Set(broken)].join('\n')}`); process.exit(1); }
console.log(`links: ${pages.length} pages, no broken internal links`);
