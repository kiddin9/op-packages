import { SectionHeading } from '../components/SectionHeading';
import type { TargetedEvent, TargetedSubmitEvent } from 'preact';
import { memo } from 'preact/compat';
import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';

import { RelativeTimestamp } from '../components/RelativeTimestamp';

import {
  AlertIcon,
  CheckCircleIcon,
  ListIcon,
  PlusIcon,
  SearchIcon,
  ShieldIcon,
  TrashIcon,
} from '../components/Icons';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';
import type { SafeShieldRulesAction } from '../hooks/useSafeShieldRules';
import type { RecommendedRuleAssignment, RecommendedRulesStatus, SafeShieldRuleAction, SafeShieldRules } from '../types/rules';
import { filterRecommendedAssignments, filterRuleGroups, sameRecommendationContent } from '../utils/ruleLists';

// Stable fallbacks keep memoized rule cards from rebuilding while the first
// recommendation status request is still pending.
const EMPTY_RECOMMENDED_DOMAINS: string[] = [];
const EMPTY_RECOMMENDED_RULES: RecommendedRuleAssignment[] = [];

interface SafeShieldRulesPageProps {
  action: SafeShieldRulesAction | null;
  data: SafeShieldRules | null;
  error: string | null;
  feedback: string | null;
  loading: boolean;
  onAddRule: (
    action: SafeShieldRuleAction,
    domain: string,
    onPersisted?: () => void,
  ) => Promise<boolean>;
  onDeleteRule: (
    action: SafeShieldRuleAction,
    domain: string,
  ) => Promise<boolean>;
  onDismissFeedback: () => void;
  onRetry: () => void;
  // Injected only by the authenticated router app; the public demo has no RPC.
  onLoadRecommendedRulesStatus?: () => Promise<RecommendedRulesStatus>;
  onSyncRecommendedRules?: () => Promise<RecommendedRulesStatus>;
  onRevokeRecommendedRule?: (ruleId: number) => Promise<RecommendedRulesStatus>;
}

interface RuleListCardProps {
  action: SafeShieldRulesAction | null;
  kind: SafeShieldRuleAction;
  onAddRule: (
    action: SafeShieldRuleAction,
    domain: string,
    onPersisted?: () => void,
  ) => Promise<boolean>;
  onDeleteRule: (
    action: SafeShieldRuleAction,
    domain: string,
  ) => Promise<boolean>;
  rules: string[];
  recommendedDomainSet: ReadonlySet<string>;
  recommendedKnown: boolean;
  recommendedRules: RecommendedRuleAssignment[];
  onRequestRevoke?: (rule: RecommendedRuleAssignment) => void;
  revokeBusy: boolean;
}

function normalizeDomain(value: string): string {
  return value.trim().toLowerCase().replace(/\.+$/, '');
}

function isValidDomain(value: string): boolean {
  if (value.length === 0 || value.length > 253 || !value.includes('.')) {
    return false;
  }

  if (!/^[a-z0-9.-]+$/.test(value)) {
    return false;
  }

  return value.split('.').every(
    (label) =>
      label.length > 0 &&
      label.length <= 63 &&
      /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label),
  );
}

