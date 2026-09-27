function safeFilenamePart(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-');

  return normalized || 'openwrt';
}

export function diagnosticFilename(hostname: string, generatedAt: number): string {
  const date = new Date(generatedAt * 1000).toISOString().replace(/[:.]/g, '-');

  return `smartsafehub-diagnostics-${safeFilenamePart(hostname)}-${date}.json`;
}

export function downloadJson(filename: string, value: unknown): void {
  const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], {
    type: 'application/json;charset=utf-8',
  });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');

  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  (document.body ?? document.documentElement).appendChild(anchor);
  anchor.click();
  anchor.remove();

  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}
