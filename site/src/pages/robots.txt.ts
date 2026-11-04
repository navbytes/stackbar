import type { APIRoute } from 'astro';

// Everything may be crawled; the sitemap lists every page.
export const GET: APIRoute = ({ site }) => {
  const sitemap = new URL(`${import.meta.env.BASE_URL.replace(/\/$/, '')}/sitemap-index.xml`, site);
  return new Response(`User-agent: *\nAllow: /\n\nSitemap: ${sitemap.href}\n`, { headers: { 'content-type': 'text/plain; charset=utf-8' } });
};
