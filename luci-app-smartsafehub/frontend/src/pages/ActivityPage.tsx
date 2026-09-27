import { formatNumber, formatRelativeTime } from '../app/format';
import { ActivityLoadState, ActivityTimeline } from '../components/ActivityTimeline';
import type { ActivityCloudSync, ActivityHistory } from '../types/activity';

function cloudStatus(cloud: ActivityCloudSync): {
  label: string;
  description: string;
  tone: string;
} {
  if (!cloud.enabled) {
    if (cloud.eligible === false) {
      return {
        label: 'Pro / Ultimate 전용',
        description: '로컬 최근 활동은 계속 사용할 수 있으며, 유료 멤버십에서 Cloud 저장을 선택적으로 켤 수 있습니다.',
        tone: 'bg-slate-100 text-slate-600 ring-slate-200',
      };
    }
    return {
      label: 'Cloud 전송 꺼짐',
      description: '활동 기록은 이 공유기에만 저장됩니다. Cloud에는 새로운 활동을 전송하지 않습니다.',
      tone: 'bg-slate-100 text-slate-700 ring-slate-200',
    };
  }
  if (cloud.eligible === false || cloud.phase === 'ineligible') {
    return {
      label: 'Pro / Ultimate 전용',
      description: '유료 멤버십이 활성화되면 이후 발생하는 활동을 Cloud에 자동으로 동기화합니다.',
      tone: 'bg-slate-100 text-slate-600 ring-slate-200',
    };
  }
  if (cloud.phase === 'error') {
    return {
      label: '동기화 확인 필요',
      description: '최근 Cloud 전송을 완료하지 못했습니다. 로컬 활동 기록은 계속 보관됩니다.',
      tone: 'bg-amber-50 text-amber-800 ring-amber-200',
    };
  }
  if (cloud.phase === 'syncing') {
    return {
      label: '동기화 중',
      description: '새 활동을 SmartSafeHub Cloud에 전송하고 있습니다.',
      tone: 'bg-teal-50 text-teal-800 ring-teal-200',
    };
  }
  if (cloud.eligible === true) {
    return {
      label: '자동 동기화',
      description: '새 활동이 생기면 SmartSafeHub Cloud에 자동으로 안전하게 전송합니다.',
      tone: 'bg-emerald-50 text-emerald-800 ring-emerald-200',
    };
  }
  return {
    label: '확인 중',
    description: 'Cloud 활동 기록 사용 가능 여부를 확인하고 있습니다.',
    tone: 'bg-slate-100 text-slate-600 ring-slate-200',
  };
}

function CloudActivitySyncCard({
  actionError,
  actionMessage,
  cloud,
  onDismissFeedback,
  onSetEnabled,
  saving,
}: {
  actionError: string | null;
  actionMessage: string | null;
  cloud: ActivityCloudSync;
  onDismissFeedback: () => void;
  onSetEnabled: (enabled: boolean) => void;
  saving: boolean;
}) {
  const status = cloudStatus(cloud);
  const plan = cloud.plan?.toUpperCase() ?? null;
  const canEnable = cloud.eligible === true;
  const canToggle = cloud.enabled || canEnable;

  return (
    <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-teal-700">
            Cloud history
          </p>
          <h2 class="mt-2 mb-0 text-base font-black text-slate-950">Cloud 활동 기록</h2>
          <p class="mt-2 mb-0 max-w-3xl text-sm leading-6 text-slate-500">{status.description}</p>
        </div>
        <div class="flex shrink-0 items-center gap-3">
          <span class={`rounded-full px-3 py-1.5 text-xs font-extrabold ring-1 ring-inset ${status.tone}`}>
            {saving ? '설정 중' : status.label}
          </span>
          <button
            aria-checked={cloud.enabled}
            aria-label="Cloud 활동 기록 전송 사용"
            class={`ssh-switch-control relative inline-flex shrink-0 rounded-full border transition focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-not-allowed disabled:opacity-50 ${
              cloud.enabled
                ? 'border-teal-600 bg-teal-600'
                : 'border-slate-300 bg-slate-200'
            }`}
            disabled={saving || !canToggle}
            onClick={() => onSetEnabled(!cloud.enabled)}
            role="switch"
            type="button"
          >
            <span
              aria-hidden="true"
              class={`ssh-switch-thumb absolute top-1 shadow-sm transition-[left] ${
                cloud.enabled ? 'left-6' : 'left-1'
              }`}
            />
          </button>
        </div>
      </div>

      {(actionError || actionMessage) && (
        <div
          class={`mt-4 flex min-w-0 items-start justify-between gap-3 rounded-xl border px-4 py-3 text-sm font-bold ${
            actionError
              ? 'border-rose-200 bg-rose-50 text-rose-800'
              : 'border-emerald-200 bg-emerald-50 text-emerald-800'
          }`}
          role={actionError ? 'alert' : 'status'}
        >
          <span class="min-w-0">{actionError || actionMessage}</span>
          <button
            class="shrink-0 rounded-lg px-2 py-1 text-xs font-extrabold hover:bg-black/5"
            onClick={onDismissFeedback}
            type="button"
          >
            닫기
          </button>
        </div>
      )}

      <dl class="mt-5 grid gap-3 sm:grid-cols-4">
        <div class="rounded-xl bg-slate-50 px-4 py-3 ring-1 ring-inset ring-slate-200">
          <dt class="text-xs font-bold text-slate-500">멤버십</dt>
          <dd class="mt-1 text-sm font-black text-slate-900">{plan ?? (cloud.eligible === false ? 'Free' : '확인 중')}</dd>
        </div>
        <div class="rounded-xl bg-slate-50 px-4 py-3 ring-1 ring-inset ring-slate-200">
          <dt class="text-xs font-bold text-slate-500">전송 대기</dt>
          <dd class="mt-1 text-sm font-black text-slate-900">{formatNumber(cloud.pendingEvents)}건</dd>
        </div>
        <div class="rounded-xl bg-slate-50 px-4 py-3 ring-1 ring-inset ring-slate-200">
          <dt class="text-xs font-bold text-slate-500">마지막 동기화</dt>
          <dd class="mt-1 text-sm font-black text-slate-900">
            {cloud.lastSuccessAt > 0 ? formatRelativeTime(cloud.lastSuccessAt) : '아직 없음'}
          </dd>
        </div>
        <div class="rounded-xl bg-slate-50 px-4 py-3 ring-1 ring-inset ring-slate-200">
          <dt class="text-xs font-bold text-slate-500">Cloud 보관</dt>
          <dd class="mt-1 text-sm font-black text-slate-900">
            {cloud.enabled && cloud.eligible === true && cloud.retentionDays > 0 ? `${cloud.retentionDays}일` : '—'}
          </dd>
        </div>
      </dl>

      {cloud.enabled && cloud.phase === 'error' && cloud.lastErrorCode ? (
        <p class="mt-3 mb-0 text-xs font-semibold text-amber-700">
          오류 코드: <code>{cloud.lastErrorCode}</code>
        </p>
      ) : null}
      <p class="mt-3 mb-0 text-xs leading-5 text-slate-500">
        Cloud 전송은 Pro 또는 Ultimate 멤버십에서 선택적으로 사용할 수 있습니다. 끄면 전송 대기 데이터와 임시 인증 정보를 삭제하며, 다시 켠 뒤 새로 발생한 활동부터 Cloud에 전송합니다. 로컬 최근 활동은 항상 유지됩니다.
      </p>
    </section>
  );
}

