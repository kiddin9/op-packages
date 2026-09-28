const RECOVERY_ENDPOINT = '/cgi-bin/smartsafehub-password-recovery';
const SESSION_ID_PATTERN = /^[0-9a-f]{32}$/i;

interface RecoverySessionResponse {
  active?: boolean;
  sessionId?: string;
}

function isRecoverySessionResponse(value: unknown): value is RecoverySessionResponse {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export async function requestPasswordRecoverySession(): Promise<string | null> {
  const response = await fetch(RECOVERY_ENDPOINT, {
    cache: 'no-store',
    credentials: 'same-origin',
    headers: {
      Accept: 'application/json',
    },
    redirect: 'error',
  });

  if (!response.ok) {
    throw new Error(`Password recovery endpoint returned HTTP ${response.status}`);
  }

  const payload: unknown = await response.json();
  if (!isRecoverySessionResponse(payload) || payload.active !== true) {
    return null;
  }

  const sessionId = payload.sessionId;
  if (typeof sessionId !== 'string' || !SESSION_ID_PATTERN.test(sessionId)) {
    throw new Error('Password recovery endpoint returned an invalid session id');
  }

  return sessionId;
}
