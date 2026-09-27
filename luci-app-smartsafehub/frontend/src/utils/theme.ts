export type ColorTheme = 'dark' | 'light';

export const THEME_STORAGE_KEY = 'smartsafehub.theme';

export function readColorTheme(): ColorTheme {
  if (typeof window === 'undefined') {
    return 'light';
  }

  try {
    const storedTheme = window.localStorage.getItem(THEME_STORAGE_KEY);

    if (storedTheme === 'dark' || storedTheme === 'light') {
      return storedTheme;
    }
  } catch {
    // Storage can be unavailable in privacy-restricted browser contexts.
  }

  return window.matchMedia('(prefers-color-scheme: dark)').matches
    ? 'dark'
    : 'light';
}

export function persistColorTheme(theme: ColorTheme): void {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    // Storage can be unavailable in privacy-restricted browser contexts.
  }
}

export function applyDocumentTheme(theme: ColorTheme): void {
  const themeColor = document.querySelector<HTMLMetaElement>(
    'meta[name="theme-color"]',
  );

  if (themeColor) {
    themeColor.content = theme === 'dark' ? '#0f172a' : '#f8fafc';
  }

  document.documentElement.style.colorScheme = theme;
  document.body.style.backgroundColor = theme === 'dark' ? '#020617' : '#f8fafc';
}
