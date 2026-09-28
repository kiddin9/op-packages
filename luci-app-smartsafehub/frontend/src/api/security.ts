import type { RootPasswordStatus } from '../types/security';
import { callApi } from './rpc';

export function changeRootPassword(
  currentPassword: string,
  newPassword: string,
): Promise<RootPasswordStatus> {
  return callApi<RootPasswordStatus>(
    'smartsafehub',
    'system_root_password_change',
    {
      current_password: currentPassword,
      new_password: newPassword,
    },
  );
}
