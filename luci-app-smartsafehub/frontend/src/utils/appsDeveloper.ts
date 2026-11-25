/** Public catalog URLs are display-only; never used by package installer. */
export function safeDeveloperUrl(value: string | undefined): string | null {
  if (!value || value.length > 500 || /[\s\\<>"'@#]/.test(value)) return null;
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase().replace(/\.$/, '');
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash
      || !/^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/.test(host)
      || host.endsWith('.local') || host.endsWith('.localhost') || host.endsWith('.internal')) return null;
    return url.href;
  } catch {
    return null;
  }
}

/** Icons are sanitized PNGs served by the SmartSafeHub Hub, not arbitrary third parties. */
export function safeAppIconUrl(value: string | undefined): string | null {
  const href = safeDeveloperUrl(value);
  if (!href) return null;
  const url = new URL(href);
  return url.hostname === 'www.smartsafehub.com'
    && url.port === '' && url.search === ''
    && /^\/media\/app-icons\/[a-f0-9]{32}\.png$/.test(url.pathname) ? href : null;
}
