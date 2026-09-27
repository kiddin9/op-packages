import { useEffect, useState } from 'preact/hooks';

import type { AppRoute } from '../app/routes';

const HASH_ROUTES: Readonly<Record<string, AppRoute>> = {
  '#home': 'home',
  '#activity': 'activity',
  '#lan': 'lan',
  '#wifi': 'wifi',
  '#iptv': 'iptv',
  '#devices': 'devices',
  '#safeshield': 'safeshield',
  '#rules': 'rules',
  '#system': 'system',
  '#settings': 'settings',
};

function routeFromHash(): AppRoute {
  return HASH_ROUTES[window.location.hash] ?? 'home';
}

export function useHashRoute(): AppRoute {
  const [route, setRoute] = useState<AppRoute>(routeFromHash);

  useEffect(() => {
    const handleChange = () => setRoute(routeFromHash());

    window.addEventListener('hashchange', handleChange);
    return () => window.removeEventListener('hashchange', handleChange);
  }, []);

  return route;
}
