const DEFAULT_CGI_BASE = '/cgi-bin';
const DEFAULT_LUCI_BASE = `${DEFAULT_CGI_BASE}/luci`;

export function luciBaseUrl(): string {
  const marker = '/cgi-bin/luci';
  const pathname = window.location.pathname;
  const markerIndex = pathname.indexOf(marker);

  if (markerIndex >= 0) {
    return pathname.slice(0, markerIndex + marker.length);
  }

  return DEFAULT_LUCI_BASE;
}

export function cgiBaseUrl(): string {
  const luciBase = luciBaseUrl();
  const suffix = '/luci';

  if (luciBase.endsWith(suffix)) {
    return luciBase.slice(0, -suffix.length);
  }

  return DEFAULT_CGI_BASE;
}

export function cgiUrl(route: string): string {
  const normalizedRoute = route.startsWith('/') ? route : `/${route}`;
  return `${cgiBaseUrl()}${normalizedRoute}`;
}

export function luciUrl(route: string): string {
  const normalizedRoute = route.startsWith('/') ? route : `/${route}`;
  return `${luciBaseUrl()}${normalizedRoute}`;
}

export function luciAdminUrl(route: string): string {
  return luciUrl(route);
}

export function smartSafeHubPublicUrl(hash = ''): string {
  const normalizedHash = hash
    ? hash.startsWith('#')
      ? hash
      : `#${hash}`
    : '';

  return `/${normalizedHash}`;
}