const RuleListCard = memo(function RuleListCard({
  action,
  kind,
  onAddRule,
  onDeleteRule,
  rules,
  recommendedDomainSet,
  recommendedKnown,
  recommendedRules,
  onRequestRevoke,
  revokeBusy,
}: RuleListCardProps) {
  const [input, setInput] = useState('');
  const [search, setSearch] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);
  const [manualExpanded, setManualExpanded] = useState(true);
  // Small groups start expanded; larger lists start collapsed. Once the user
  // changes it, keep their choice even when the next sync updates the list.
  const [recommendedExpanded, setRecommendedExpanded] = useState<boolean | null>(null);
  const isAllow = kind === 'allow';
  const busy = action !== null;
  const query = useMemo(() => search.trim().toLowerCase(), [search]);
  const searching = query.length > 0;
  // Filter and partition once per actual list/search/ownership change. Set
  // membership avoids a quadratic scan across the recommended domains.
  const { filteredRules, manualRules, managedRules } = useMemo(
    () => filterRuleGroups(rules, query, isAllow && recommendedKnown, recommendedDomainSet),
    [rules, query, isAllow, recommendedKnown, recommendedDomainSet],
  );
  const visibleRecommendedRules = useMemo(
    () => isAllow ? filterRecommendedAssignments(recommendedRules, query) : [],
    [isAllow, recommendedRules, query],
  );
  const showRecommended = searching || (recommendedExpanded ?? (recommendedRules.length || managedRules.length) <= 3);
  const showManual = searching || manualExpanded;

  async function handleSubmit(event: TargetedSubmitEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    const domain = normalizeDomain(input);
    if (!isValidDomain(domain)) {
      setValidationError('example.com 형식의 도메인을 입력해 주세요. URL, IP 주소, 와일드카드는 사용할 수 없습니다.');
      return;
    }
    setValidationError(null);
    await onAddRule(kind, domain, () => {
      // Clear when persisted, not after the slower DNS refresh finishes.
      setInput((current) => normalizeDomain(current) === domain ? '' : current);
    });
  }

  const theme = isAllow
    ? {
        badge: 'bg-emerald-100 text-emerald-800',
        button: 'border-emerald-700 bg-emerald-700 text-white hover:border-emerald-800 hover:bg-emerald-800 focus-visible:ring-emerald-100',
        icon: 'bg-emerald-50 text-emerald-700',
        label: '허용 목록',
        description: '직접 허용하거나 웹사이트 추천으로 추가된 도메인을 관리합니다.',
        empty: '등록된 허용 도메인이 없습니다.',
      }
    : {
        badge: 'bg-red-100 text-red-800',
        button: 'border-red-700 bg-red-700 text-white hover:border-red-800 hover:bg-red-800 focus-visible:ring-red-100',
        icon: 'bg-red-50 text-red-700',
        label: '차단 목록',
        description: 'SafeShield 기본 목록에 없더라도 직접 차단할 도메인을 등록합니다.',
        empty: '등록된 차단 도메인이 없습니다.',
      };

  function renderRule(domain: string) {
    // A manual entry that happens to match a cloud recommendation must
    // remain deletable. Only entries actually owned by the reconciler lock.
    const cloudManaged = isAllow && recommendedKnown && recommendedDomainSet.has(domain);
    const ruleOrigin = !isAllow || recommendedKnown
      ? (cloudManaged ? '추천 규칙' : '직접 추가')
      : null;
    const deleting = action?.operation === 'delete' && action.action === kind && action.domain === domain;
    return (
      <li class="flex min-w-0 items-center justify-between gap-3 px-3.5 py-3" key={domain}>
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-2">
          <code class="min-w-0 break-all font-mono text-sm font-semibold text-slate-800">{domain}</code>
        </div>
        {cloudManaged ? (
          <span class="shrink-0 rounded-full bg-teal-50 px-2.5 py-1 text-[11px] font-bold text-teal-800" title="추천 규칙의 적용과 해제는 웹사이트에서 관리합니다.">
            웹사이트 관리
          </span>
        ) : (
          <button
            aria-label={`${domain} ${theme.label}에서 삭제`}
            class="inline-flex size-9 shrink-0 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-500 transition hover:border-red-200 hover:bg-red-50 hover:text-red-700 focus:outline-none focus-visible:ring-4 focus-visible:ring-red-100 disabled:cursor-not-allowed disabled:opacity-50"
            disabled={busy || cloudManaged}
            onClick={() => void onDeleteRule(kind, domain)}
            title={ruleOrigin === '직접 추가' ? '직접 추가한 규칙 삭제' : '삭제'}
            type="button"
          >
            <TrashIcon class={`size-4 ${deleting ? 'animate-pulse' : ''}`} />
          </button>
        )}
      </li>
    );
  }

  return (
    <article class="min-w-0 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-900/5">
      <div class="border-b border-slate-200 p-4 sm:p-6">
        <div class="flex min-w-0 items-start gap-3">
          <span class={`grid size-11 shrink-0 place-items-center rounded-xl ${theme.icon}`}>
            {isAllow ? <CheckCircleIcon class="size-6" /> : <ShieldIcon class="size-6" />}
          </span>
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="m-0 text-xl font-extrabold tracking-tight text-slate-950">{theme.label}</h2>
              <span class={`rounded-full px-2.5 py-1 text-xs font-extrabold ${theme.badge}`}>{rules.length}</span>
            </div>
            <p class="mt-2 mb-0 text-sm leading-6 text-slate-600">{theme.description}</p>
          </div>
        </div>
        <form class="mt-5" onSubmit={handleSubmit}>
          <label class="block text-xs font-extrabold text-slate-600" for={`${kind}-domain`}>새 도메인</label>
          <div class="mt-2 flex flex-col gap-2 sm:flex-row">
            <input
              aria-describedby={validationError ? `${kind}-domain-error` : undefined}
              aria-invalid={validationError ? true : undefined}
              autocomplete="off"
              class="min-h-11 min-w-0 flex-1 rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold text-slate-950 shadow-inner outline-none transition placeholder:text-slate-400 focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100"
              disabled={busy}
              id={`${kind}-domain`}
              onInput={(event: TargetedEvent<HTMLInputElement, InputEvent>) => setInput(event.currentTarget.value)}
              placeholder="example.com"
              spellcheck={false}
              type="text"
              value={input}
            />
            <button
              class={`inline-flex min-h-11 w-full shrink-0 items-center justify-center gap-2 rounded-xl border px-4 py-2.5 text-sm font-extrabold transition focus:outline-none focus-visible:ring-4 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto ${theme.button}`}
              disabled={busy || input.trim().length === 0}
              type="submit"
            >
              <PlusIcon class="size-4" />
              {action?.operation === 'add' && action.action === kind ? '추가 중…' : '추가'}
            </button>
          </div>
          {validationError ? <p class="mt-2 mb-0 text-xs font-semibold leading-5 text-red-700" id={`${kind}-domain-error`}>{validationError}</p> : null}
        </form>
      </div>

      <div class="p-4 sm:p-6">
        <label class="relative block" for={`${kind}-search`}>
          <span class="sr-only">{theme.label} 검색</span>
          <span class="pointer-events-none absolute inset-y-0 left-0 flex w-11 items-center justify-center text-slate-400"><SearchIcon class="size-4" /></span>
          <input
            class="min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 py-2.5 pr-4 pl-11 text-sm font-semibold text-slate-950 shadow-inner outline-none transition placeholder:text-slate-400 focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100"
            id={`${kind}-search`}
            onInput={(event: TargetedEvent<HTMLInputElement, InputEvent>) => setSearch(event.currentTarget.value)}
            placeholder={`${theme.label} 검색`}
            type="search"
            value={search}
          />
        </label>

        {isAllow && recommendedKnown ? (
          <div class="mt-4 overflow-hidden rounded-xl border border-slate-200">
            <section aria-label="직접 추가한 허용 규칙">
              <button
                aria-controls="allow-manual-domains"
                aria-expanded={showManual}
                class="flex min-h-14 w-full items-center justify-between gap-3 ssh-rule-group-toggle bg-slate-50 px-4 py-3 text-left focus-visible:outline-2 focus-visible:outline-teal-500"
                onClick={() => setManualExpanded(!showManual)}
                type="button"
              >
                <span class="min-w-0 text-sm font-extrabold text-slate-800">직접 추가한 규칙 <span class="ml-1 rounded-full bg-white px-2 py-0.5 text-xs font-bold text-slate-600">{manualRules.length}{searching ? '개 검색됨' : '개'}</span></span>
                <span aria-hidden="true" class="shrink-0 text-sm font-bold text-slate-500">{showManual ? '접기 −' : '펼치기 +'}</span>
              </button>
              <div hidden={!showManual} id="allow-manual-domains">
                {manualRules.length ? (
                  <ul class="m-0 max-h-[20rem] list-none divide-y divide-slate-200 overflow-y-auto p-0">{manualRules.map(renderRule)}</ul>
                ) : (
                  <p class="m-0 px-4 py-5 text-sm text-slate-500">{searching ? '검색 결과가 없습니다.' : '직접 추가한 허용 도메인이 없습니다.'}</p>
                )}
              </div>
            </section>
            <section aria-label="웹사이트 추천 규칙" class="border-t border-slate-200">
              <button
                aria-controls="allow-recommended-domains"
                aria-expanded={showRecommended}
                class="flex min-h-14 w-full items-center justify-between gap-3 ssh-rule-group-toggle bg-slate-50 px-4 py-3 text-left focus-visible:outline-2 focus-visible:outline-teal-500"
                onClick={() => setRecommendedExpanded(!showRecommended)}
                type="button"
              >
                <span class="min-w-0 text-sm font-extrabold text-slate-800">추천 규칙 <span class="ml-1 rounded-full bg-white px-2 py-0.5 text-xs font-bold text-teal-800">{!searching && recommendedRules.length ? recommendedRules.length : managedRules.length}{searching ? '개 검색됨' : '개'}</span></span>
                <span aria-hidden="true" class="shrink-0 text-sm font-bold text-slate-500">{showRecommended ? '접기 −' : '펼치기 +'}</span>
              </button>
              <div hidden={!showRecommended} id="allow-recommended-domains">
                {visibleRecommendedRules.length ? (
                  <ul class="m-0 max-h-[22rem] list-none divide-y divide-slate-200 overflow-y-auto p-0">
                    {visibleRecommendedRules.map((rule) => (
                      <li class="flex min-w-0 flex-wrap items-center justify-between gap-3 px-3.5 py-3" key={rule.id}>
                        <div class="min-w-0 flex-1">
                          <strong class="block break-words text-sm text-slate-900">{rule.title}</strong>
                          <div class="mt-1 flex flex-wrap gap-1.5">
                            {rule.domains.map((domain) => <code class="break-all text-xs text-slate-600" key={domain}>{domain}</code>)}
                          </div>
                        </div>
                        {onRequestRevoke ? (
                          <button class="shrink-0 rounded-lg border border-red-200 px-3 py-2 text-xs font-bold text-red-700 hover:bg-red-50 disabled:opacity-50" disabled={revokeBusy || busy} onClick={() => onRequestRevoke(rule)} type="button">적용 해제</button>
                        ) : <span class="text-xs text-slate-500">웹사이트 관리</span>}
                      </li>
                    ))}
                  </ul>
                ) : managedRules.length ? (
                  <ul class="m-0 max-h-[20rem] list-none divide-y divide-slate-200 overflow-y-auto p-0">{managedRules.map(renderRule)}</ul>
                ) : (
                  <p class="m-0 px-4 py-5 text-sm text-slate-500">{searching ? '검색 결과가 없습니다.' : '추천으로 추가된 허용 도메인이 없습니다.'}</p>
                )}
                {!searching ? (
                  <p class="m-0 border-t border-slate-100 px-4 py-3 text-xs leading-5 text-slate-500">추천 규칙은 이 공유기에서 적용 해제할 수 있습니다. 새 규칙의 적용은 SmartSafeHub 웹사이트에서 관리해 주세요.</p>
                ) : null}
              </div>
            </section>
          </div>
        ) : (
          <div class="mt-4 max-h-[28rem] overflow-y-auto rounded-xl border border-slate-200">
            {filteredRules.length ? (
              <ul class="m-0 list-none divide-y divide-slate-200 p-0">{filteredRules.map(renderRule)}</ul>
            ) : (
              <div class="px-5 py-10 text-center">
                <ListIcon class="mx-auto size-8 text-slate-300" />
                <p class="mt-3 mb-0 text-sm font-bold text-slate-600">{searching ? '검색 결과가 없습니다.' : theme.empty}</p>
              </div>
            )}
          </div>
        )}
      </div>
    </article>
  );
});

