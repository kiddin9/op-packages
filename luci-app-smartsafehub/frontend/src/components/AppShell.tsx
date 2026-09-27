import type { ComponentChildren } from 'preact';
import { useEffect, useState } from 'preact/hooks';

import { ROUTE_BY_NAME } from '../app/routes';
import type { AppRoute } from '../app/routes';
import { applyDocumentTheme, persistColorTheme, readColorTheme } from '../utils/theme';
import type { ColorTheme } from '../utils/theme';
import { ProductHeader } from './ProductHeader';
import { ProductNavigation } from './ProductNavigation';

const SIDEBAR_COLLAPSED_STORAGE_KEY = 'smartsafehub.sidebar.collapsed';

interface AppShellProps {
  children: ComponentChildren;
  loading: boolean;
  onRefresh: () => void;
  refreshing: boolean;
  route: AppRoute;
  updateCount: number;
}

function readSidebarCollapsed(): boolean {
  if (typeof window === 'undefined') {
    return false;
  }

  try {
    return window.localStorage.getItem(SIDEBAR_COLLAPSED_STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

export function AppShell({
  children,
  loading,
  onRefresh,
  refreshing,
  route,
  updateCount,
}: AppShellProps) {
  const copy = ROUTE_BY_NAME[route];
  const [sidebarCollapsed, setSidebarCollapsed] = useState(readSidebarCollapsed);
  const [theme, setTheme] = useState<ColorTheme>(readColorTheme);

  useEffect(() => {
    try {
      window.localStorage.setItem(
        SIDEBAR_COLLAPSED_STORAGE_KEY,
        sidebarCollapsed ? '1' : '0',
      );
    } catch {
      // Storage can be unavailable in privacy-restricted browser contexts.
    }
  }, [sidebarCollapsed]);

  useEffect(() => {
    persistColorTheme(theme);
    applyDocumentTheme(theme);
  }, [theme]);

  return (
    <div
      class={`ssh-app min-h-screen bg-slate-50 text-slate-950 md:grid md:transition-[grid-template-columns] md:duration-200 md:ease-out ${
        sidebarCollapsed
          ? 'md:grid-cols-[5rem_minmax(0,1fr)]'
          : 'md:grid-cols-[16rem_minmax(0,1fr)]'
      }`}
      data-theme={theme}
    >
      <ProductNavigation
        collapsed={sidebarCollapsed}
        loading={loading}
        onRefresh={onRefresh}
        onToggleCollapsed={() => setSidebarCollapsed((collapsed) => !collapsed)}
        onToggleTheme={() => setTheme((current) => (current === 'dark' ? 'light' : 'dark'))}
        refreshing={refreshing}
        route={route}
        theme={theme}
        title={copy.title}
        updateCount={updateCount}
      />
      <div class="min-w-0 md:min-h-screen">
        <ProductHeader
          description={copy.description}
          loading={loading}
          onRefresh={onRefresh}
          onToggleTheme={() => setTheme((current) => (current === 'dark' ? 'light' : 'dark'))}
          refreshing={refreshing}
          theme={theme}
          title={copy.title}
        />
        <main
          class={`ssh-product-main w-full max-w-[1600px] bg-slate-50 px-4 pb-8 sm:px-6 sm:pb-10 lg:px-8 lg:pb-12 xl:px-10 ${
            loading
              ? 'pt-2 sm:pt-2 lg:pt-3'
              : 'pt-5 sm:pt-6 lg:pt-8'
          }`}
        >
          {children}
        </main>
      </div>
    </div>
  );
}
