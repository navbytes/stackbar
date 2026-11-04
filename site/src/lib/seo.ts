// schema.org structured data for search engines, passed to Base as `jsonLd`.
import type { Plugin } from './plugins';
import { href, repo, version } from './site';

const ctx = { '@context': 'https://schema.org' };
const url = (site: URL | undefined, path: string) => new URL(href(path), site).href;
const orgId = (site: URL | undefined) => `${url(site, '/')}#organization`;
const appId = (site: URL | undefined) => `${url(site, '/')}#app`;

export const organization = (site: URL | undefined) => ({
  ...ctx,
  '@type': 'Organization',
  '@id': orgId(site),
  name: 'Stackbar',
  url: url(site, '/'),
  logo: url(site, '/apple-touch-icon.png'),
  sameAs: [repo],
});

export const website = (site: URL | undefined) => ({
  ...ctx,
  '@type': 'WebSite',
  name: 'Stackbar',
  url: url(site, '/'),
  publisher: { '@id': orgId(site) },
});

const free = { '@type': 'Offer', price: '0', priceCurrency: 'USD' };

export const stackbarApp = (site: URL | undefined, description: string) => ({
  ...ctx,
  '@type': 'SoftwareApplication',
  '@id': appId(site),
  name: 'Stackbar',
  description,
  url: url(site, '/'),
  downloadUrl: url(site, '/download/'),
  applicationCategory: 'DeveloperApplication',
  operatingSystem: 'macOS 26 or later',
  softwareVersion: version,
  license: 'https://opensource.org/licenses/MIT',
  isAccessibleForFree: true,
  offers: free,
  image: url(site, '/og.png'),
  codeRepository: repo,
  publisher: { '@id': orgId(site) },
});

const categoryOf: Record<string, string> = {
  Developer: 'DeveloperApplication', Productivity: 'BusinessApplication', Monitoring: 'UtilitiesApplication',
  System: 'UtilitiesApplication', Network: 'UtilitiesApplication',
};

export const pluginApp = (site: URL | undefined, plugin: Plugin, image: string | undefined) => ({
  ...ctx,
  '@type': 'SoftwareApplication',
  name: plugin.name,
  description: plugin.summary,
  url: url(site, `/plugins/${plugin.slug}/`),
  applicationCategory: categoryOf[plugin.category] ?? 'UtilitiesApplication',
  applicationSubCategory: `${plugin.category} plugin for Stackbar`,
  operatingSystem: 'macOS 26 or later',
  softwareVersion: plugin.version,
  dateModified: plugin.updated,
  softwareRequirements: `Stackbar ${plugin.minimumStackbar ?? version} or later`,
  isAccessibleForFree: true,
  offers: free,
  ...(image ? { image, screenshot: image } : {}),
  author: { '@type': 'Organization', name: plugin.publisher },
  isPartOf: { '@id': appId(site) },
});

/** Each crumb is a name and a site path, home first. */
export const breadcrumbs = (site: URL | undefined, crumbs: [string, string][]) => ({
  ...ctx,
  '@type': 'BreadcrumbList',
  itemListElement: crumbs.map(([name, path], i) => ({ '@type': 'ListItem', position: i + 1, name, item: url(site, path) })),
});

export const faq = (entries: { question: string; answer: string }[]) => ({
  ...ctx,
  '@type': 'FAQPage',
  mainEntity: entries.map((e) => ({ '@type': 'Question', name: e.question, acceptedAnswer: { '@type': 'Answer', text: e.answer } })),
});

export const itemList = (site: URL | undefined, plugins: Plugin[]) => ({
  ...ctx,
  '@type': 'ItemList',
  itemListElement: plugins.map((p, i) => ({ '@type': 'ListItem', position: i + 1, name: p.name, url: url(site, `/plugins/${p.slug}/`) })),
});
