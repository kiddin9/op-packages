import { useEffect, useMemo, useRef, useState } from 'preact/hooks';

import { AppsIcon, ReloadIcon } from '../components/Icons';
import { AppsStorageCard } from '../components/AppsStorageCard';
import { AppsArtwork } from '../components/AppsArtwork';
import { AppsCategoryIcon, appsCategoryOf } from '../components/AppsCategoryIcon';
import { safeDeveloperUrl } from '../utils/appsDeveloper';
import type { AppsCategory } from '../components/AppsCategoryIcon';
import { SectionHeading } from '../components/SectionHeading';
import type { AppsCatalog, AppsInstallStatus, AppsMetrics, VerifiedApp } from '../types/apps';
import { errorMessage } from '../utils/errors';
import { approvedAppPath } from '../utils/appsWebUi';
import { formatStorageBytes } from '../utils/appsStorage';
import { isFirstPartyPublisher } from '../utils/appsPublisher';
import { appsJobNoticeKey, readDismissedAppsJob, saveDismissedAppsJob } from '../utils/appsJobNotice';
import { appsHighlightFromHash } from '../utils/appsHighlight';
import { compareJarbisVersions, JARBIS_FULL_FEATURE_VERSION } from '../utils/jarbisCompatibility';

interface AppsPageProps {
  data: AppsCatalog | null;
  error: string | null;
  loading: boolean;
  refreshing: boolean;
  onRetry: () => void;
  installStatus: AppsInstallStatus | null;
  metrics: AppsMetrics | null;
  statusError: string | null;
  onRefreshStatus: () => void;
  onInstall: (id: string) => Promise<void>;
  onRepair: (id: string) => Promise<void>;
  onRemove: (id: string) => Promise<void>;
  onUpdate: (id: string) => Promise<void>;
  /** All public demo actions are local-only; no installs or real app launch. */
  demo?: boolean;
  onDemoAction?: () => void;
}

const OPERATION_MESSAGES: Readonly<Record<string, string>> = {
  E21: '서버에서 승인 정보를 확인하지 못했습니다. 인터넷 연결을 확인해 주세요.',
  E22: '이 펌웨어에서 승인되지 않은 앱입니다.',
  E24: '공유기의 패키지 아키텍처와 앱이 일치하지 않습니다.',
  E25: '배포 저장소가 승인 당시와 달라졌거나 접근할 수 없습니다. 관리자 확인 후 다시 시도해 주세요.',
  E26: '앱 설치에 필요한 메모리 또는 저장 공간이 부족합니다.',
  E27: '승인된 패키지 정보가 올바르지 않습니다.',
  E28: '이전에 설치한 앱의 구성이 현재 승인 정보와 다릅니다.',
  E29: '동일한 패키지가 이미 다른 방법으로 설치되어 있습니다.',
  E31: '앱 파일을 다운로드하지 못했습니다.',
  E32: '다운로드된 앱 파일이 올바르지 않습니다.',
  E33: '앱 파일의 검증 값이 일치하지 않습니다.',
  E34: '패키지 설치 사전 확인에 실패했습니다.',
  E35: '패키지를 설치하지 못했습니다.',
  E37: '공식 OpenWrt LuCI 저장소가 승인 당시와 다릅니다. 관리자에게 확인해 주세요.',
  E38: '기존 공유 라이브러리의 버전이 승인된 버전과 달라 설치할 수 없습니다.',
  E51: 'SmartSafeHub Apps에서 관리하는 앱만 업데이트할 수 있습니다.',
  E52: '현재 설치 버전과 승인된 업데이트가 일치하지 않습니다. 앱 구성과 업데이트 버전을 확인해 주세요.',
  E53: '다른 시스템 패키지 변경이 필요하여 앱 업데이트를 중단했습니다.',
  E54: '앱 업데이트에 실패했습니다. 일부 패키지가 변경되었을 수 있으니 관리자에게 확인해 주세요.',
  E55: '업데이트 후 설치 기록을 저장하지 못했습니다. 관리자에게 확인해 주세요.',
  E41: 'SmartSafeHub Apps에서 설치한 앱만 여기서 제거할 수 있습니다.',
  E42: '설치 관리 기록을 안전하게 확인할 수 없어 앱을 제거할 수 없습니다. 관리자에게 확인해 주세요.',
  E43: '다른 앱이 관리하는 패키지가 포함되어 있어 제거할 수 없습니다.',
  E44: '기존 시스템에 영향을 줄 수 있어 앱 제거가 차단됐습니다.',
  E45: '앱 제거에 실패했습니다.',
};

