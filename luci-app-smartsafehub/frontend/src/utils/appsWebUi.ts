/** Only approved same-origin LuCI pages, known static apps or the fixed Jarbis route. */
export function approvedAppPath(webUi: { type: string; path: string } | null | undefined): string | null {
  if (!webUi || typeof webUi.path !== 'string' || webUi.path.length > 160) return null;
  if (webUi.type === 'smartsafehub') return webUi.path === '#smarthome' ? '#smarthome' : null;
  if (webUi.type === 'static') return ['/retro-arcade/', '/arcdrop/'].includes(webUi.path) ? webUi.path : null;
  if (webUi.type !== 'luci') return null;
  return /^\/cgi-bin\/luci\/admin\/[a-z0-9_-]+(?:\/[a-z0-9_-]+)*$/.test(webUi.path) ? webUi.path : null;
}
