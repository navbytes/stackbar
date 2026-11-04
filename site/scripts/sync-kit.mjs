// Writes src/generated/, public/icon.svg, public/install.sh and public/llms.txt from the Swift sources (see kit.mjs).
// Runs before dev, build and check; the outputs are not committed.
import fs from 'node:fs';
import path from 'node:path';
import { repoRoot, readDesign, readStore, readVersion, readBrand, designCSS } from './kit.mjs';

const site = path.join(repoRoot, 'site');
const design = readDesign();
fs.mkdirSync(path.join(site, 'src/generated'), { recursive: true });
fs.writeFileSync(path.join(site, 'src/generated/kit.css'), designCSS(design, readBrand()));
fs.writeFileSync(path.join(site, 'src/generated/kit.json'), JSON.stringify({
  version: readVersion(), store: readStore(), hues: Object.keys(design.hues),
}, null, 2) + '\n');
fs.mkdirSync(path.join(site, 'public'), { recursive: true });
fs.copyFileSync(path.join(repoRoot, 'Packaging/Icon/AppIcon.svg'), path.join(site, 'public/icon.svg'));
// `curl -fsSL https://stackbar.app/install.sh | bash`
fs.copyFileSync(path.join(repoRoot, 'scripts/get-stackbar.sh'), path.join(site, 'public/install.sh'));
// The plugin authoring guide for AI tools and answer engines (llmstxt.org).
fs.copyFileSync(path.join(repoRoot, 'llms.txt'), path.join(site, 'public/llms.txt'));
console.log(`site: kit synced (${Object.keys(design.hues).length} hues, Stackbar ${readVersion()})`);
