import type { ComponentChildren } from 'preact';

import { formatNumber, formatTimestamp } from '../app/format';
import type { ActivityEvent, ActivityEventSeverity } from '../types/activity';
import {
  AlertIcon,
  CheckCircleIcon,
  ClockIcon,
  ReloadIcon,
} from './Icons';

interface ActivityPresentation {
  title: string;
  description: string | null;
}

function metadataString(event: ActivityEvent, key: string): string | null {
  const value = event.metadata[key];
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

function metadataNumber(event: ActivityEvent, key: string): number | null {
  const value = event.metadata[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function metadataBoolean(event: ActivityEvent, key: string): boolean | null {
  const value = event.metadata[key];
  return typeof value === 'boolean' ? value : null;
}

function failureDescription(event: ActivityEvent, message: string): string {
  const errorCode = metadataString(event, 'error_code');
  return errorCode ? `${message} (오류 코드: ${errorCode})` : message;
}

function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  if (seconds < 60) {
    return `${seconds}초`;
  }

  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return remainingSeconds > 0 ? `${minutes}분 ${remainingSeconds}초` : `${minutes}분`;
  }

  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return remainingMinutes > 0 ? `${hours}시간 ${remainingMinutes}분` : `${hours}시간`;
}

function versionTransition(event: ActivityEvent): string | null {
  const fromVersion = metadataString(event, 'from_version');
  const toVersion = metadataString(event, 'to_version');

  if (fromVersion && toVersion) {
    return `${fromVersion} → ${toVersion}`;
  }
  if (toVersion) {
    return `${toVersion} 버전이 적용되었습니다.`;
  }
  return null;
}

function licensePlan(value: string | null): string | null {
  if (!value) {
    return null;
  }

  return value.toUpperCase();
}

export function activityPresentation(event: ActivityEvent): ActivityPresentation {
  switch (event.eventType) {
    case 'system.booted':
      return {
        title: '공유기 부팅 감지',
        description: '공유기가 켜지거나 재시작된 것을 확인했습니다.',
      };

    case 'network.internet.disconnected':
      return {
        title: '인터넷 연결 끊김 감지',
        description: '공유기에서 인터넷 연결을 확인할 수 없었습니다.',
      };

    case 'network.internet.recovered': {
      const downtime = metadataNumber(event, 'downtime_seconds');
      return {
        title: '인터넷 연결 복구',
        description:
          downtime !== null && downtime > 0
            ? `약 ${formatDuration(downtime)} 동안 인터넷 연결이 확인되지 않았습니다.`
            : '공유기에서 인터넷 연결을 다시 확인했습니다.',
      };
    }

    case 'safeshield.protection.enabled':
      return {
        title: 'SafeShield 보호 활성화',
        description: 'DNS 보호 기능이 활성화되었습니다.',
      };

    case 'safeshield.protection.disabled':
      return {
        title: 'SafeShield 보호 비활성화',
        description: 'DNS 보호 기능이 비활성화되었습니다.',
      };

    case 'safeshield.blocklist.updated': {
      const domainCount = metadataNumber(event, 'domain_count');
      const artifactVersion = metadataString(event, 'artifact_version');
      const details: string[] = [];
      if (domainCount !== null && domainCount > 0) {
        details.push(`${formatNumber(domainCount)}개 도메인 적용`);
      }
      if (artifactVersion) {
        details.push(`목록 ${artifactVersion}`);
      }
      return {
        title: 'SafeShield 차단 목록 업데이트 완료',
        description: details.length > 0 ? details.join(' · ') : '최신 차단 목록을 적용했습니다.',
      };
    }

    case 'safeshield.blocklist.update_failed':
      return {
        title: 'SafeShield 차단 목록 업데이트 실패',
        description: failureDescription(event, '차단 목록을 업데이트하지 못했습니다.'),
      };


    case 'safeshield.statistics.enabled':
      return {
        title: 'SafeShield 차단 통계 수집 활성화',
        description: '기기별 차단 통계 수집을 활성화했습니다.',
      };

    case 'safeshield.statistics.disabled':
      return {
        title: 'SafeShield 차단 통계 수집 비활성화',
        description: '기기별 차단 통계 수집을 비활성화했습니다.',
      };

    case 'safeshield.rule.added': {
      const action = metadataString(event, 'rule_action');
      return {
        title: action === 'allow' ? '사용자 허용 규칙 추가' : '사용자 차단 규칙 추가',
        description: 'SafeShield 사용자 규칙이 변경되었습니다.',
      };
    }

    case 'safeshield.rule.removed': {
      const action = metadataString(event, 'rule_action');
      return {
        title: action === 'allow' ? '사용자 허용 규칙 삭제' : '사용자 차단 규칙 삭제',
        description: 'SafeShield 사용자 규칙이 변경되었습니다.',
      };
    }

    case 'settings.scheduled_reboot.updated': {
      const enabled = metadataBoolean(event, 'enabled');
      return {
        title: '예약 재부팅 설정 변경',
        description:
          enabled === true
            ? '예약 재부팅 설정을 저장하고 새 일정에 적용했습니다.'
            : enabled === false
              ? '예약 재부팅을 비활성화했습니다.'
              : '예약 재부팅 설정을 변경했습니다.',
      };
    }

    case 'settings.software_updates.updated': {
      const autoInstall = metadataBoolean(event, 'auto_install');
      return {
        title: '관리 소프트웨어 업데이트 설정 변경',
        description:
          autoInstall === true
            ? '자동 설치를 포함한 업데이트 설정을 저장했습니다.'
            : '관리 소프트웨어 업데이트 설정을 저장했습니다.',
      };
    }

    case 'settings.health_reporter.enabled':
      return {
        title: '원격 상태 보고 활성화',
        description: '장치 상태를 SmartSafeHub Cloud에 보고하도록 설정했습니다.',
      };

    case 'settings.health_reporter.disabled':
      return {
        title: '원격 상태 보고 비활성화',
        description: 'SmartSafeHub Cloud로의 장치 상태 보고를 중지했습니다.',
      };

    case 'settings.activity_cloud_sync.enabled':
      return {
        title: 'Cloud 활동 기록 전송 활성화',
        description: '이후 발생하는 활동을 SmartSafeHub Cloud에 전송하도록 설정했습니다.',
      };

    case 'settings.activity_cloud_sync.disabled':
      return {
        title: 'Cloud 활동 기록 전송 비활성화',
        description: 'Cloud 전송을 중지했습니다. 로컬 최근 활동은 계속 기록됩니다.',
      };

    case 'settings.timezone.updated': {
      const zonename = metadataString(event, 'zonename');
      return {
        title: '시간대 설정 변경',
        description: zonename ? `공유기 시간대를 ${zonename}(으)로 변경했습니다.` : '공유기 시간대를 변경했습니다.',
      };
    }

    case 'settings.wifi.updated':
      return {
        title: 'Wi-Fi 설정 변경',
        description: 'Wi-Fi 설정을 저장하고 무선 네트워크에 적용했습니다.',
      };

    case 'settings.lan.updated':
      return {
        title: 'LAN 설정 변경',
        description: '내부 네트워크 및 DHCP 설정을 변경했습니다.',
      };

    case 'settings.iptv.updated': {
      const enabled = metadataBoolean(event, 'enabled');
      const provider = metadataString(event, 'provider');
      const providerLabel = provider === 'skb' ? 'SK Broadband' : provider === 'lgu' ? 'LG U+' : null;
      return {
        title: 'IPTV 설정 변경',
        description:
          enabled === false
            ? 'IPTV 기능을 비활성화했습니다.'
            : providerLabel
              ? `${providerLabel} IPTV 설정을 적용했습니다.`
              : 'IPTV 설정을 적용했습니다.',
      };
    }

    case 'software.update.completed':
      return {
        title: '관리 소프트웨어 업데이트 완료',
        description: versionTransition(event),
      };

    case 'software.update.failed':
      return {
        title: '관리 소프트웨어 업데이트 실패',
        description: failureDescription(event, '관리 소프트웨어를 업데이트하지 못했습니다.'),
      };

    case 'firmware.update.started':
      return {
        title: '펌웨어 업데이트 시작',
        description: '펌웨어 설치를 시작했습니다. 완료 과정에서 공유기가 재부팅됩니다.',
      };

    case 'firmware.update.failed':
      return {
        title: '펌웨어 업데이트 실패',
        description: failureDescription(event, '펌웨어 설치 준비 또는 검증에 실패했습니다.'),
      };

    case 'license.activated': {
      const plan = licensePlan(metadataString(event, 'to_plan'));
      return {
        title: '라이선스 활성화',
        description: plan ? `${plan} 라이선스가 활성화되었습니다.` : '라이선스가 활성화되었습니다.',
      };
    }

    case 'license.changed': {
      const fromPlan = licensePlan(metadataString(event, 'from_plan'));
      const toPlan = licensePlan(metadataString(event, 'to_plan'));
      return {
        title: '라이선스 변경',
        description:
          fromPlan && toPlan
            ? `${fromPlan} → ${toPlan}`
            : toPlan
              ? `${toPlan} 라이선스로 변경되었습니다.`
              : '라이선스 상태가 변경되었습니다.',
      };
    }

    case 'license.cleared': {
      const reason = metadataString(event, 'reason');
      return {
        title: '라이선스 연결 해제',
        description:
          reason === 'manual'
            ? '이 공유기에서 라이선스 연결을 해제했습니다.'
            : '서버의 라이선스 상태가 반영되어 이 공유기의 라이선스 연결이 해제되었습니다.',
      };
    }

    case 'health.issue.started': {
      const warningCount = metadataNumber(event, 'warning_count') ?? 0;
      const criticalCount = metadataNumber(event, 'critical_count') ?? 0;
      const details: string[] = [];
      if (criticalCount > 0) {
        details.push(`이상 ${formatNumber(criticalCount)}건`);
      }
      if (warningCount > 0) {
        details.push(`주의 ${formatNumber(warningCount)}건`);
      }
      return {
        title: '확인이 필요한 장치 상태 발견',
        description: details.length > 0 ? details.join(' · ') : '장치 상태에서 확인이 필요한 항목이 발견되었습니다.',
      };
    }

    case 'health.issue.changed': {
      const warningCount = metadataNumber(event, 'warning_count') ?? 0;
      const criticalCount = metadataNumber(event, 'critical_count') ?? 0;
      const details: string[] = [];
      if (criticalCount > 0) {
        details.push(`이상 ${formatNumber(criticalCount)}건`);
      }
      if (warningCount > 0) {
        details.push(`주의 ${formatNumber(warningCount)}건`);
      }
      return {
        title: '확인이 필요한 장치 상태 변경',
        description: details.length > 0 ? details.join(' · ') : '확인이 필요한 장치 상태 항목이 변경되었습니다.',
      };
    }

    case 'health.issue.resolved':
      return {
        title: '장치 상태 정상으로 복구',
        description: '이전에 확인이 필요했던 장치 상태가 정상으로 돌아왔습니다.',
      };

    default:
      return {
        title: 'SmartSafeHub 활동',
        description: '장치에서 새로운 활동이 기록되었습니다.',
      };
  }
}

function severityTone(severity: ActivityEventSeverity): {
  icon: ComponentChildren;
  surface: string;
} {
  if (severity === 'error') {
    return {
      icon: <AlertIcon class="size-4" />,
      surface: 'bg-rose-50 text-rose-700 ring-rose-200',
    };
  }
  if (severity === 'warning') {
    return {
      icon: <AlertIcon class="size-4" />,
      surface: 'bg-amber-50 text-amber-800 ring-amber-200',
    };
  }
  if (severity === 'success') {
    return {
      icon: <CheckCircleIcon class="size-4" />,
      surface: 'bg-emerald-50 text-emerald-700 ring-emerald-200',
    };
  }
  return {
    icon: <ClockIcon class="size-4" />,
    surface: 'bg-slate-100 text-slate-600 ring-slate-200',
  };
}

function timeLabel(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  return new Intl.DateTimeFormat('ko-KR', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date);
}

function dateKey(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

function dateHeading(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const target = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const elapsedDays = Math.round((today.getTime() - target.getTime()) / 86_400_000);

  if (elapsedDays === 0) {
    return '오늘';
  }
  if (elapsedDays === 1) {
    return '어제';
  }

  return new Intl.DateTimeFormat('ko-KR', {
    month: 'long',
    day: 'numeric',
    weekday: 'short',
  }).format(date);
}

export function ActivityTimeline({
  compact = false,
  events,
}: {
  compact?: boolean;
  events: ActivityEvent[];
}) {
  if (events.length === 0) {
    return (
      <div class="rounded-xl border border-slate-200 bg-slate-50 px-4 py-5 text-center">
        <ClockIcon class="mx-auto size-5 text-slate-400" />
        <p class="mt-2 mb-0 text-sm font-extrabold text-slate-700">아직 기록된 활동이 없습니다.</p>
        <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
          상태가 실제로 변경되면 이곳에 시간순으로 기록됩니다.
        </p>
      </div>
    );
  }

  let previousDate = '';

  return (
    <div class={compact ? 'space-y-2' : 'space-y-1'}>
      {events.map((event) => {
        const presentation = activityPresentation(event);
        const tone = severityTone(event.severity);
        const currentDate = dateKey(event.occurredAt);
        const showDate = !compact && currentDate !== previousDate;
        previousDate = currentDate;

        return (
          <div key={event.eventId}>
            {showDate ? (
              <p class="mt-5 mb-2 first:mt-0 text-xs font-black text-slate-500">
                {dateHeading(event.occurredAt)}
              </p>
            ) : null}
            <article
              class={`relative flex min-w-0 gap-3 ${
                compact
                  ? 'border-b border-slate-100 py-3 first:pt-0 last:border-b-0 last:pb-0'
                  : 'rounded-xl px-2 py-3 hover:bg-slate-50'
              }`}
            >
              <div class="w-12 shrink-0 pt-1 text-xs font-bold tabular-nums text-slate-400">
                <time dateTime={new Date(event.occurredAt * 1000).toISOString()} title={formatTimestamp(event.occurredAt)}>
                  {timeLabel(event.occurredAt)}
                </time>
              </div>
              <span
                class={`mt-0.5 grid size-8 shrink-0 place-items-center rounded-full ring-1 ring-inset ${tone.surface}`}
              >
                {tone.icon}
              </span>
              <div class="min-w-0 flex-1">
                <p class="m-0 text-sm font-black leading-5 text-slate-950">{presentation.title}</p>
                {presentation.description ? (
                  <p class="mt-1 mb-0 break-words text-xs font-medium leading-5 text-slate-500">
                    {presentation.description}
                  </p>
                ) : null}
              </div>
            </article>
          </div>
        );
      })}
    </div>
  );
}

export function ActivityLoadState({
  error,
  loading,
  onRetry,
}: {
  error: string | null;
  loading: boolean;
  onRetry?: () => void;
}) {
  if (loading) {
    return (
      <div class="rounded-xl border border-slate-200 bg-slate-50 px-4 py-5 text-center">
        <ReloadIcon class="mx-auto size-5 animate-spin text-teal-700" />
        <p class="mt-2 mb-0 text-sm font-bold text-slate-500">최근 활동을 불러오는 중입니다.</p>
      </div>
    );
  }

  if (error) {
    return (
      <div class="rounded-xl border border-amber-200 bg-amber-50/70 px-4 py-4">
        <div class="flex items-start gap-3">
          <AlertIcon class="mt-0.5 size-5 shrink-0 text-amber-700" />
          <div class="min-w-0 flex-1">
            <p class="m-0 text-sm font-black text-slate-950">최근 활동을 불러오지 못했습니다.</p>
            <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">{error}</p>
            {onRetry ? (
              <button
                class="mt-3 inline-flex min-h-9 items-center justify-center rounded-lg border border-amber-300 bg-white px-3 text-xs font-extrabold text-amber-800 transition hover:bg-amber-50"
                onClick={onRetry}
                type="button"
              >
                다시 시도
              </button>
            ) : null}
          </div>
        </div>
      </div>
    );
  }

  return null;
}
