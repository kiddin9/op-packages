import { useEffect, useState } from 'preact/hooks';
import { formatNumber, formatRelativeTime, formatTimestamp } from '../app/format';
import { SectionHeading } from '../components/SectionHeading';
import { NetworkNodesIcon } from '../components/Icons';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';
import type { ActivityEvent, ActivityHistory } from '../types/activity';
import type { ConnectedDevicesSummary } from '../types/devices';
import type { NetwatchDevice, NetwatchStatus } from '../types/netwatch';

interface Props {
  data: NetwatchStatus | null;
  error: string | null;
  loading: boolean;
  onRetry: () => void;
  onSetEnabled: (enabled: boolean) => Promise<void>;
  devices?: ConnectedDevicesSummary | null;
  activity?: ActivityHistory | null;
  demo?: boolean;
  onDemoAction?: () => void;
}

/** Learning state is a statistical observation, never a malware verdict. */
function observedState(device: NetwatchDevice, data: NetwatchStatus): { label: string; tone: string } {
  if (data.limited) return { label: '판단 보류', tone: 'bg-slate-100 text-slate-600' };
  switch (device.state) {
    case 'learning': return { label: '학습 중', tone: 'bg-slate-100 text-slate-600' };
    case 'normal': return { label: '정상 범위', tone: 'bg-emerald-50 text-emerald-800' };
    case 'watch': return { label: '변화 관찰', tone: 'bg-amber-50 text-amber-800' };
    case 'anomaly': return { label: '이상 증가 감지', tone: 'bg-amber-100 text-amber-900' };
    default: return { label: '관찰 중', tone: 'bg-slate-100 text-slate-600' };
  }
}

/** Match the collector's risk-first order; older firmware may send an unsorted top-12. */
function sortObservedDevices(devices: NetwatchDevice[]): NetwatchDevice[] {
  const rank = (state: NetwatchDevice['state']): number => {
    switch (state) {
      case 'anomaly': return 4;
      case 'watch': return 3;
      case 'learning': return 2;
      default: return 1;
    }
  };
  return [...devices].sort((a, b) => rank(b.state) - rank(a.state)
    || b.connections - a.connections || b.destinations - a.destinations || a.ip.localeCompare(b.ip)).slice(0, 12);
}

/** The bar compares a count with a learned statistical upper limit, not a security score. */
function TrafficMetric({ value, limit, name, limited = false }: { value: number; limit?: number | null; name: string; limited?: boolean }) {
  const threshold = typeof limit === 'number' && Number.isFinite(limit) && limit > 0 ? limit : null;
  const overLimit = threshold !== null && value > threshold;
  const percent = threshold !== null ? Math.min(100, Math.max(0, 100 * value / threshold)) : 0;
  return <div class="min-w-0" aria-label={`${name} ${formatNumber(value)}${threshold !== null ? `, 학습된 상한 ${formatNumber(threshold)}` : limited ? ', 일부 연결만 관찰되어 판단 보류' : ', 학습 기준 없음'}`}>
    <div class="flex flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
      <span class="font-bold tabular-nums text-slate-800">{formatNumber(value)}</span>
      {threshold !== null ? <span class="whitespace-nowrap text-xs text-slate-500">/ {formatNumber(threshold)} 상한</span> : <span class="text-xs text-slate-500">{limited ? '판단 보류' : '기준 미확보'}</span>}
    </div>
    {threshold !== null ? <div class="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-slate-100" aria-hidden="true">
      <div class={`h-full rounded-full ${overLimit ? 'bg-amber-500' : 'bg-teal-600'}`} style={{ width: `${percent}%` }} />
    </div> : null}
    {overLimit ? <span class="mt-1 block text-xs font-semibold text-amber-700">기준 초과</span> : null}
  </div>;
}

function recentWarnings(activity: ActivityHistory | null | undefined): ActivityEvent[] {
  return (activity?.events ?? [])
    .filter((event) => event.eventType === 'network_watch.anomaly.warning' && event.source === 'network_watch' && Number.isFinite(event.occurredAt) && event.occurredAt > 0)
    .sort((a, b) => b.occurredAt - a.occurredAt)
    .slice(0, 3);
}

