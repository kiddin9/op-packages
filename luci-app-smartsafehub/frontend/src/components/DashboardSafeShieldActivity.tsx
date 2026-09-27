import type { ComponentChildren } from 'preact';
import { formatNumber, formatTimestamp } from '../app/format';
import type {
  SafeShieldStatistics,
  SafeShieldStatisticsBucket,
} from '../types/safeshield';
import { SafeShieldBlockedBarChart } from './SafeShieldBlockedBarChart';

interface DashboardSafeShieldActivityProps {
  data: SafeShieldStatistics | null;
  error: string | null;
  loading: boolean;
  refreshing: boolean;
}

const HOUR_SECONDS = 3_600;
const DISPLAY_HOURS = 24;

function blockRate(queries: number, blocked: number): string {
  if (queries <= 0) {
    return '0.0%';
  }

  return `${((blocked / queries) * 100).toFixed(1)}%`;
}

function latestHour(data: SafeShieldStatistics): number {
  const lastBucket = data.hourly[data.hourly.length - 1];

  if (lastBucket?.bucketStart) {
    return lastBucket.bucketStart;
  }

  const timestamp =
    data.updatedAt > 0 ? data.updatedAt : Math.floor(Date.now() / 1_000);
  return Math.floor(timestamp / HOUR_SECONDS) * HOUR_SECONDS;
}

function recentBuckets(data: SafeShieldStatistics): SafeShieldStatisticsBucket[] {
  const byStart = new Map(data.hourly.map((bucket) => [bucket.bucketStart, bucket]));
  const end = latestHour(data);
  const start = end - (DISPLAY_HOURS - 1) * HOUR_SECONDS;

  return Array.from({ length: DISPLAY_HOURS }, (_, index) => {
    const bucketStart = start + index * HOUR_SECONDS;

    return (
      byStart.get(bucketStart) ?? {
        bucketStart,
        queries: 0,
        blocked: 0,
      }
    );
  });
}

function EmptyActivity({ children }: { children: string }) {
  return (
    <div class="mt-5 flex min-h-52 items-center justify-center rounded-xl border border-slate-200 bg-slate-50 px-5 text-center">
      <p class="m-0 max-w-lg text-sm font-semibold leading-6 text-slate-500">{children}</p>
    </div>
  );
}

export function DashboardSafeShieldActivity({
  data,
  error,
  loading,
  refreshing,
}: DashboardSafeShieldActivityProps) {
  let content: ComponentChildren;

  if (loading && !data) {
    content = <EmptyActivity>SafeShield 보호 활동을 불러오는 중입니다.</EmptyActivity>;
  } else if (error && !data) {
    content = (
      <EmptyActivity>
        SafeShield 보호 활동을 불러오지 못했습니다. SafeShield 페이지에서 상태를 확인해 주세요.
      </EmptyActivity>
    );
  } else if (!data || !data.available) {
    content = (
      <EmptyActivity>
        현재 SafeShield에서 차단 통계를 제공하지 않습니다. 통계 기능을 확인해 주세요.
      </EmptyActivity>
    );
  } else if (!data.enabled) {
    content = (
      <EmptyActivity>
        통계 수집이 꺼져 있습니다. SafeShield 페이지에서 통계를 켜면 최근 24시간 활동이 표시됩니다.
      </EmptyActivity>
    );
  } else {
    const buckets = recentBuckets(data);
    const totals = buckets.reduce(
      (result, bucket) => ({
        queries: result.queries + bucket.queries,
        blocked: result.blocked + bucket.blocked,
      }),
      { queries: 0, blocked: 0 },
    );

    content = (
      <>
        <dl class="mt-5 grid gap-3 sm:grid-cols-3">
          <div class="rounded-xl bg-slate-50 px-4 py-3">
            <dt class="text-[0.68rem] font-black uppercase tracking-[0.12em] text-slate-400">
              DNS 요청
            </dt>
            <dd class="mt-1 mb-0 ml-0 text-lg font-black text-slate-950">
              {formatNumber(totals.queries)}
            </dd>
          </div>
          <div class="rounded-xl bg-slate-50 px-4 py-3">
            <dt class="text-[0.68rem] font-black uppercase tracking-[0.12em] text-slate-400">
              차단
            </dt>
            <dd class="mt-1 mb-0 ml-0 text-lg font-black text-teal-700">
              {formatNumber(totals.blocked)}
            </dd>
          </div>
          <div class="rounded-xl bg-slate-50 px-4 py-3">
            <dt class="text-[0.68rem] font-black uppercase tracking-[0.12em] text-slate-400">
              차단율
            </dt>
            <dd class="mt-1 mb-0 ml-0 text-lg font-black text-slate-950">
              {blockRate(totals.queries, totals.blocked)}
            </dd>
          </div>
        </dl>

        <SafeShieldBlockedBarChart buckets={buckets} />
      </>
    );
  }

  return (
    <article class="min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
            SafeShield activity
          </p>
          <h3 class="mt-2 mb-0 text-xl font-black text-slate-950">
            최근 24시간 보호 활동
          </h3>
        </div>
        <div class="text-right">
          <a class="text-xs font-extrabold text-teal-700 no-underline hover:text-teal-800" href="#safeshield">
            상세 통계 →
          </a>
          {data?.updatedAt ? (
            <p class="mt-1 mb-0 text-[0.68rem] font-semibold text-slate-400">
              {refreshing ? '갱신 중…' : `집계 ${formatTimestamp(data.updatedAt)}`}
            </p>
          ) : null}
        </div>
      </div>
      {content}
      {error && data ? (
        <p class="mt-3 mb-0 text-xs font-bold text-amber-700">
          최근 통계 갱신에 실패해 마지막 정상 데이터를 표시하고 있습니다.
        </p>
      ) : null}
    </article>
  );
}
