import { ReloadIcon } from './Icons';

export function LoadingPanel() {
  return (
    <section
      aria-busy="true"
      aria-live="polite"
      class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6"
    >
      <div class="flex items-center gap-4">
        <ReloadIcon class="size-8 shrink-0 animate-spin text-teal-700" />
        <div class="min-w-0 text-left">
          <h2 class="m-0 text-lg font-extrabold text-slate-950">
            장치 상태를 확인하고 있습니다
          </h2>
          <p class="mt-1 mb-0 text-sm leading-6 text-slate-600">
            OpenWrt의 rpcd API에서 정보를 불러오는 중입니다.
          </p>
        </div>
      </div>
    </section>
  );
}

interface ErrorPanelProps {
  message: string;
  onRetry: () => void;
}

export function ErrorPanel({ message, onRetry }: ErrorPanelProps) {
  return (
    <section
      aria-live="assertive"
      class="rounded-2xl border border-red-200 bg-red-50 p-5 sm:p-6"
    >
      <p class="m-0 text-xs font-bold uppercase tracking-[0.16em] text-red-700">
        연결 오류
      </p>
      <h2 class="mt-2 mb-0 text-lg font-extrabold text-red-950">
        장치 상태를 불러오지 못했습니다
      </h2>
      <p class="mt-2 mb-0 text-sm leading-6 text-red-800">{message}</p>
      <button
        class="mt-5 inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border-0 bg-red-700 px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-red-800 focus:outline-none focus-visible:ring-4 focus-visible:ring-red-200"
        onClick={onRetry}
        type="button"
      >
        <ReloadIcon class="size-4" />
        다시 시도
      </button>
    </section>
  );
}
