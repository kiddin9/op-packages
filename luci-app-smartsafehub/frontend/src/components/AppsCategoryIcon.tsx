import { AppsIcon, CircleEllipsisIcon, GamepadIcon, HomeIcon, NetworkNodesIcon, ShieldIcon, WrenchIcon } from './Icons';

export type AppsCategory = 'all' | 'network' | 'security' | 'smart_home' | 'entertainment' | 'utilities' | 'other';

/** Normalize catalog categories once for both the filter and icon fallback. */
export function appsCategoryOf(category: string): AppsCategory {
  switch (category) {
    case 'network': return 'network';
    case 'security': return 'security';
    case 'entertainment': return 'entertainment';
    case 'utilities': return 'utilities';
    case 'other': return 'other';
    case 'smart_home':
    case 'iot': return 'smart_home';
    default: return 'other';
  }
}

/** Local SVG icons: never fetch or execute artwork from a catalog entry.
 * When verified per-app icons are supported, use these as the fallback. */
export function AppsCategoryIcon({ category, class: className }: { category: AppsCategory; class?: string }) {
  switch (category) {
    case 'all': return <AppsIcon class={className} />;
    case 'network': return <NetworkNodesIcon class={className} />;
    case 'security': return <ShieldIcon class={className} />;
    case 'smart_home': return <HomeIcon class={className} />;
    case 'entertainment': return <GamepadIcon class={className} />;
    case 'utilities': return <WrenchIcon class={className} />;
    case 'other': return <CircleEllipsisIcon class={className} />;
    default: return <CircleEllipsisIcon class={className} />;
  }
}
