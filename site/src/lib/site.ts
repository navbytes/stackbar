import kit from '../generated/kit.json';

export const version = kit.version;
export const store = kit.store;
export const repo = 'https://github.com/navbytes/stackbar';
export const releases = `${repo}/releases/latest`;

/** A path inside the site, under the configured base. */
export function href(path = '/'): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, '');
  return `${base}${path.startsWith('/') ? path : `/${path}`}`;
}
