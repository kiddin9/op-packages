import { callApi } from './rpc';
import type { NetwatchStatus } from '../types/netwatch';

export function fetchNetwatchStatus(): Promise<NetwatchStatus> {
  return callApi('smartsafehub', 'netwatch_status', {}, { priority: 'low', timeoutMs: 5000 });
}

export function updateNetwatchEnabled(enabled: boolean): Promise<NetwatchStatus> {
  return callApi('smartsafehub', 'netwatch_enabled_update', { enabled }, { priority: 'high', timeoutMs: 6000 });
}
