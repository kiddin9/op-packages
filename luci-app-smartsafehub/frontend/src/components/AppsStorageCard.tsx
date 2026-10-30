import type { AppsStorage } from '../types/apps';
import { summarizeAppsStorage } from '../utils/appsStorage';

const RING_CIRCUMFERENCE = 2 * Math.PI * 39;

export function AppsStorageCard({ storage }: { storage: AppsStorage | null | undefined }) {
  const summary = summarizeAppsStorage(storage);
  const availableArc = summary ? (summary.availableRatio * RING_CIRCUMFERENCE).toFixed(2) : '0';
  return (
    <aside aria-label="앱 설치 저장 공간" data-level={summary?.level ?? 'unavailable'} class="ssh-apps-storage-card flex min-w-0 items-center gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5">
      <div class="ssh-apps-storage-ring relative grid size-24 shrink-0 place-items-center" data-level={summary?.level ?? 'unavailable'}>
        <svg aria-hidden="true" class="size-24" viewBox="0 0 96 96">
          <circle class="ssh-apps-storage-track" cx="48" cy="48" r="39" />
          {summary && summary.availableRatio > 0 ? (
            <circle class="ssh-apps-storage-free" cx="48" cy="48" r="39"
              stroke-dasharray={`${availableArc} ${RING_CIRCUMFERENCE.toFixed(2)}`} />
          ) : null}
        </svg>
        <div class="absolute inset-0 flex flex-col items-center justify-center text-center">
          <strong class="text-lg leading-6 font-black text-slate-950">{summary ? `${summary.availablePercent}%` : '—'}</strong>
          <span class="text-[10px] font-bold text-slate-500">여유</span>
        </div>
      </div>
      <div aria-live="polite" class="min-w-0 flex-1">
        <h3 class="m-0 text-sm font-black text-slate-950">저장 공간</h3>
        {summary ? (
          <>
            <p class="ssh-apps-storage-available mb-0 mt-1 text-base font-extrabold text-teal-700">{summary.availableText} 남음</p>
            <p class="mb-0 mt-1 text-[11px] leading-4 text-slate-500" title="앱 설치 가능 용량을 기준으로 계산하며, 파일시스템 예약 공간이 사용량에 포함될 수 있습니다.">
              사용 {summary.usedText} / 전체 {summary.totalText}
            </p>
          </>
        ) : (
          <p class="mb-0 mt-1 text-xs leading-5 text-slate-500">용량 정보를 확인할 수 없습니다.</p>
        )}
      </div>
    </aside>
  );
}