function warningIp(event: ActivityEvent): string | null {
  const ip = event.metadata?.source_ip;
  // Event metadata is not trusted HTML. Render only a short, literal IPv4 label.
  return typeof ip === 'string' && /^\d{1,3}(?:\.\d{1,3}){3}$/.test(ip) ? ip : null;
}

export function NetworkWatchPage({ data, error, loading, onRetry, onSetEnabled, devices, activity, demo = false, onDemoAction }: Props) {
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const enabled = !!data?.enabled;
  const ready = enabled && data?.phase === 'ready';
  // Enabled and actively collecting are different states; never show '관찰 중' without a fresh ready status.
  const collectionStatus = saving
    ? '저장 중…'
    : !data
      ? loading ? '확인 중' : '상태 확인 불가'
      : !enabled
        ? '사용 안 함'
        : data.phase === 'ready'
          ? '사용 중 · 관찰 중'
          : data.phase === 'unavailable'
            ? '사용 중 · 수집 불가'
            : '사용 중 · 준비 중';
  const collectionTone = data && enabled && data.phase === 'ready'
    ? 'text-emerald-700'
    : data && enabled && data.phase === 'unavailable'
      ? 'text-amber-700'
      : 'text-slate-500';

  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => setNotice(null), 3500);
    return () => window.clearTimeout(timer);
  }, [notice]);

  const toggle = async () => {
    if (demo) { onDemoAction?.(); return; }
    if (saving || !data) return;
    setSaving(true);
    setSaveError(null);
    setNotice(null);
    try {
      await onSetEnabled(!enabled);
      setNotice(!enabled ? 'Network Watch를 켰습니다. 다음 관찰 주기부터 반영됩니다.' : 'Network Watch를 껐습니다.');
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : '설정을 저장하지 못했습니다.');
    } finally {
      setSaving(false);
    }
  };

  const hostnames = new Map<string, string>();
  // Reuse the connected-devices API response; do not start another lookup per row.
  for (const device of devices?.devices ?? []) {
    if (device.online && device.ipv4Address && device.hostname?.trim()) {
      hostnames.set(device.ipv4Address, device.hostname.trim());
    }
  }
  const warnings = recentWarnings(activity);
  const visibleDevices = sortObservedDevices(data?.devices ?? []);
  const learningCountsAvailable = data?.phase === 'ready' && !data.limited
    && typeof data.trainingReadyDevices === 'number' && Number.isInteger(data.trainingReadyDevices) && data.trainingReadyDevices >= 0
    && typeof data.trainingLearningDevices === 'number' && Number.isInteger(data.trainingLearningDevices) && data.trainingLearningDevices >= 0
    && data.trainingReadyDevices + data.trainingLearningDevices === data.totalDevices;
  // The API reports the longest-trained currently connected device, not a fleet-wide average.
  // A missing/invalid target must never produce a broken progress width.
  const trainingTarget = typeof data?.trainingTargetDays === 'number'
    && Number.isFinite(data.trainingTargetDays) && data.trainingTargetDays > 0
    ? data.trainingTargetDays : 14;
  const trainingDays = typeof data?.trainingDays === 'number' && Number.isFinite(data.trainingDays)
    ? Math.min(trainingTarget, Math.max(0, data.trainingDays)) : 0;
  const trainingPercent = Math.min(100, 100 * trainingDays / trainingTarget);
  const trainingStage = trainingDays >= trainingTarget
    ? '기준 안정화'
    : trainingDays >= 7 ? '기준 형성' : '학습 중';

  return (
    <div class="space-y-5">
      <SectionHeading
        eyebrow="Security"
        title="Network Watch"
        description={`연결된 기기의 외부 통신 변화를 ${data?.intervalSeconds ?? 60}초 간격으로 관찰합니다. 의심 징후는 참고 정보이며 악성 앱을 확정하거나 연결을 자동 차단하지 않습니다.`}
        action={
          <div class="flex items-center gap-3 rounded-xl border border-slate-100 bg-slate-50 px-3 py-2.5" aria-busy={saving}>
            <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-500">
              <NetworkNodesIcon class="size-5" />
            </span>
            <div class="text-right">
              <p class="m-0 text-[0.68rem] font-bold text-slate-400">관찰 수집</p>
              <p class={`mt-1 mb-0 whitespace-nowrap text-xs font-extrabold ${collectionTone}`} role="status">{collectionStatus}</p>
            </div>
            <button type="button" role="switch" aria-checked={enabled} aria-label="네트워크 이상 감지 사용"
              disabled={saving || !data} onClick={() => void toggle()}
              class={`ssh-switch-control relative inline-flex shrink-0 items-center rounded-full border-0 p-0 transition focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-not-allowed disabled:opacity-50 ${enabled ? 'bg-teal-600' : 'bg-slate-300'}`}>
              <span aria-hidden="true" class={`ssh-switch-thumb absolute top-1 shadow-sm transition-[left] ${enabled ? 'left-6' : 'left-1'}`} />
            </button>
          </div>
        }
      />
      {notice ? <p role="status" class="text-sm text-teal-700">{notice}</p> : null}
      {saveError ? <p role="alert" class="text-sm text-rose-700">{saveError}</p> : null}
      {loading && !data ? <LoadingPanel /> : null}
      {error && !data ? <ErrorPanel message={error} onRetry={onRetry} /> : null}
      {data && !enabled ? <p role="status" class="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">네트워크 관찰이 꺼져 있습니다. 기존 방화벽과 SafeShield 보호에는 영향이 없습니다.</p> : null}
      {enabled && data?.phase === 'preparing' ? <p role="status" class="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">첫 연결 관찰을 준비하고 있습니다. 잠시 후 자동으로 갱신됩니다.</p> : null}
      {enabled && data?.phase === 'unavailable' ? <div role="alert" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">연결 정보를 읽을 수 없습니다. OpenWrt의 conntrack 지원 여부를 확인해 주세요. 실제 감시가 수행 중인 것으로 표시하지 않습니다.</div> : null}
      {ready && data ? <>
        <section aria-label="Network Watch 관찰 요약과 학습" class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <div class="grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-3 xl:grid-cols-5 xl:gap-5">
            <div class="min-w-0 border-b border-slate-200 pb-3 sm:border-b-0 sm:pb-0 xl:border-r xl:pr-4">
              <p class="text-xs font-semibold text-slate-500">관찰된 IPv4 외부 연결</p>
              <p class="mt-2 text-2xl font-extrabold tabular-nums text-slate-900">{formatNumber(data.totalConnections)}</p>
            </div>
            <div class="min-w-0 border-b border-slate-200 pb-3 sm:border-b-0 sm:pb-0 xl:border-r xl:pr-4">
              <p class="text-xs font-semibold text-slate-500">외부 통신 기기</p>
              <p class="mt-2 text-2xl font-extrabold tabular-nums text-slate-900">{formatNumber(data.totalDevices)}<span class="ml-1 text-xs font-medium text-slate-500">대</span></p>
            </div>
            <div class="min-w-0 border-b border-slate-200 pb-3 sm:border-b-0 sm:pb-0 xl:border-r xl:pr-4">
              <p class="text-xs font-semibold text-slate-500">마지막 갱신</p>
              <p class="mt-2 text-xl font-extrabold text-slate-900">{data.sampledAt > 0 ? formatRelativeTime(data.sampledAt) : '—'}</p>
              {data.sampledAt > 0 ? <p class="mt-1 text-xs text-slate-500" title="브라우저 시간대 기준">{formatTimestamp(data.sampledAt)}</p> : null}
            </div>
            <div class="min-w-0 sm:col-span-3 xl:col-span-2">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <p class="text-xs font-semibold text-slate-500">정상 통신 패턴 학습</p>
                <span class="inline-flex rounded-full bg-slate-100 px-2.5 py-1 text-[0.68rem] font-bold text-slate-600">{trainingStage}</span>
              </div>
              <div class="mt-1 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                <p class="text-xl font-extrabold tabular-nums text-slate-900">{trainingDays}<span class="ml-1 text-xs font-semibold text-slate-500">/ {trainingTarget}일</span></p>
                <p class="text-xs text-slate-500">최장 학습 기기 기준</p>
              </div>
              <div class="mt-2 h-2 w-full overflow-hidden rounded-full bg-slate-100" role="progressbar"
                aria-label="정상 패턴 학습 진행" aria-valuemin={0} aria-valuemax={trainingTarget} aria-valuenow={trainingDays}>
                <div class="h-full rounded-full bg-teal-600" style={{ width: `${trainingPercent}%` }} />
              </div>
              <div class="mt-1 flex flex-wrap justify-between gap-x-3 text-[0.68rem] text-slate-500">
                <span>7일 · 기준 형성</span><span>{trainingTarget}일 · 안정화</span>
              </div>
              {learningCountsAvailable ? <p class="mt-2 text-xs text-slate-600">
                기준 확보 <strong class="font-extrabold text-teal-700">{data.trainingReadyDevices}대</strong>
                <span class="mx-2 text-slate-300" aria-hidden="true">·</span>
                학습 중 <strong class="font-extrabold text-slate-700">{data.trainingLearningDevices}대</strong>
                {typeof data.trainingStableDevices === 'number' && Number.isInteger(data.trainingStableDevices)
                  && data.trainingStableDevices >= 0 && typeof data.trainingReadyDevices === 'number'
                  && data.trainingStableDevices <= data.trainingReadyDevices
                  ? <span class="ml-2 text-slate-500">(14일 안정화 {data.trainingStableDevices}대)</span> : null}
                <span class="ml-1 text-slate-500">· 현재 관찰 기기 기준</span>
              </p> : null}
            </div>
          </div>
        </section>
        {data.limited ? <p role="status" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">연결 수가 관찰 한도를 초과하여 일부 연결만 집계했습니다. 이번 결과로 이상 여부를 판단하지 않습니다.</p> : null}
        {data.alert ? <p role="status" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">{data.alert.ip} 기기의 외부 연결이 학습된 기준을 3회 연속 초과했거나 초기 학습 중 매우 높게 관찰되었습니다. 정상적인 사용일 수도 있습니다.</p> : null}
        <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <h2 class="text-base font-extrabold text-slate-900">기기별 외부 연결 현황</h2>
          <p class="mt-1 text-xs text-slate-500">IPv4 외부 연결 스냅샷 · 이상 감지 우선 최대 12대 표시 · 통신 내용 분석 없음</p>
          {visibleDevices.length ? <>
            <div class="mt-4 hidden overflow-x-auto lg:block">
              <table class="w-full min-w-[44rem] text-left text-sm">
                <thead class="text-slate-500"><tr>
                  <th scope="col" class="pb-3 pr-4">기기</th>
                  <th scope="col" class="w-[22%] pb-3 pr-4">외부 연결 / 평소 기준</th>
                  <th scope="col" class="w-[22%] pb-3 pr-4">목적지 / 평소 기준</th>
                  <th scope="col" class="pb-3 text-right">관찰 상태</th>
                </tr></thead>
                <tbody>{visibleDevices.map(device => {
                  const state = observedState(device, data);
                  const hostname = hostnames.get(device.ip);
                  return <tr class="border-t border-slate-100 text-slate-700" key={device.ip}>
                    <td class="py-3 pr-4"><div class="font-semibold">{hostname || device.ip}</div>{hostname ? <div class="mt-0.5 text-xs text-slate-500">{device.ip}</div> : null}</td>
                    <td class="py-3 pr-4"><TrafficMetric name="외부 연결" value={device.connections} limit={data.limited ? null : (device.baselineConnections ?? null)} limited={data.limited} /></td>
                    <td class="py-3 pr-4"><TrafficMetric name="외부 목적지" value={device.destinations} limit={data.limited ? null : (device.baselineDestinations ?? null)} limited={data.limited} /></td>
                    <td class="py-3 text-right">
                      <span class={`inline-block whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-bold ${state.tone}`}>{state.label}</span>
                      {!data.limited ? <div class="mt-1 text-xs text-slate-500">학습 {device.trainingDays ?? 0}일</div> : null}
                    </td>
                  </tr>;
                })}</tbody>
              </table>
            </div>
            <div class="mt-4 grid gap-3 lg:hidden" aria-label="모바일 기기별 외부 연결 현황">
              {visibleDevices.map(device => {
                const state = observedState(device, data);
                const hostname = hostnames.get(device.ip);
                return <article key={device.ip} class="rounded-xl border border-slate-200 bg-slate-50 p-3 sm:p-4">
                  <div class="flex flex-wrap items-start justify-between gap-2">
                    <div class="min-w-0"><p class="break-all text-sm font-bold text-slate-800">{hostname || device.ip}</p>
                      {hostname ? <p class="mt-0.5 text-xs text-slate-500">{device.ip}</p> : null}
                      {!data.limited ? <p class="mt-1 text-xs text-slate-500">학습 {device.trainingDays ?? 0}일</p> : null}
                    </div>
                    <span class={`inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-bold ${state.tone}`}>{state.label}</span>
                  </div>
                  <div class="mt-3 grid grid-cols-2 gap-4 border-t border-slate-200 pt-3">
                    <div><p class="mb-1 text-xs font-semibold text-slate-500">외부 연결 / 기준</p><TrafficMetric name="외부 연결" value={device.connections} limit={data.limited ? null : (device.baselineConnections ?? null)} limited={data.limited} /></div>
                    <div><p class="mb-1 text-xs font-semibold text-slate-500">목적지 / 기준</p><TrafficMetric name="외부 목적지" value={device.destinations} limit={data.limited ? null : (device.baselineDestinations ?? null)} limited={data.limited} /></div>
                  </div>
                </article>;
              })}
            </div>
          </> : <p class="mt-4 text-sm text-slate-500">현재 확인된 외부 연결이 없습니다.</p>}
          <p class="mt-3 text-xs text-slate-500">표시된 기준은 최근 학습으로 계산한 통계적 상한이며 보안 안전 판정이 아닙니다. 기기 이름을 확인할 수 없으면 IP만 표시합니다.</p>
        </section>
        <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-base font-extrabold text-slate-900">최근 감지 이벤트</h2>
            <a href="#activity" class="text-xs font-bold text-teal-700 hover:underline">최근 활동 전체 보기</a>
          </div>
          <p class="mt-1 text-xs text-slate-500">현재 부팅 후 기록된 Network Watch 주의 이벤트 중 최신 3건</p>
          {warnings.length ? <ul class="mt-4 divide-y divide-slate-100">
            {warnings.map(event => <li key={event.eventId} class="flex flex-wrap items-start justify-between gap-2 py-3 first:pt-0 last:pb-0">
              <div class="min-w-0"><p class="text-sm font-bold text-slate-800">평소보다 통신 증가 감지</p>
                <p class="mt-1 text-xs text-slate-600">{warningIp(event) ?? '연결된 기기'} · 비정상 통신 확정 아님</p></div>
              <time class="text-xs text-slate-500" dateTime={new Date(event.occurredAt * 1000).toISOString()} title={formatTimestamp(event.occurredAt)}>{formatRelativeTime(event.occurredAt)}</time>
            </li>)}
          </ul> : <p class="mt-4 text-sm text-slate-500">최근 감지된 주의 이벤트가 없습니다.</p>}
        </section>
      </> : null}
      <section aria-label="Network Watch 관찰 범위" class="rounded-xl border border-slate-200 bg-slate-50 p-4">
        <h2 class="text-sm font-bold text-slate-700">관찰 범위 안내</h2>
        <ul class="mt-2 list-disc space-y-1 pl-5 text-xs leading-relaxed text-slate-600">
          <li>통신 내용은 읽지 않습니다. 최근 14일간의 기기 식별자(MAC 또는 IP) 및 연결 수·목적지 수 통계 구간은 재부팅 후 학습 유지용으로 공유기에 저장합니다. 원본 연결 기록은 저장하지 않습니다.</li>
          <li>IPv6, 짧게 종료된 연결 및 일부 하드웨어 가속 연결은 관찰에서 제외될 수 있습니다.</li>
          <li>주의 이벤트는 최근 활동에 기록되며, Cloud 활동 전송을 직접 켠 경우 내부 IP·연결 수 등의 요약 정보가 전송될 수 있습니다.</li>
        </ul>
      </section>
    </div>
  );
}
