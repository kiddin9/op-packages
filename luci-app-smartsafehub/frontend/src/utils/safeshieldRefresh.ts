export interface SafeShieldRefreshStep {
  description: string;
  label: string;
  number: number;
  total: number;
}

interface SafeShieldRefreshStepDefinition {
  description: string;
  label: string;
  stages: readonly string[];
}

const REFRESH_STEP_DEFINITIONS: readonly SafeShieldRefreshStepDefinition[] = [
  {
    label: '갱신 준비',
    description: '차단 목록 갱신을 준비하고 있습니다.',
    stages: [
      'starting',
      'boot_delay',
      'boot_refresh',
      'boot_refresh_skipped',
      'scheduled_refresh',
      'init',
    ],
  },
  {
    label: '최신 차단 목록 확인',
    description: '서버에서 최신 차단 목록 정보를 확인하고 있습니다.',
    stages: ['resolve_api'],
  },
  {
    label: '차단 목록 다운로드',
    description: '최신 차단 목록을 안전하게 다운로드하고 있습니다.',
    stages: ['download_artifact'],
  },
  {
    label: '사용자 규칙 적용',
    description: '허용·차단 사용자 규칙을 새 차단 목록에 반영하고 있습니다.',
    stages: ['local_overrides', 'merge'],
  },
  {
    label: '보호 규칙 적용',
    description: '새 차단 규칙을 설치하고 DNS 보호 서비스를 갱신하고 있습니다.',
    stages: ['install', 'restart_dnsmasq'],
  },
  {
    label: '보호 상태 확인',
    description: '새 차단 목록과 DNS 보호가 정상적으로 동작하는지 확인하고 있습니다.',
    stages: ['runtime_check', 'blocklist_verify'],
  },
];

const REFRESH_STAGE_TO_INDEX = new Map<string, number>();

REFRESH_STEP_DEFINITIONS.forEach((step, index) => {
  step.stages.forEach((stage) => REFRESH_STAGE_TO_INDEX.set(stage, index));
});

export function isSafeShieldRefreshTransition(
  status: string,
  stage: string | null,
): boolean {
  return status === 'running' || (stage !== null && REFRESH_STAGE_TO_INDEX.has(stage));
}

export function getSafeShieldRefreshStep(stage: string | null): SafeShieldRefreshStep {
  const index = stage === null ? 0 : (REFRESH_STAGE_TO_INDEX.get(stage) ?? 0);
  const definition = REFRESH_STEP_DEFINITIONS[index]!;

  return {
    description: definition.description,
    label: definition.label,
    number: index + 1,
    total: REFRESH_STEP_DEFINITIONS.length,
  };
}

function normalizedErrorCode(errorCode: string | null): string {
  return (errorCode ?? '').trim().toLowerCase();
}

export function getSafeShieldRefreshErrorMessage(
  errorCode: string | null,
  stage: string | null,
): string {
  const code = normalizedErrorCode(errorCode);

  if (code.includes('upgrade') || code.includes('version')) {
    return '현재 SafeShield 버전으로는 갱신을 계속할 수 없습니다. 시스템 업데이트에서 SafeShield를 최신 버전으로 업데이트해 주세요.';
  }

  if (code.includes('license') || code.includes('unauthorized') || code.includes('forbidden')) {
    return '차단 목록을 사용할 권한을 확인하지 못했습니다. SafeShield 라이선스 상태를 확인해 주세요.';
  }

  if (
    code.includes('dnsmasq') ||
    code.includes('restart') ||
    code.includes('runtime')
  ) {
    return 'DNS 보호 서비스를 정상적으로 갱신하지 못했습니다. 잠시 후 다시 갱신해 보고 문제가 계속되면 상태 점검 정보를 확인해 주세요.';
  }

  if (code.includes('verify') || code.includes('sanity')) {
    return '새 차단 목록을 적용한 뒤 보호 상태 확인을 완료하지 못했습니다. 다시 갱신해 주세요.';
  }

  if (
    code.includes('download') ||
    code.includes('fetch') ||
    code.includes('timeout') ||
    code.includes('network') ||
    code.includes('wan')
  ) {
    return '차단 목록을 다운로드하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 갱신해 주세요.';
  }

  if (
    code.includes('resolve') ||
    code.includes('manifest') ||
    code.includes('artifact') ||
    code.includes('api')
  ) {
    return '최신 차단 목록 정보를 확인하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 갱신해 주세요.';
  }

  if (
    code.includes('override') ||
    code.includes('allowlist') ||
    code.includes('merge') ||
    code.includes('rule')
  ) {
    return '사용자 허용·차단 규칙을 새 차단 목록에 반영하지 못했습니다. 사용자 규칙을 확인한 뒤 다시 갱신해 주세요.';
  }

  if (code.includes('install') || code.includes('write') || code.includes('space')) {
    return '새 차단 규칙을 장치에 적용하지 못했습니다. 저장 공간과 SafeShield 상태를 확인한 뒤 다시 갱신해 주세요.';
  }

  const step = getSafeShieldRefreshStep(stage);

  if (step.number === 2) {
    return '최신 차단 목록 정보를 확인하는 중 문제가 발생했습니다. 인터넷 연결을 확인한 뒤 다시 갱신해 주세요.';
  }

  if (step.number === 3) {
    return '차단 목록을 다운로드하는 중 문제가 발생했습니다. 인터넷 연결을 확인한 뒤 다시 갱신해 주세요.';
  }

  if (step.number === 4) {
    return '사용자 규칙을 적용하는 중 문제가 발생했습니다. 사용자 규칙을 확인한 뒤 다시 갱신해 주세요.';
  }

  if (step.number === 5) {
    return '새 보호 규칙을 적용하는 중 문제가 발생했습니다. 잠시 후 다시 갱신해 주세요.';
  }

  if (step.number === 6) {
    return '새 차단 목록의 보호 상태를 확인하지 못했습니다. 다시 갱신해 주세요.';
  }

  return '차단 목록 갱신을 완료하지 못했습니다. 잠시 후 다시 갱신해 주세요.';
}