const TABS: readonly { id: AppsCategory; label: string }[] = [
  { id: 'all', label: '전체' },
  { id: 'network', label: '네트워크' },
  { id: 'security', label: '보안' },
  { id: 'smart_home', label: '스마트홈' },
  { id: 'entertainment', label: '엔터테인먼트' },
  { id: 'utilities', label: '도구' },
  { id: 'other', label: '기타' },
];

type AppAction = 'install' | 'repair' | 'update' | 'remove';

function OperationIndicator({ action }: { action: AppAction }) {
  const removing = action === 'remove';
  return (
    <span aria-live="polite" class={`inline-flex items-center gap-1.5 text-xs font-bold ${removing ? 'text-red-700' : 'text-teal-700'}`} role="status">
      <svg aria-hidden="true" class="size-4 animate-spin" fill="none" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="3" opacity="0.25" />
        <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
      </svg>
      {removing ? '제거 중…' : action === 'update' ? '업데이트 중…' : action === 'repair' ? '복원 중…' : '설치 중…'}
    </span>
  );
}

export function AppsPage({ data, error, loading, refreshing, onRetry, installStatus, metrics, statusError,
  onRefreshStatus, onInstall, onRepair, onUpdate, onRemove, demo = false, onDemoAction }: AppsPageProps) {
  const [highlightedAppId, setHighlightedAppId] = useState(() => demo ? null : appsHighlightFromHash(window.location.hash));
  const [category, setCategory] = useState<AppsCategory>('all');
  const [query, setQuery] = useState('');
  const highlightedCardRef = useRef<HTMLElement | null>(null);
  const scrolledHighlightRef = useRef<string | null>(null);
  const [pending, setPending] = useState<{ appId: string; action: AppAction } | null>(null);
  const [removeTarget, setRemoveTarget] = useState<VerifiedApp | null>(null);
  const cancelRemoveRef = useRef<HTMLButtonElement>(null);
  const removeTriggerRef = useRef<HTMLButtonElement | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [dismissedJob, setDismissedJob] = useState<string | null>(readDismissedAppsJob);
  // The optional highlight is only a visual guide; never filter or implicitly
  // install apps. Support the legacy #apps/jarbis link for old entry points.
  // The Apps route can remain mounted while only its hash changes.
  useEffect(() => {
    if (demo) return;
    const syncHighlight = () => {
      const highlighted = appsHighlightFromHash(window.location.hash);
      scrolledHighlightRef.current = null;
      setHighlightedAppId(highlighted);
      setCategory('all');
      setQuery('');
    };
    window.addEventListener('hashchange', syncHighlight);
    return () => window.removeEventListener('hashchange', syncHighlight);
  }, [demo]);
  // Keep the last successful catalog while a refresh fails. A separate status
  // request may describe a different catalog generation, so a missing ID
  // alone is NOT proof that an app has been discontinued.
  const currentData = data;
  const apps = currentData?.apps ?? [];
  const orphans = currentData && !error && !loading && !refreshing && !statusError
    ? Object.entries(installStatus?.installed ?? {}).filter(([id, state]) =>
      state.retired === true && state.managed && !apps.some((app) => app.id === id))
    : [];
  const guidedJarbis = apps.find(app => app.id === 'jarbis');
  const guidedState = installStatus?.installed?.jarbis;
  const guidedInstalledOutdated = guidedState?.installedVersion && compareJarbisVersions(guidedState.installedVersion, JARBIS_FULL_FEATURE_VERSION) === -1;
  const approvedComparison = guidedJarbis ? compareJarbisVersions(guidedJarbis.version, JARBIS_FULL_FEATURE_VERSION) : null;
  const guidedApprovedCompatible = approvedComparison !== null && approvedComparison >= 0;
  const restore = installStatus?.restore;
  const job = installStatus?.job;
  const running = job?.phase === 'starting' || job?.phase === 'running';
  const restoring = restore?.phase === 'starting' || restore?.phase === 'running';
  const jobKey = appsJobNoticeKey(job);
  const dismissJob = (key: string) => {
    setDismissedJob(key);
    saveDismissedAppsJob(key);
  };
  const showJob = job && job.phase !== 'idle' && jobKey !== dismissedJob;
  useEffect(() => {
    if (job?.phase !== 'success' || !showJob) return;
    const timeout = window.setTimeout(() => dismissJob(jobKey), 7000);
    return () => window.clearTimeout(timeout);
  }, [jobKey, job?.phase, showJob]);
  const jobAction: AppAction | null = job?.action === 'install' || job?.action === 'update' || job?.action === 'remove' ? job.action : null;
  const filtered = useMemo(() => apps.filter((app) =>
    (category === 'all' || appsCategoryOf(app.category) === category) &&
    `${app.id} ${app.name} ${app.summary}`.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()),
  ), [apps, category, query]);

  // Wait for the approved catalog to render before scrolling. A catalog
  // arriving asynchronously must still receive its first highlight, without
  // repeated jumps on every status poll or background refresh.
  useEffect(() => {
    if (!highlightedAppId || !filtered.some(app => app.id === highlightedAppId)) return;
    if (scrolledHighlightRef.current === highlightedAppId) return;
    const card = highlightedCardRef.current;
    if (!card) return;
    scrolledHighlightRef.current = highlightedAppId;
    const reducedMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;
    card.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth', block: 'center' });
  }, [highlightedAppId, filtered]);

  useEffect(() => {
    if (!removeTarget) return;
    cancelRemoveRef.current?.focus();
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        setRemoveTarget(null);
        removeTriggerRef.current?.focus();
      }
    };
    window.addEventListener('keydown', handleEscape);
    return () => window.removeEventListener('keydown', handleEscape);
  }, [removeTarget]);

  const closeRemoveDialog = () => {
    setRemoveTarget(null);
    removeTriggerRef.current?.focus();
  };

  const openRemoveDialog = (app: VerifiedApp, trigger: HTMLButtonElement) => {
    if (!installStatus || statusError || pending !== null || running || restoring) return;
    removeTriggerRef.current = trigger;
    setRemoveTarget(app);
  };

  const requestOperation = async (app: VerifiedApp, action: AppAction) => {
    if (!installStatus || statusError || pending !== null || running || restoring) return;
    if (demo) {
      if (action === 'remove') closeRemoveDialog();
      onDemoAction?.();
      return;
    }
    if (action === 'update' && !window.confirm(`${app.name} 앱을 최신 승인 버전으로 업데이트하시겠습니까?\n\n업데이트 중 공유기를 재부팅하지 마세요.`)) return;
    if (action === 'install' && !window.confirm(`${app.name} 앱을 설치하시겠습니까?\n\n앱을 변경하는 동안 공유기를 재부팅하지 마세요.`)) return;
    if (action === 'repair' && !window.confirm(`${app.name} 앱의 누락된 패키지를 복원하시겠습니까?\n\n기존 설치 기록과 최신 승인 패키지를 검증합니다. 복원 중 공유기를 재부팅하지 마세요.`)) return;
    if (action === 'remove') closeRemoveDialog();
    setActionError(null);
    setPending({ appId: app.id, action });
    try {
      if (action === 'install') await onInstall(app.id);
      else if (action === 'repair') await onRepair(app.id);
      else if (action === 'update') await onUpdate(app.id);
      else await onRemove(app.id);
      onRefreshStatus();
    } catch (cause: unknown) {
      setActionError(errorMessage(cause, `${app.name} 앱 작업을 시작하지 못했습니다.`));
    } finally {
      setPending(null);
    }
  };

  return (
    <section class="min-w-0 space-y-6">
      {removeTarget ? (
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4"
          onClick={(event) => { if (event.target === event.currentTarget) closeRemoveDialog(); }}
          role="presentation"
        >
          <div
            aria-describedby="apps-remove-description"
            aria-labelledby="apps-remove-title"
            aria-modal="true"
            class="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-5 shadow-xl"
            onKeyDown={(event) => {
              if (event.key !== 'Tab') return;
              // Keep keyboard focus inside the confirmation dialog.
              if (event.shiftKey && event.target === cancelRemoveRef.current) {
                event.preventDefault();
                const confirmButton = event.currentTarget.querySelector<HTMLButtonElement>('[data-confirm-remove]');
                confirmButton?.focus();
              } else if (!event.shiftKey && event.target instanceof HTMLButtonElement && event.target.hasAttribute('data-confirm-remove')) {
                event.preventDefault();
                cancelRemoveRef.current?.focus();
              }
            }}
            role="dialog"
          >
            <h2 class="m-0 text-lg font-extrabold text-slate-950" id="apps-remove-title">앱 제거 확인</h2>
            <p class="mt-3 break-words text-sm text-slate-700" id="apps-remove-description">
              <strong>{removeTarget.name}</strong> 앱을 이 공유기에서 제거하시겠습니까?
            </p>
            <p class="mt-2 text-xs leading-5 text-slate-600">
              앱에서 제공하던 기능을 더 이상 사용할 수 없습니다. 제거하는 동안 공유기를 재부팅하지 마세요.
            </p>
            <p class="mt-2 text-xs leading-5 text-slate-600">
              이전에 직접 설치한 패키지는 Apps가 제거하지 않습니다. 다른 앱이나 공유기 기능에
              필요한 패키지가 영향을 받는다면 안전을 위해 제거가 중단될 수 있습니다.
            </p>
            <div class="mt-5 flex justify-end gap-2">
              <button
                class="min-h-10 rounded-lg border border-slate-200 bg-white px-4 text-sm font-bold text-slate-700 transition hover:bg-slate-50"
                onClick={closeRemoveDialog}
                ref={cancelRemoveRef}
                type="button"
              >취소</button>
              <button
                class="min-h-10 rounded-lg bg-red-700 px-4 text-sm font-bold text-white transition hover:bg-red-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-100 disabled:opacity-50"
                data-confirm-remove
                disabled={!installStatus || Boolean(statusError) || pending !== null || running || restoring}
                onClick={() => void requestOperation(removeTarget, 'remove')}
                type="button"
              >앱 제거</button>
            </div>
          </div>
        </div>
      ) : null}
      {highlightedAppId === 'jarbis' ? <section aria-label="Jarbis 설치 안내" class="ssh-apps-guide flex flex-col gap-2 rounded-2xl border border-teal-200 bg-white p-4 shadow-sm sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0 flex-1">
          <p class="m-0 text-xs font-extrabold tracking-widest text-teal-700">스마트홈 시작하기 · 1단계</p>
          <h2 class="mt-1 mb-1 text-base font-black text-slate-950">Jarbis 설치 및 확인</h2>
        {!data || loading || !installStatus || installStatus.ready === false ?
          <p role="status" class="m-0 text-sm text-slate-600">승인된 Jarbis와 공유기 설치 상태를 확인하고 있습니다.</p>
          : !guidedJarbis ? <p class="m-0 text-sm text-slate-600">현재 펌웨어에 승인된 Jarbis가 없습니다. 목록을 새로고침하거나 지원 여부를 확인해 주세요.</p>
          : running || restoring ? <p role="status" class="m-0 text-sm text-slate-600">앱 작업을 진행 중입니다. 완료되면 설치 버전과 기능 지원 여부를 확인해 주세요.</p>
          : guidedState?.installed && !running && !restoring ? <>
            <p role="status" class="m-0 text-sm text-slate-600">{guidedInstalledOutdated
              ? guidedApprovedCompatible
                ? guidedState.updateAvailable
                  ? `현재 설치된 Jarbis(${guidedState.installedVersion})는 일부 스마트홈 기능에 필요한 ${JARBIS_FULL_FEATURE_VERSION}보다 이전 버전입니다. 아래 Jarbis 카드에서 승인된 업데이트를 선택해 주세요.`
                  : `Jarbis 최소 버전은 ${JARBIS_FULL_FEATURE_VERSION}입니다. 승인된 버전(${guidedJarbis.version})이 있지만 업데이트 상태가 확인되지 않았습니다. 앱 목록을 새로고침해 주세요.`
                : `현재 승인된 Jarbis(${guidedJarbis.version})는 일부 스마트홈 기능의 최소 버전(${JARBIS_FULL_FEATURE_VERSION})보다 낮습니다. 해당 배포 채널의 업데이트를 기다려 주세요.`
              : 'Jarbis가 설치되어 있습니다. 기존 기기 기능을 사용하거나 스마트홈에서 추가 지원 여부를 확인할 수 있습니다.'}</p>
            <a class="ssh-apps-guide-return mt-2 inline-flex min-h-9 items-center rounded-lg bg-teal-700 px-3 py-2 text-xs font-bold text-white hover:bg-teal-800" href="#smarthome">스마트홈으로 돌아가기</a>
          </>
          : <p class="m-0 text-sm text-slate-600">아래 Jarbis 카드에서 <strong>{guidedState?.managed || guidedState?.partial ? '재설치 또는 설치 마무리' : '설치'}</strong>를 눌러 주세요. 설치는 직접 확인한 후에만 진행됩니다.</p>}
        </div>
        <p class="ssh-apps-guide-caption m-0 text-xs text-slate-500 sm:max-w-60">다른 검증 앱도 함께 둘러보실 수 있습니다.</p>
      </section> : null}
      <div class="min-w-0">
        <SectionHeading
          eyebrow="SmartSafeHub Apps"
          title="Apps"
          description="SmartSafeHub에서 직접 검증한 앱으로 공유기의 기능을 확장하세요."
        />
        <div class="grid min-w-0 gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(0,18.5rem)]">
          <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div class="flex min-w-0 items-center gap-3">
                <span class="grid size-12 shrink-0 place-items-center rounded-2xl bg-teal-50 text-teal-700">
                  <AppsIcon class="size-6" />
                </span>
                <div class="min-w-0">
                  <h3 class="m-0 text-base font-black text-slate-950">검증된 앱</h3>
                  <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">현재 펌웨어에서 확인된 앱만 표시합니다.</p>
                </div>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <span class="rounded-full border border-teal-200 bg-teal-50 px-3 py-1 text-xs font-bold text-teal-800">
                  {currentData ? `${apps.length}개` : '확인 전'}
                </span>
                {error && currentData ? (
                  <span class="rounded-full border border-amber-200 bg-amber-50 px-2 py-1 text-[11px] font-semibold text-amber-800" title={error} role="status">이전 목록</span>
                ) : null}
                <button
                  class="inline-flex min-h-10 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 text-xs font-bold text-slate-700 transition hover:border-teal-300 hover:text-teal-700 disabled:opacity-50"
                  disabled={loading || refreshing}
                  onClick={onRetry}
                  type="button"
                >
                  <ReloadIcon class={`size-4 ${refreshing ? 'animate-spin' : ''}`} />
                  {refreshing ? '확인 중' : '목록 새로고침'}
                </button>
              </div>
            </div>
            <p class="mt-3 mb-0 text-xs leading-5 text-slate-500">
              검증된 APK를 설치·업데이트·제거할 수 있습니다. 작업 중에는 다른 앱 작업을 시작할 수 없습니다.
            </p>
          </div>
          <AppsStorageCard storage={metrics?.storage} />
        </div>
      </div>

      {restore && (restore.phase === 'starting' || restore.phase === 'running' || restore.phase === 'failed') ? (
        <div aria-live="polite" class={`rounded-2xl border p-4 text-sm ${restore.phase === 'failed' ? 'border-amber-300 bg-amber-50 text-amber-900' : 'border-teal-200 bg-teal-50 text-teal-900'}`} role="status">
          <strong>{restore.phase === 'failed' ? 'Apps 자동 복원을 완료하지 못했습니다.' : '펌웨어 업데이트 후 Apps를 복원하는 중입니다.'}</strong>
          {restore.appId ? <span> · {restore.appId}</span> : null}
          {restore.phase === 'failed' ? <p class="mb-0 mt-1 text-xs">{OPERATION_MESSAGES[restore.code] ?? '승인·연결·설치 상태를 확인해 주세요.'} 필요한 경우 앱 카드에서 재설치 또는 설치 마무리를 진행할 수 있습니다.</p> : <p class="mb-0 mt-1 text-xs">검증된 패키지만 다시 설치합니다. 완료될 때까지 앱 설치·제거를 시작하지 마세요.</p>}
        </div>
      ) : null}
      {showJob && job ? (
        <div aria-live="polite" class={`rounded-2xl border p-4 text-sm ${job.phase === 'failed' ? 'border-rose-200 bg-rose-50 text-rose-800' : running && job.action === 'remove' ? 'border-red-200 bg-red-50 text-red-800' : 'border-teal-200 bg-teal-50 text-teal-900'}`} role="status">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              {running ? (job.action === 'remove' ? '앱 제거 중' : job.action === 'update' ? '앱 업데이트 중' : '앱 설치 중') : job.phase === 'success' ? '마지막 앱 작업 완료' : '마지막 앱 작업 실패'}
              {job.appId ? ` · ${job.appId}` : ''}
              {job.code && job.code !== 'NONE' ? ` · 오류 코드 ${job.code}` : ''}
              {job.phase === 'failed' && job.code && OPERATION_MESSAGES[job.code]
                ? <p class="mb-0 mt-1 text-xs">{OPERATION_MESSAGES[job.code]}</p> : null}
              {running ? <p class="mb-0 mt-1 text-xs">{job.action === 'remove' ? '앱 제거와 패키지 정리가 진행 중입니다.' : job.action === 'update' ? '승인된 버전으로 앱을 업데이트하고 있습니다.' : '설치 확인과 패키지 처리가 진행 중입니다.'} 화면을 닫아도 작업은 계속됩니다.</p> : null}
            </div>
            {!running ? <button aria-label="앱 작업 알림 닫기" class="shrink-0 rounded-lg px-2 py-1 text-xs font-bold hover:bg-black/5 focus-visible:outline-none focus-visible:ring-2" onClick={() => dismissJob(jobKey)} type="button">닫기 ×</button> : null}
          </div>
        </div>
      ) : null}
      {actionError ? <p class="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800" role="alert">{actionError}</p> : null}
      {statusError ? <div class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900" role="alert">설치 상태를 확인하지 못했습니다. 설치 및 제거 버튼이 비활성화됩니다. <button class="underline" onClick={onRefreshStatus} type="button">다시 확인</button></div> : null}
      {error && !currentData ? (
        <div class="rounded-2xl border border-rose-200 bg-rose-50 p-5" role="alert">
          <p class="m-0 text-sm font-bold text-rose-800">앱 목록을 불러오지 못했습니다.</p>
          <p class="mt-2 mb-0 text-sm text-rose-700">{error}</p>
          <button class="mt-3 rounded-lg border border-rose-300 px-3 py-2 text-xs font-bold text-rose-800" onClick={onRetry} type="button">다시 시도</button>
        </div>
      ) : null}
      {loading && !currentData ? (
        <div aria-live="polite" class="rounded-2xl border border-slate-200 bg-white p-8 text-center text-sm text-slate-500" role="status">검증된 앱 목록을 확인하는 중입니다.</div>
      ) : null}
      {currentData ? (
        <>
          {apps.length > 0 ? (
            <div class="space-y-4">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="flex flex-wrap items-center gap-2" role="group" aria-label="앱 카테고리">
                  {TABS.map((tab) => (
                    <button
                      class={`inline-flex min-h-10 items-center gap-1.5 rounded-xl border px-3 text-xs font-bold ${category === tab.id ? 'border-teal-400 bg-teal-50 text-teal-800' : 'border-slate-200 bg-white text-slate-600'}`}
                      key={tab.id}
                      onClick={() => setCategory(tab.id)}
                      type="button"
                    ><AppsCategoryIcon category={tab.id} class="size-4 shrink-0" />{tab.label}</button>
                  ))}
                </div>
                <input
                  aria-label="앱 검색"
                  class="min-h-10 w-full rounded-xl border border-slate-200 bg-white px-3 text-sm text-slate-900 outline-none focus:border-teal-500 sm:w-52"
                  onInput={(event) => setQuery(event.currentTarget.value)}
                  placeholder="앱 검색"
                  type="search"
                  value={query}
                />
              </div>
              <div class="grid min-w-0 gap-3 sm:grid-cols-2 xl:grid-cols-3">
                {filtered.map((app) => {
                  const isHighlighted = app.id === highlightedAppId;
                  const state = installStatus?.installed[app.id];
                  const installed = state?.installed ?? false;
                  const bytes = metrics?.installedSizes?.[app.id];
                  const sizeLabel = installed && typeof bytes === 'number' && Number.isSafeInteger(bytes) && bytes >= 0
                    ? formatStorageBytes(bytes) : null;
                  const managed = state?.managed ?? false;
                  // A new approved dependency may be missing while the existing app is
                  // still Apps-owned. Allow the reviewed update to complete it.
                  const updateAvailable = Boolean(managed && state?.updateAvailable);
                  const installedVersion = installed ? state?.installedVersion : null;
                  const showOfferedVersion = Boolean(installed && installedVersion && (updateAvailable || installedVersion !== app.version));
                  const activeAction = pending?.appId === app.id ? pending.action : running && job?.appId === app.id ? jobAction : null;
                  const disabled = !installStatus || Boolean(statusError) || pending !== null || running || restoring;
                  const removable = managed && (installed || Boolean(state?.partial));
                  const launchPath = installed && state?.webUiReady ? approvedAppPath(app.webUi) : null;
                  return (
                    <article
                      class={`flex min-w-0 flex-col rounded-2xl border border-slate-200 bg-white p-5 shadow-sm ${isHighlighted ? 'ssh-apps-highlight-card' : ''}`}
                      data-highlighted={isHighlighted ? 'true' : undefined}
                      key={app.id}
                      ref={isHighlighted ? highlightedCardRef : null}
                    >
                      <div class="flex min-w-0 items-start gap-3">
                        <AppsArtwork app={app} key={`${app.id}:${app.iconImageUrl ?? ''}`} />
                        <div class="min-w-0 flex-1">
                          <div class="flex min-w-0 flex-wrap items-start justify-between gap-x-3 gap-y-2">
                            <h3 class="m-0 min-w-0 flex-1 break-words text-sm font-black text-slate-950">{app.name}</h3>
                            {isHighlighted ? <span class="ssh-apps-highlight-label shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold">설치 안내</span> : null}
                            {installed && managed ? <span class="ssh-apps-installed-badge shrink-0 rounded-full border px-2 py-0.5 text-[11px] font-bold">✓ 설치됨</span> : null}
                          </div>
                          {app.developerName || safeDeveloperUrl(app.developerWebsiteUrl) ? (
                            <div class="mt-1 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs text-slate-500">
                              {app.developerName ? <span class="min-w-0 break-words">개발자 <strong class="font-semibold text-slate-700">{app.developerName}</strong></span> : null}
                              {safeDeveloperUrl(app.developerWebsiteUrl) ? <a class="font-semibold text-teal-700 underline-offset-2 hover:underline focus-visible:underline"
                                href={safeDeveloperUrl(app.developerWebsiteUrl)!} rel="noopener noreferrer" referrerPolicy="no-referrer"
                                target="_blank" aria-label={`${app.name} 개발자 홈페이지 (새 탭)`}>홈페이지 ↗</a> : null}
                            </div>
                          ) : null}
                          <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
                            <span class="text-xs text-slate-500" title={installed ? '공유기에 설치된 대표 APK 패키지 버전입니다.' : '현재 제공 중인 승인 버전입니다.'}>
                              {installed ? installedVersion ? `설치 v${installedVersion}` : '설치 버전 확인 불가' : `v${app.version}`}
                            </span>
                            {updateAvailable ? <span class="ssh-apps-update-badge rounded-full border px-2 py-0.5 text-[11px] font-bold">업데이트 가능</span> : null}
                          </div>
                          {managed && !updateAvailable && state?.updateBlocked ? (
                            <p class="mb-0 mt-1 text-xs text-amber-700">설치된 패키지의 상태가 승인된 업데이트 조건과 맞지 않습니다.</p>
                          ) : null}
                          {showOfferedVersion || sizeLabel !== null ? (
                            <p class="mb-0 mt-1 flex min-w-0 flex-wrap items-center gap-x-1.5 gap-y-0.5 text-[11px] text-slate-500">
                              {showOfferedVersion ? (
                                <span title="현재 서버가 승인한 앱 릴리스 버전입니다. 설치된 APK 패키지의 버전과 다를 수 있습니다.">제공 v{app.version}</span>
                              ) : null}
                              {showOfferedVersion && sizeLabel !== null ? <span aria-hidden="true">·</span> : null}
                              {sizeLabel !== null ? (
                                <span title="설치된 APK 패키지의 용량 합계입니다. 앱 데이터 및 캐시는 포함되지 않습니다.">설치 용량 약 {sizeLabel}</span>
                              ) : null}
                            </p>
                          ) : null}
                        </div>
                      </div>
                      <p class="mt-4 mb-4 min-h-10 break-words text-sm leading-5 text-slate-600">{app.summary}</p>
                      <div class="mt-auto flex flex-wrap items-center justify-between gap-2 border-t border-slate-100 pt-3">
                        {isFirstPartyPublisher(app.publisherType) ? (
                          <span class="ssh-apps-official-badge inline-flex items-center gap-1 rounded-lg border px-2 py-1 text-xs font-bold" title="SmartSafeHub가 직접 개발하고 제공하는 앱입니다.">
                            <span aria-hidden="true">✦</span> SmartSafeHub 공식
                          </span>
                        ) : (
                          <span class="text-xs font-bold text-slate-500">✓ 검증된 앱</span>
                        )}
                        {activeAction ? <OperationIndicator action={activeAction} /> : (
                          <span class="flex flex-wrap items-center gap-2">
                            {managed && state?.partial && !installed && !updateAvailable ? (
                              <button class="min-h-9 rounded-lg border border-teal-300 bg-white px-3 text-xs font-bold text-teal-800 hover:bg-teal-50 disabled:opacity-50" disabled={disabled} onClick={() => void requestOperation(app, 'repair')} type="button">설치 마무리</button>
                            ) : null}
                            {updateAvailable ? <button class="ssh-apps-update-button min-h-9 rounded-lg border px-3 text-xs font-bold transition disabled:opacity-50" disabled={disabled} onClick={() => void requestOperation(app, 'update')} type="button">업데이트</button> : null}
                            {launchPath ? (demo ? (launchPath === '#smarthome' ? (
                              <a aria-label="Jarbis 스마트홈 체험" class="inline-flex min-h-9 items-center rounded-lg border border-teal-700 bg-teal-700 px-3 text-xs font-bold text-white transition hover:bg-teal-800" href="#smarthome">스마트홈 체험</a>
                            ) : (
                              <button aria-label={`${app.name} 데모 실행 안내`} class="inline-flex min-h-9 items-center rounded-lg border border-teal-700 bg-teal-700 px-3 text-xs font-bold text-white transition hover:bg-teal-800" onClick={onDemoAction} type="button">열기 ↗</button>
                            )) : (
                              <a aria-label={`${app.name} ${app.id === 'jarbis' ? '스마트홈으로 이동' : '새 탭에서 열기'}`} class="inline-flex min-h-9 items-center rounded-lg border border-teal-700 bg-teal-700 px-3 text-xs font-bold text-white transition hover:bg-teal-800" href={launchPath} rel="noopener noreferrer" target={app.id === 'jarbis' ? '_self' : '_blank'}>{app.id === 'jarbis' ? '스마트홈 열기' : '열기 ↗'}</a>
                            )) : installed && app.webUi ? (
                              <span class="text-xs text-amber-700" title="이 앱의 웹 UI 패키지를 설치해야 열 수 있습니다.">웹 UI 미설치</span>
                            ) : null}
                            {installed && !managed ? <span class="text-xs text-slate-500" title="공유기 소프트웨어 메뉴 또는 SSH로 설치한 앱은 Apps에서 제거하지 않습니다.">기존에 설치됨</span>
                          : state?.partial && !managed ? <span class="text-xs text-amber-700">일부 패키지 설치됨</span>
                          : <button
                              class={`min-h-9 rounded-lg border bg-white px-3 text-xs font-bold transition focus-visible:outline-none focus-visible:ring-2 disabled:cursor-not-allowed disabled:opacity-50 ${removable ? 'border-red-300 text-red-700 hover:bg-red-50 focus-visible:ring-red-100' : 'border-teal-300 text-teal-800 hover:bg-teal-50 focus-visible:ring-teal-200'}`}
                              disabled={disabled || (Boolean(state?.partial) && !managed)}
                              onClick={(event) => removable ? openRemoveDialog(app, event.currentTarget) : void requestOperation(app, managed ? 'repair' : 'install')}
                              type="button"
                            >{removable ? '제거' : managed ? '재설치' : '설치'}</button>}
                          </span>
                        )}
                      </div>
                    </article>
                  );
                })}
              </div>
              {filtered.length === 0 ? <p class="rounded-xl bg-slate-100 p-5 text-center text-sm text-slate-600">검색 조건에 맞는 앱이 없습니다.</p> : null}
            </div>
          ) : (
            <div class="rounded-2xl border border-dashed border-slate-300 bg-white px-5 py-12 text-center">
              <AppsIcon class="mx-auto size-10 text-slate-400" />
              <h3 class="mt-4 mb-2 text-base font-black text-slate-900">아직 등록된 앱이 없습니다.</h3>
              <p class="m-0 text-sm leading-6 text-slate-500">현재 기기와 펌웨어에 대해 승인된 앱이 준비되면 이곳에서 확인할 수 있습니다.</p>
            </div>
          )}
          <p class="text-xs text-slate-400">기기 {currentData.deviceCode} · 펌웨어 {currentData.firmwareBuildId} · {currentData.channel} 채널</p>
        </>
      ) : null}
          {orphans.length > 0 ? (
            <div class="rounded-2xl border border-amber-200 bg-amber-50 p-5">
              <h3 class="m-0 text-sm font-black text-amber-900">제공이 중단된 앱</h3>
              <p class="mb-3 mt-1 text-xs text-amber-800">현재 승인 목록에서 제외되었지만 기기에 남아 있는 앱입니다. 설치는 불가능하며 제거할 수 있습니다.</p>
              <div class="space-y-2">
                {orphans.map(([id]) => {
                  const activeAction = pending?.appId === id ? pending.action : running && job?.appId === id ? jobAction : null;
                  return (
                    <div class="flex flex-wrap items-center justify-between gap-3" key={id}>
                      <span class="break-all text-sm text-amber-900">{id}</span>
                      {activeAction ? <OperationIndicator action={activeAction} /> : <button
                        class="min-h-9 rounded-lg border border-red-300 bg-white px-3 text-xs font-bold text-red-700 transition hover:bg-red-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-100 disabled:cursor-not-allowed disabled:opacity-50"
                        disabled={!installStatus || running || restoring || pending !== null || Boolean(statusError)}
                        onClick={(event) => openRemoveDialog({ id, name: id, summary: '', description: '', category: '', version: '' }, event.currentTarget)}
                        type="button"
                      >제거</button>}
                    </div>
                  );
                })}
              </div>
            </div>
          ) : null}
    </section>
  );
}