export function SafeShieldRulesPage({
  action,
  data,
  error,
  feedback,
  loading,
  onAddRule,
  onDeleteRule,
  onDismissFeedback,
  onRetry,
  onLoadRecommendedRulesStatus,
  onSyncRecommendedRules,
  onRevokeRecommendedRule,
}: SafeShieldRulesPageProps) {
  const [recommendedStatus, setRecommendedStatus] = useState<RecommendedRulesStatus | null>(null);
  const [recommendedKnown, setRecommendedKnown] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<RecommendedRuleAssignment | null>(null);
  const [revokeBusy, setRevokeBusy] = useState(false);
  const [revokeConfirming, setRevokeConfirming] = useState(false);
  const [revokeConfirmationDelayed, setRevokeConfirmationDelayed] = useState(false);
  const pendingRevokeId = useRef<number | null>(null);
  const previousStatusSignature = useRef<string | null>(null);
  const lastConfirmedSignature = useRef<string | null>(null);
  const onRetryRef = useRef(onRetry);
  onRetryRef.current = onRetry;
  const [syncMessage, setSyncMessage] = useState<string | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);
  const recommendedDomains = recommendedStatus?.domains ?? EMPTY_RECOMMENDED_DOMAINS;
  const recommendedRules = recommendedStatus?.rules ?? EMPTY_RECOMMENDED_RULES;
  const recommendedDomainSet = useMemo(() => new Set(recommendedDomains), [recommendedDomains]);

  // A revoke can reach Hub even if rpcd times out while SafeShield is applying
  // the new rules. Only a confirmed local read can settle its final outcome.
  // The local SafeShield list also needs a refresh when a background poll
  // observes a new recommendation revision, without reloading the whole page.
  const acceptRecommendedStatus = useCallback((status: RecommendedRulesStatus): boolean => {
    setRecommendedStatus((previous) => {
      if (!previous) return status;
      // Poll responses are newly deserialized objects. Reuse unchanged list
      // references so both memoized cards skip work on progress-only updates.
      const { domains, rules } = sameRecommendationContent(previous, status);
      return { ...status, domains, rules };
    });
    setRecommendedKnown(true);
    // Progress/status/metadata changes must not re-read the whole SafeShield
    // rules list. After a completed reconcile, reload only once per actual
    // recommendation revision/ownership change. The first pending -> confirmed
    // transition also refreshes a list fetched while SafeShield was applying.
    const signature = JSON.stringify([status.revision, status.domains]);
    let reloaded = false;
    if (status.syncStatus === 'confirmed' && lastConfirmedSignature.current !== signature) {
      if (previousStatusSignature.current !== null) {
        onRetryRef.current();
        reloaded = true;
      }
      lastConfirmedSignature.current = signature;
    }
    previousStatusSignature.current = signature;

    // A worker failure is not a successful revoke. Keep the previous rule
    // visible and let the user retry instead of waiting indefinitely.
    if (pendingRevokeId.current !== null && status.revokeOperation?.phase === 'failed' &&
        status.revokeOperation.argument === String(pendingRevokeId.current)) {
      pendingRevokeId.current = null;
      setRevokeConfirming(false);
      setRevokeConfirmationDelayed(false);
      setSyncError('추천 규칙 적용 해제를 완료하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.');
    }
    if (status.syncStatus === 'confirmed' && pendingRevokeId.current === null &&
        status.revokeOperation?.phase !== 'failed') {
      setSyncError(null);
    }
    if (
      pendingRevokeId.current !== null &&
      status.syncStatus === 'confirmed' &&
      !status.rules.some((rule) => rule.id === pendingRevokeId.current)
    ) {
      pendingRevokeId.current = null;
      setRevokeConfirming(false);
      setRevokeConfirmationDelayed(false);
      setSyncError(null);
      setSyncMessage('추천 규칙 적용 해제를 확인했습니다.');
    }
    return reloaded;
  }, []);

  useEffect(() => {
    if (!onLoadRecommendedRulesStatus) return;
    const loadStatus = onLoadRecommendedRulesStatus;
    let mounted = true;
    let inFlight = false;
    // Read only the local rpcd state. Hub's 30-second poll runs separately.
    function updateStatus(): void {
      if (inFlight || syncing || revokeBusy) return;
      inFlight = true;
      void loadStatus()
        .then((status) => {
          if (!mounted) return;
          acceptRecommendedStatus(status);
        })
        .catch(() => {
          // Retain the last known result on a transient local RPC failure.
          // Do not mislabel a known recommendation as a manually added rule.
        })
        .finally(() => { inFlight = false; });
    }
    updateStatus();
    const timer = window.setInterval(updateStatus, 15_000);
    const onFocus = () => updateStatus();
    const onVisible = () => { if (!document.hidden) updateStatus(); };
    window.addEventListener('focus', onFocus);
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      mounted = false;
      window.clearInterval(timer);
      window.removeEventListener('focus', onFocus);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [onLoadRecommendedRulesStatus, syncing, revokeBusy, acceptRecommendedStatus]);

  // An RPC timeout cannot prove whether Hub accepted the removal. After a
  // minute, explain the delay but continue watching for eventual confirmation.
  useEffect(() => {
    if (!revokeConfirming) return;
    const timer = window.setTimeout(() => setRevokeConfirmationDelayed(true), 60_000);
    return () => window.clearTimeout(timer);
  }, [revokeConfirming]);

  async function handleSyncRecommended(): Promise<void> {
    if (!onSyncRecommendedRules || syncing || revokeBusy) return;
    setSyncing(true);
    setSyncError(null);
    setSyncMessage(null);
    try {
      const status = await onSyncRecommendedRules();
      const reloaded = acceptRecommendedStatus(status);
      setSyncMessage(status.syncStatus === 'confirmed'
        ? '서버에서 규칙을 가져와 SafeShield 허용 목록을 확인했습니다.'
        : '추천 규칙 상태를 확인 중입니다. 진행 결과는 자동으로 갱신됩니다.');
      // The user explicitly requested synchronization, so allow one manual
      // refresh after confirmation but never queue a duplicate full RPC.
      if (status.syncStatus === 'confirmed' && !reloaded) onRetry();
    } catch {
      setSyncError('추천 규칙을 동기화하지 못했습니다. 서버 연결 및 기기 등록 상태를 확인해 주세요.');
    } finally {
      setSyncing(false);
    }
  }

  async function handleRevokeRecommended(): Promise<void> {
    if (!revokeTarget || revokeBusy || !onRevokeRecommendedRule) return;
    const ruleId = revokeTarget.id;
    pendingRevokeId.current = ruleId;
    setRevokeBusy(true);
    setRevokeConfirming(true);
    setRevokeConfirmationDelayed(false);
    setSyncError(null);
    setSyncMessage(null);
    try {
      const status = await onRevokeRecommendedRule(ruleId);
      acceptRecommendedStatus(status);
      setRevokeTarget(null);
      if (pendingRevokeId.current !== null) {
        setSyncMessage('적용 해제 요청을 처리했습니다. 공유기의 허용 목록을 확인하고 있습니다.');
      }
      // A pending revoke is not yet a changed SafeShield rule list. The
      // confirmed status poll refreshes once the local apply is complete.
    } catch {
      // Hub may have removed the assignment before the local SafeShield apply
      // timed out. Keep checking instead of permanently displaying a failure.
      setRevokeTarget(null);
      setSyncError('적용 해제 결과를 아직 확인하지 못했습니다. 공유기의 상태를 자동으로 다시 확인합니다.');
      try {
        const status = await onLoadRecommendedRulesStatus?.();
        if (status) acceptRecommendedStatus(status);
      } catch { /* The 15-second local poll will retry. */ }
    } finally {
      setRevokeBusy(false);
    }
  }

  // Only one live notice is rendered. In-progress SafeShield refreshes are
  // not failures; the 15-second local poll advances the visible stage.
  const syncStage = recommendedStatus?.syncStage;
  const syncPending = recommendedStatus?.syncStatus === 'pending';
  const syncDelayed = recommendedStatus?.syncStatus === 'delayed';
  const syncFailed = recommendedStatus?.syncStatus === 'failed';
  const stageLabel = syncStage === 'server_sync' ? '서버 동기화 중'
    : syncStage === 'safeshield_refreshing' ? 'SafeShield 갱신 중'
    : syncStage === 'applying' ? '추천 규칙 적용 중'
    : syncStage === 'verifying' ? '허용 목록 확인 중'
    : syncDelayed ? '재확인 지연' : syncFailed ? '동기화 실패' :
      syncPending ? '동기화 대기' : '허용 목록 확인';
  const stageDescription = syncStage === 'safeshield_refreshing' && syncPending
    ? 'SafeShield가 보호 목록을 갱신하고 있습니다. 갱신이 끝나면 추천 규칙을 자동으로 다시 확인합니다.'
    : syncStage === 'applying' && syncPending
      ? '추천 규칙을 SafeShield 허용 목록에 반영하고 있습니다.'
      : syncStage === 'verifying' && syncPending
        ? 'SafeShield 허용 목록에서 추천 규칙 반영 결과를 확인하고 있습니다.'
        : syncStage === 'server_sync' && syncPending
          ? 'SmartSafeHub 서버에서 최신 추천 규칙을 확인하고 있습니다.'
          : syncDelayed
            ? '서버 응답이 지연되고 있습니다. 이미 확인한 허용 규칙은 유지되며 자동으로 다시 시도합니다.'
            : syncFailed
              ? recommendedStatus?.syncReason === 'auth_rejected'
                ? 'SmartSafeHub 기기 인증이 거부되었습니다. 공유기 계정 연결 상태를 확인해 주세요.'
                : recommendedStatus?.syncReason === 'api_rejected'
                  ? '서버가 추천 규칙 요청을 거부했습니다. Hub API 배포 상태를 확인해 주세요.'
                  : recommendedStatus?.syncReason === 'invalid_response'
                ? '서버 응답을 확인할 수 없습니다. 규칙은 유지되며 다음 동기화에서 다시 확인합니다.'
                : '추천 규칙 반영을 완료하지 못했습니다. 다음 자동 동기화에서 다시 시도합니다.'
              : syncPending ? '추천 규칙의 적용 결과를 기다리고 있습니다.' : null;
  const waitingForRevoke = revokeConfirming && pendingRevokeId.current !== null;
  const currentNotice = waitingForRevoke
    ? { tone: 'amber', label: revokeConfirmationDelayed ? '적용 해제 처리 지연' : '적용 해제 확인 중',
        description: revokeConfirmationDelayed
          ? '적용 해제 확인이 지연되고 있습니다. SafeShield 갱신 중이라면 완료 후 자동으로 재확인합니다.'
          : stageDescription ?? '적용 해제 상태를 확인하고 있습니다. 확인되면 목록과 상태가 자동 갱신됩니다.' }
    : syncPending || syncDelayed || syncFailed
      ? { tone: syncFailed ? 'red' : 'amber', label: stageLabel, description: stageDescription ?? '' }
      : syncError ? { tone: 'red', label: '상태 확인 필요', description: syncError }
        : recommendedStatus?.syncWarning
          ? { tone: 'amber', label: '서버 재확인 지연', description: '이미 확인한 허용 규칙은 유지되며 자동으로 다시 시도합니다.' }
          : syncMessage ? { tone: 'green', label: '허용 목록 확인', description: syncMessage } : null;

  if (loading && !data) {
    return <LoadingPanel />;
  }

  if (error && !data) {
    return <ErrorPanel message={error} onRetry={onRetry} />;
  }

  if (!data) {
    return <ErrorPanel message="사용자 규칙 응답이 비어 있습니다." onRetry={onRetry} />;
  }

  return (
    <>
      {revokeTarget ? (
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4" role="presentation" onClick={() => { if (!revokeBusy) setRevokeTarget(null); }}>
          <section aria-labelledby="recommended-revoke-title" aria-modal="true" class="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-5 shadow-xl" onClick={(event) => event.stopPropagation()} role="dialog">
            <h2 class="m-0 text-lg font-extrabold text-slate-950" id="recommended-revoke-title">추천 규칙 적용 해제</h2>
            <p class="mt-3 text-sm text-slate-700"><strong>{revokeTarget.title}</strong> 규칙을 이 공유기에서 해제할까요?</p>
            <p class="mt-2 text-xs leading-5 text-slate-600">포함된 도메인 {revokeTarget.domains.length}개를 다시 확인합니다. 직접 추가한 허용 규칙과 다른 추천 규칙에 필요한 도메인은 유지됩니다.</p>
            <div class="mt-5 flex justify-end gap-2">
              <button class="rounded-lg border border-slate-200 px-4 py-2 text-sm font-bold text-slate-700 disabled:cursor-wait disabled:opacity-50" disabled={revokeBusy} onClick={() => setRevokeTarget(null)} type="button">취소</button>
              <button
                class="inline-flex min-w-24 items-center justify-center gap-2 rounded-lg bg-red-700 px-4 py-2 text-sm font-bold text-white transition hover:bg-red-800 disabled:cursor-progress disabled:bg-red-700 disabled:opacity-80"
                aria-busy={revokeBusy}
                disabled={revokeBusy}
                onClick={() => void handleRevokeRecommended()}
                type="button"
              >
                {revokeBusy ? <svg class="size-4 animate-spin" aria-hidden="true" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="3" opacity="0.25"/><path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg> : null}
                <span role="status">{revokeBusy ? '해제 중…' : '적용 해제'}</span>
              </button>
            </div>
          </section>
        </div>
      ) : null}
      <SectionHeading eyebrow="Local overrides" title="사용자 도메인 규칙" description="허용 목록은 오탐을 해제하고, 차단 목록은 원하는 도메인을 SafeShield 보호 목록에 추가합니다." />
      <section aria-label="규칙 개수 요약" class="min-w-0">
        <dl class="m-0 grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div class="min-w-0 rounded-2xl border border-slate-200 bg-white px-5 py-4 shadow-sm shadow-slate-900/5">
            <dt class="text-sm font-extrabold text-emerald-700">허용 도메인</dt>
            <dd class="mt-2 mb-0 ml-0 text-2xl font-black tracking-tight text-slate-950">{data.counts.allow}<span class="ml-1 text-sm font-bold text-slate-500">개</span></dd>
            <p class="mt-1 mb-0 text-xs text-slate-500">차단하지 않도록 등록한 도메인</p>
          </div>
          <div class="min-w-0 rounded-2xl border border-slate-200 bg-white px-5 py-4 shadow-sm shadow-slate-900/5">
            <dt class="text-sm font-extrabold text-red-700">차단 도메인</dt>
            <dd class="mt-2 mb-0 ml-0 text-2xl font-black tracking-tight text-slate-950">{data.counts.block}<span class="ml-1 text-sm font-bold text-slate-500">개</span></dd>
            <p class="mt-1 mb-0 text-xs text-slate-500">추가로 차단하도록 등록한 도메인</p>
          </div>
          <div class="min-w-0 rounded-2xl border border-slate-200 bg-white px-5 py-4 shadow-sm shadow-slate-900/5">
            <dt class="text-sm font-extrabold text-slate-600">전체 등록 규칙</dt>
            <dd class="mt-2 mb-0 ml-0 text-2xl font-black tracking-tight text-slate-950">{data.counts.total}<span class="ml-1 text-sm font-bold text-slate-500">개</span></dd>
            <p class="mt-1 mb-0 text-xs text-slate-500">허용 및 차단 규칙의 합계</p>
          </div>
        </dl>
      </section>

      <div class="mt-7">
        <SectionHeading eyebrow="Recommendations" title="추천 사용자 규칙" description="웹사이트에서 선택한 권장 허용 규칙의 동기화 상태를 확인하고 관리합니다." />
      </div>
      <section class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5" aria-label="추천 사용자 규칙">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <span class="grid size-8 place-items-center rounded-lg bg-teal-50 text-teal-700"><CheckCircleIcon class="size-4" /></span>
              <h3 class="m-0 text-base font-extrabold text-slate-950">동기화 상태</h3>
              {onLoadRecommendedRulesStatus ? (
                <span aria-live="polite" class={`rounded-full px-2.5 py-1 text-xs font-bold ${recommendedStatus?.syncStatus === 'confirmed' ? 'bg-emerald-100 text-emerald-800' : recommendedStatus?.syncStatus === 'failed' ? 'bg-red-100 text-red-800' : 'bg-amber-100 text-amber-800'}`}>
                  {recommendedStatus?.syncStatus === 'confirmed' ? '허용 목록 확인' : stageLabel}
                </span>
              ) : null}
            </div>
            <p class="mt-2 mb-0 text-sm leading-6 text-slate-600">웹사이트에서 선택한 허용 규칙을 약 30초마다 확인합니다. 적용 해제는 이 공유기에서도 할 수 있습니다.</p>
            <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs font-semibold text-slate-600">
              <span>추천으로 추가 <strong class="text-teal-800">{recommendedKnown ? recommendedDomains.length : '—'}개 도메인</strong></span>
              {recommendedStatus?.syncStatus === 'confirmed' ? (
                <span>허용 확인 <strong class="text-emerald-800">{recommendedStatus.confirmedDomains.length}개</strong></span>
              ) : null}
              {recommendedStatus?.lastCheckedAt ? (
                <span>{recommendedStatus.syncWarning ? '최근 재확인 시도' : '최근 확인'}: <RelativeTimestamp timestamp={recommendedStatus.lastCheckedAt} /></span>
              ) : null}
            </div>
          </div>
          <div class="flex w-full flex-wrap gap-2 sm:w-auto lg:shrink-0">
            {onSyncRecommendedRules ? (
              <button
                class="inline-flex min-h-10 flex-1 items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-extrabold text-slate-800 transition hover:bg-slate-50 disabled:cursor-wait disabled:opacity-60 sm:flex-none"
                disabled={syncing}
                onClick={() => void handleSyncRecommended()}
                type="button"
              >{syncing ? '동기화 중…' : '지금 동기화'}</button>
            ) : null}
            <a class="inline-flex min-h-10 flex-1 items-center justify-center rounded-xl border border-teal-700 bg-teal-700 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-teal-800 sm:flex-none" href="https://www.smartsafehub.com/dashboard/recommended-rules/" target="_blank" rel="noopener noreferrer">추천 규칙 보기 ↗</a>
          </div>
        </div>
        {currentNotice ? (
          <div aria-live="polite" class={`mt-3 flex items-start gap-2 rounded-xl px-3 py-2.5 text-sm ${currentNotice.tone === 'red' ? 'bg-red-50 text-red-800' : currentNotice.tone === 'green' ? 'bg-emerald-50 text-emerald-800' : 'bg-amber-50 text-amber-800'}`} role="status">
            <span aria-hidden="true" class={`mt-1 size-2 shrink-0 rounded-full ${currentNotice.tone === 'red' ? 'bg-red-500' : currentNotice.tone === 'green' ? 'bg-emerald-500' : 'bg-amber-500'}`} />
            <div class="min-w-0"><strong>{currentNotice.label}</strong><p class="mt-1 mb-0 leading-5">{currentNotice.description}</p></div>
          </div>
        ) : null}
        <p class="mt-3 mb-0 text-xs leading-5 text-slate-500">추천 규칙 동기화는 SafeShield 차단 목록 갱신과 별개입니다. 허용 목록 확인은 DNS 처리나 서비스 재생 성공을 보장하지 않습니다.</p>
      </section>

      {!data.applyLocalOverrides ? (
        <section class="mt-4 flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-4" role="alert">
          <AlertIcon class="mt-0.5 size-5 shrink-0 text-amber-700" />
          <div>
            <p class="m-0 text-sm font-extrabold text-amber-950">로컬 규칙 적용이 꺼져 있습니다</p>
            <p class="mt-1 mb-0 text-sm leading-6 text-amber-800">
              규칙은 저장되지만 SafeShield의 apply_local_overrides 설정을 켜기 전까지 DNS에 반영되지 않습니다.
            </p>
          </div>
        </section>
      ) : null}

      {!data.safeshieldEnabled ? (
        <section class="mt-4 flex items-start gap-3 rounded-2xl border border-slate-200 bg-slate-100 p-4" role="status">
          <ShieldIcon class="mt-0.5 size-5 shrink-0 text-slate-600" />
          <div>
            <p class="m-0 text-sm font-extrabold text-slate-950">SafeShield가 비활성화되어 있습니다</p>
            <p class="mt-1 mb-0 text-sm leading-6 text-slate-600">
              규칙을 미리 저장할 수 있으며, SafeShield를 켜고 차단 목록을 갱신하면 적용됩니다.
            </p>
          </div>
        </section>
      ) : null}

      {feedback ? (
        <section aria-live="polite" class="mt-4 flex flex-col items-start gap-3 rounded-2xl border border-teal-200 bg-teal-50 sm:flex-row sm:justify-between p-4">
          <div class="flex min-w-0 items-start gap-3">
            <CheckCircleIcon class="mt-0.5 size-5 shrink-0 text-teal-700" />
            <p class="m-0 text-sm font-semibold leading-6 text-teal-950">{feedback}</p>
          </div>
          <button
            class="shrink-0 rounded-lg border-0 bg-transparent px-2 py-1 text-xs font-extrabold text-teal-800 hover:bg-teal-100"
            onClick={onDismissFeedback}
            type="button"
          >
            닫기
          </button>
        </section>
      ) : null}

      {error && data ? (
        <section aria-live="assertive" class="mt-4 flex items-start gap-3 rounded-2xl border border-red-200 bg-red-50 p-4">
          <AlertIcon class="mt-0.5 size-5 shrink-0 text-red-700" />
          <p class="m-0 text-sm font-semibold leading-6 text-red-900">{error}</p>
        </section>
      ) : null}

      <section class="mt-5 grid gap-5 xl:grid-cols-2">
        <RuleListCard
          action={action}
          kind="allow"
          onAddRule={onAddRule}
          onDeleteRule={onDeleteRule}
          rules={data.allow}
          recommendedDomainSet={recommendedDomainSet}
          recommendedKnown={recommendedKnown}
          recommendedRules={recommendedRules}
          {...(onRevokeRecommendedRule ? { onRequestRevoke: setRevokeTarget } : {})}
          revokeBusy={revokeBusy}
        />
        <RuleListCard
          action={action}
          kind="block"
          onAddRule={onAddRule}
          onDeleteRule={onDeleteRule}
          rules={data.block}
          recommendedDomainSet={recommendedDomainSet}
          recommendedKnown={recommendedKnown}
          recommendedRules={recommendedRules}
          revokeBusy={revokeBusy}
        />
      </section>
    </>
  );
}
