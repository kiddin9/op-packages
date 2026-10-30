import { useEffect, useState } from 'preact/hooks';

import type { AppRoute } from '../app/routes';

const HASH_ROUTES: Readonly<Record<string, AppRoute>> = {
  '#home': 'home',
  '#activity': 'activity',
  '#network': 'network',
  '#network/internet': 'network',
  '#network/lan': 'network',
  '#wan': 'network',
  '#lan': 'network',
  '#wifi': 'wifi',
  '#iptv': 'iptv',
  '#devices': 'devices',
  '#safeshield': 'safeshield',
  '#rules': 'rules',
  '#account': 'account',
  '#apps': 'apps',
  '#system': 'system',
  '#settings': 'settings',
  '#settings/diagnostics': 'settings',
  '#settings/time': 'settings',
  '#settings/management': 'settings',
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
