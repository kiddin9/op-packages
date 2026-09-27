import { MoonIcon, ReloadIcon, SunIcon } from './Icons';

interface ProductHeaderProps {
  description: string;
  loading: boolean;
  onRefresh: () => void;
  onToggleTheme: () => void;
  refreshing: boolean;
  theme: 'dark' | 'light';
  title: string;
}

export function ProductHeader({
  description,
  loading,
  onRefresh,
  onToggleTheme,
  refreshing,
  theme,
  title,
}: ProductHeaderProps) {
  return (
    <header class="ssh-product-hero border-b border-slate-200 bg-white px-4 py-4 sm:px-6 md:h-[4.5rem] md:py-0 lg:px-8 xl:px-10">
      <div class="flex w-full items-center justify-between gap-4 md:h-full">
        <div class="min-w-0">
          <p class="m-0 text-[0.68rem] font-extrabold uppercase tracking-[0.18em] text-teal-700">
            SmartSafeHub
          </p>
          <div class="mt-1 flex min-w-0 items-baseline gap-3">
            <h1 class="m-0 truncate text-xl font-black tracking-tight text-slate-950 sm:text-2xl">
              {title}
            </h1>
            <p class="m-0 hidden truncate text-sm text-slate-500 lg:block">
              {description}
            </p>
          </div>
        </div>

        <div class="flex shrink-0 items-center gap-2">
          <button
            aria-label={theme === 'dark' ? '라이트 모드로 전환' : '다크 모드로 전환'}
            class="ssh-product-header-action hidden h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-600 shadow-sm transition hover:border-teal-300 hover:text-teal-700 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 md:inline-flex"
            onClick={onToggleTheme}
            title={theme === 'dark' ? '라이트 모드' : '다크 모드'}
            type="button"
          >
            {theme === 'dark' ? <SunIcon class="size-5" /> : <MoonIcon class="size-5" />}
          </button>
          <button
            aria-busy={refreshing}
            aria-label={refreshing ? '새로고침 중' : '현재 화면 새로고침'}
            class={`ssh-product-header-action hidden h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-slate-200 bg-white shadow-sm transition hover:border-teal-300 hover:text-teal-700 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-wait disabled:opacity-60 md:inline-flex ${
              refreshing ? 'text-teal-700' : 'text-slate-600'
            }`}
            disabled={loading || refreshing}
            onClick={onRefresh}
            title={refreshing ? '새로고침 중' : '새로고침'}
            type="button"
          >
            {refreshing ? (
              <ReloadIcon class="size-5 animate-spin" />
            ) : (
              <ReloadIcon class="size-5" />
            )}
          </button>
        </div>
      </div>
    </header>
  );
}
