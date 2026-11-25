import { useState } from 'preact/hooks';
import { AppsCategoryIcon, appsCategoryOf } from './AppsCategoryIcon';
import type { VerifiedApp } from '../types/apps';
import { safeAppIconUrl } from '../utils/appsDeveloper';

/** An icon never affects verification, installation or launch paths. */
export function AppsArtwork({ app }: { app: VerifiedApp }) {
  const [failed, setFailed] = useState(false);
  const url = safeAppIconUrl(app.iconImageUrl);
  if (url && !failed) {
    return <span class="grid size-14 shrink-0 place-items-center overflow-hidden rounded-xl">
      <img alt="" class="size-full rounded-xl object-contain" decoding="async" loading="lazy" referrerPolicy="no-referrer" src={url}
        onError={() => setFailed(true)} />
    </span>;
  }

  return <span class="grid size-14 shrink-0 place-items-center overflow-hidden rounded-xl bg-slate-100 text-slate-600">
    <AppsCategoryIcon category={appsCategoryOf(app.category)} class="size-7" />
  </span>;
}