export function ActivityPage({
  actionError,
  actionMessage,
  data,
  error,
  loading,
  onDismissActionFeedback,
  onRetry,
  onSetCloudSync,
  savingCloudSync,
}: {
  actionError: string | null;
  actionMessage: string | null;
  data: ActivityHistory | null;
  error: string | null;
  loading: boolean;
  onDismissActionFeedback: () => void;
  onRetry: () => void;
  onSetCloudSync: (enabled: boolean) => void;
  savingCloudSync: boolean;
}) {
  return (
    <div class="min-w-0 space-y-5">
      <section
        aria-labelledby="activity-history-title"
        class="min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6"
      >
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-teal-700">
              Local history
            </p>
            <h2 class="mt-2 mb-0 text-xl font-black tracking-tight text-slate-950" id="activity-history-title">
              현재 부팅 이후의 최근 활동
            </h2>
            <p class="mt-2 mb-0 max-w-3xl text-sm leading-6 text-slate-500">
              인터넷, SafeShield, 업데이트, 라이선스와 주요 설정에서 실제 상태가 변경된 시점만 기록합니다.
            </p>
          </div>
          <span class="rounded-full bg-slate-100 px-3 py-1.5 text-xs font-extrabold text-slate-600 ring-1 ring-inset ring-slate-200">
            최대 {data?.maxEvents ?? 128}건
          </span>
        </div>

        <div class="mt-5">
          {loading || (error && !data) ? (
            <ActivityLoadState error={error} loading={loading} onRetry={onRetry} />
          ) : (
            <ActivityTimeline events={data?.events ?? []} />
          )}
        </div>
      </section>

      <CloudActivitySyncCard
        actionError={actionError}
        actionMessage={actionMessage}
        cloud={
          data?.cloud ?? {
            enabled: false,
            phase: 'preparing',
            eligible: null,
            plan: null,
            retentionDays: 0,
            pendingEvents: 0,
            lastAttemptAt: 0,
            lastSuccessAt: 0,
            lastUploadedCount: 0,
            lastErrorCode: null,
            nextSyncAt: 0,
          }
        }
        onDismissFeedback={onDismissActionFeedback}
        onSetEnabled={onSetCloudSync}
        saving={savingCloudSync}
      />

      <aside class="rounded-2xl border border-slate-200 bg-slate-50 px-5 py-4">
        <p class="m-0 text-sm font-extrabold text-slate-800">로컬 활동 기록 안내</p>
        <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
          이 기록은 공유기의 메모리 영역에만 보관되어 재부팅하면 초기화됩니다. 직접 설정을 변경한 작업은 성공 시점에 즉시 기록하고, 인터넷 및 장치 진단처럼 외부 상태를 확인해야 하는 항목은 실제 상태 변화가 관찰된 경우에만 추가합니다.
        </p>
      </aside>
    </div>
  );
}
