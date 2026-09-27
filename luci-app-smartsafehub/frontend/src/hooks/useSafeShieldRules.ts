import { useCallback, useState } from 'preact/hooks';

import {
  addSafeShieldRule,
  deleteSafeShieldRule,
  fetchSafeShieldRules,
  fetchSafeShieldStatus,
} from '../api/safeshield';
import type {
  SafeShieldRuleAction,
  SafeShieldRuleMutationResult,
} from '../types/rules';
import type { SafeShieldStatus } from '../types/safeshield';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

const LOCAL_APPLY_POLL_INTERVAL_MS = 500;
const LOCAL_APPLY_TIMEOUT_MS = 45_000;

export interface SafeShieldRulesAction {
  operation: 'add' | 'delete';
  action: SafeShieldRuleAction;
  domain: string;
}

interface SafeShieldRulesMutationState {
  action: SafeShieldRulesAction | null;
  error: string | null;
  feedback: string | null;
}

type LocalApplyOutcome =
  | { kind: 'success'; status: SafeShieldStatus }
  | { kind: 'failure'; status: SafeShieldStatus }
  | { kind: 'disabled'; status: SafeShieldStatus }
  | { kind: 'timeout'; status: SafeShieldStatus | null };

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function ruleLabel(action: SafeShieldRuleAction): string {
  return action === 'allow' ? '허용' : '차단';
}

function savedOnlyMessage(
  operation: 'add' | 'delete',
  result: SafeShieldRuleMutationResult,
): string {
  if (!result.changed) {
    return operation === 'add'
      ? result.action === 'allow'
        ? '이미 허용 목록에 있는 도메인입니다.'
        : '이미 차단 목록에 있는 도메인입니다.'
      : '이미 삭제된 규칙입니다.';
  }

  const label = ruleLabel(result.action);
  const verb = operation === 'add' ? '저장' : '삭제';

  if (!result.rules.safeshieldEnabled) {
    return `${result.domain} ${label} 규칙을 ${verb}했습니다. SafeShield를 켜면 다음 갱신에서 적용됩니다.`;
  }

  if (!result.rules.applyLocalOverrides) {
    return `${result.domain} ${label} 규칙을 ${verb}했습니다. 로컬 규칙 적용 설정이 꺼져 있어 아직 DNS에는 반영되지 않습니다.`;
  }

  return `${result.domain} ${label} 규칙을 ${verb}했습니다.`;
}

function applyingMessage(
  operation: 'add' | 'delete',
  result: SafeShieldRuleMutationResult,
): string {
  const verb = operation === 'add' ? '추가' : '삭제';
  return `${result.domain} ${ruleLabel(result.action)} 규칙 ${verb}를 저장했습니다. 로컬 규칙을 DNS에 적용하고 있습니다…`;
}

function appliedMessage(
  operation: 'add' | 'delete',
  result: SafeShieldRuleMutationResult,
): string {
  const verb = operation === 'add' ? '추가' : '삭제';
  return `${result.domain} ${ruleLabel(result.action)} 규칙 ${verb}와 DNS 적용이 완료되었습니다.`;
}

async function waitForLocalApply(
  baseline: SafeShieldStatus,
): Promise<LocalApplyOutcome> {
  const deadline = Date.now() + LOCAL_APPLY_TIMEOUT_MS;
  let latest: SafeShieldStatus | null = null;

  while (Date.now() < deadline) {
    latest = await fetchSafeShieldStatus();

    if (!latest.enabled) {
      return { kind: 'disabled', status: latest };
    }

    if (
      latest.timestamps.lastLocalApply >
      baseline.timestamps.lastLocalApply
    ) {
      return { kind: 'success', status: latest };
    }

    if (
      latest.timestamps.lastLocalApplyFailure >
      baseline.timestamps.lastLocalApplyFailure
    ) {
      return { kind: 'failure', status: latest };
    }

    await sleep(LOCAL_APPLY_POLL_INTERVAL_MS);
  }

  return { kind: 'timeout', status: latest };
}

export function useSafeShieldRules(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: '사용자 규칙을 불러오지 못했습니다.',
    loader: fetchSafeShieldRules,
  });
  const [mutation, setMutation] = useState<SafeShieldRulesMutationState>({
    action: null,
    error: null,
    feedback: null,
  });

  const mutate = useCallback(
    async (
      operation: 'add' | 'delete',
      action: SafeShieldRuleAction,
      domain: string,
    ): Promise<boolean> => {
      setMutation({
        action: { operation, action, domain },
        error: null,
        feedback: null,
      });

      try {
        // Capture the engine's local-apply generation before persisting the
        // mutation. SafeShield owns serialization, debounce, merge and dnsmasq
        // verification; the UI only waits for the authoritative apply stamp.
        const baseline = await fetchSafeShieldStatus();
        const result =
          operation === 'add'
            ? await addSafeShieldRule(action, domain, true)
            : await deleteSafeShieldRule(action, domain, true);

        resource.replaceData(result.rules);

        const shouldApply =
          result.changed &&
          result.rules.safeshieldEnabled &&
          result.rules.applyLocalOverrides;

        if (!shouldApply) {
          setMutation({
            action: null,
            error: null,
            feedback: savedOnlyMessage(operation, result),
          });
          return true;
        }

        if (!result.refresh.accepted) {
          setMutation({
            action: null,
            error: `규칙은 저장되었지만 로컬 DNS 적용 요청을 시작하지 못했습니다${result.refresh.reason ? ` (${result.refresh.reason})` : ''}.`,
            feedback: null,
          });
          return true;
        }

        setMutation({
          action: null,
          error: null,
          feedback: applyingMessage(operation, result),
        });

        const outcome = await waitForLocalApply(baseline);

        if (outcome.kind === 'success') {
          setMutation({
            action: null,
            error: null,
            feedback: appliedMessage(operation, result),
          });
          return true;
        }

        if (outcome.kind === 'disabled') {
          setMutation({
            action: null,
            error: null,
            feedback: '규칙은 저장되었지만 SafeShield가 꺼져 있어 DNS 적용을 대기하고 있습니다.',
          });
          return true;
        }

        if (outcome.kind === 'failure') {
          setMutation({
            action: null,
            error: '규칙은 저장되었지만 로컬 DNS 적용이 실패했습니다. SafeShield 상태를 확인해 주세요.',
            feedback: null,
          });
          return true;
        }

        setMutation({
          action: null,
          error: '규칙은 저장되었지만 제한 시간 안에 로컬 DNS 적용 완료를 확인하지 못했습니다.',
          feedback: null,
        });
        return true;
      } catch (error) {
        setMutation({
          action: null,
          error: errorMessage(error, '사용자 규칙을 변경하지 못했습니다.'),
          feedback: null,
        });
        return false;
      }
    },
    [resource.replaceData],
  );

  const addRule = useCallback(
    (action: SafeShieldRuleAction, domain: string) =>
      mutate('add', action, domain),
    [mutate],
  );

  const deleteRule = useCallback(
    (action: SafeShieldRuleAction, domain: string) =>
      mutate('delete', action, domain),
    [mutate],
  );

  const refresh = useCallback(async () => {
    setMutation((current) => ({ ...current, error: null }));
    await resource.refresh();
  }, [resource.refresh]);

  const dismissFeedback = useCallback(() => {
    setMutation((current) => ({ ...current, feedback: null }));
  }, []);

  return {
    ...resource,
    ...mutation,
    error: mutation.error ?? resource.error,
    addRule,
    deleteRule,
    dismissFeedback,
    refresh,
  };
}
