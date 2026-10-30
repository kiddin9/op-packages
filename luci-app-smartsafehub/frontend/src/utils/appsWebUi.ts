/** Only approved same-origin LuCI pages or the first-party Retro Arcade entry point. */
export function approvedAppPath(webUi: { type: string; path: string } | null | undefined): string | null {
  if (!webUi || typeof webUi.path !== 'string' || webUi.path.length > 160) return null;
  if (webUi.type === 'static') return webUi.path === '/retro-arcade/' ? webUi.path : null;
  if (webUi.type !== 'luci') return null;
  return /^\/cgi-bin\/luci\/admin\/[a-z0-9_-]+(?:\/[a-z0-9_-]+)*$/.test(webUi.path) ? webUi.path : null;
}
