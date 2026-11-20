// SPDX-License-Identifier: GPL-3.0-or-later
/** Only approved display targets are supported; this never authorizes an install. */
export function appsHighlightFromHash(hash: string): 'jarbis' | null {
  if (hash === '#apps/jarbis') return 'jarbis'; // Legacy Smart Home link.
  if (!hash.startsWith('#apps?')) return null;
  return new URLSearchParams(hash.slice('#apps?'.length)).get('highlight') === 'jarbis'
    ? 'jarbis' : null;
}
