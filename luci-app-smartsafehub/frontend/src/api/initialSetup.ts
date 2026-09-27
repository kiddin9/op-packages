import { callApi } from './rpc';
import type { RootPasswordStatus } from '../types/security';

export function readRootPasswordStatus(): Promise<RootPasswordStatus> {
  return callApi<RootPasswordStatus>(
    'smartsafehub',
    'system_root_password_status',
  );
}

export function setInitialRootPassword(
  password: string,
): Promise<RootPasswordStatus> {
  return callApi<RootPasswordStatus>(
    'smartsafehub',
    'system_root_password_set',
    { password },
  );
}
