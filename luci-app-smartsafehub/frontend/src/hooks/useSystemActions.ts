import { useCallback, useState } from 'preact/hooks';

import { fetchSafeShieldStatus } from '../api/safeshield';
import {
  fetchHealthStatus,
  fetchWifiSummary,
  requestSystemReboot,
} from '../api/smartsafehub';
import type { SafeShieldStatus } from '../types/safeshield';
import type { SmartSafeHubStatus } from '../types/status';
import type { SystemDiagnostics } from '../types/system';
import type { WifiSummary } from '../types/wifi';
import { diagnosticFilename, downloadJson } from '../utils/download';
import { errorMessage } from '../utils/errors';

export type SystemAction = 'diagnostics' | 'reboot' | null;

interface SystemActionState {
  action: SystemAction;
  error: string | null;
  message: string | null;
  rebootAccepted: boolean;
}

function diagnosticSafeShieldStatus(status: SafeShieldStatus) {
  return {
    enabled: status.available ? status.enabled : null,
    status: status.status,
    lastResult: status.runtime.lastResult,
    validLineCount: status.blocklist.validLineCount,
    blocklistInstalled: status.blocklist.installed,
    dnsmasqOk: status.runtime.dnsRuntimeOk,
  };
}

function unavailableWifiSummary(): WifiSummary {
  return {
    networks: [],
    totalClients: 0,
  };
}

function unavailableSafeShieldDiagnostic() {
  return {
    enabled: null,
    status: 'unavailable',
    lastResult: null,
    validLineCount: 0,
    blocklistInstalled: false,
    dnsmasqOk: false,
  };
}

async function fetchDiagnostics(
  system: SmartSafeHubStatus | null,
): Promise<SystemDiagnostics> {
  if (!system) {
    throw new Error(
      '시스템 상태가 준비되지 않았습니다. 새로고침한 뒤 다시 시도해 주세요.',
    );
  }

  // The system snapshot is already loaded for this page. Wi-Fi, SafeShield and
  // local Health details are requested in parallel so one unavailable optional
  // service does not prevent the diagnostic file download.
  const [wifiResult, safeshieldResult, healthResult] = await Promise.allSettled([
    fetchWifiSummary(),
    fetchSafeShieldStatus(),
    fetchHealthStatus(),
  ]);

  return {
    generatedAt: Math.floor(Date.now() / 1000),
    health: healthResult.status === 'fulfilled' ? healthResult.value : null,
    system,
    wifi:
      wifiResult.status === 'fulfilled'
        ? wifiResult.value
        : unavailableWifiSummary(),
    safeshield:
      safeshieldResult.status === 'fulfilled'
        ? diagnosticSafeShieldStatus(safeshieldResult.value)
        : unavailableSafeShieldDiagnostic(),
  };
}

export function useSystemActions(system: SmartSafeHubStatus | null) {
  const [state, setState] = useState<SystemActionState>({
    action: null,
    error: null,
    message: null,
    rebootAccepted: false,
  });

  const downloadDiagnostics = useCallback(async () => {
    setState((current) => ({
      ...current,
      action: 'diagnostics',
      error: null,
      message: null,
    }));

    try {
      const diagnostics = await fetchDiagnostics(system);
      downloadJson(
        diagnosticFilename(
          diagnostics.system.device.hostname,
          diagnostics.generatedAt,
        ),
        diagnostics,
      );
      setState((current) => ({
        ...current,
        action: null,
        message: '진단 정보 파일을 만들었습니다.',
      }));
    } catch (error) {
      setState((current) => ({
        ...current,
        action: null,
        error: errorMessage(error, '시스템 작업을 완료하지 못했습니다.'),
      }));
    }
  }, [system]);

  const reboot = useCallback(async () => {
    setState((current) => ({
      ...current,
      action: 'reboot',
      error: null,
      message: null,
    }));

    try {
      const result = await requestSystemReboot();
      setState({
        action: null,
        error: null,
        message: result.accepted
          ? '재부팅을 시작했습니다. 잠시 후 공유기에 다시 연결해 주세요.'
          : '재부팅 요청이 접수되지 않았습니다.',
        rebootAccepted: result.accepted,
      });
    } catch (error) {
      setState((current) => ({
        ...current,
        action: null,
        error: errorMessage(error, '시스템 작업을 완료하지 못했습니다.'),
      }));
    }
  }, []);

  const dismissFeedback = useCallback(() => {
    setState((current) => ({
      ...current,
      error: null,
      message: null,
    }));
  }, []);

  return {
    ...state,
    dismissFeedback,
    downloadDiagnostics,
    reboot,
  };
}
