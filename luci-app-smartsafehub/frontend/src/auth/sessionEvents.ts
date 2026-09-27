export const SESSION_EXPIRED_EVENT = 'smartsafehub:session-expired';
export const SESSION_EXPIRED_MESSAGE =
  '로그인 세션이 만료되었습니다. 계속하려면 다시 로그인해 주세요.';

let lastExpiredSessionId: string | null = null;

export function markSessionActive(): void {
  lastExpiredSessionId = null;
}

export function hasNotifiedSessionExpired(sessionId: string): boolean {
  return lastExpiredSessionId === sessionId;
}

export function notifySessionExpired(sessionId: string): void {
  if (lastExpiredSessionId === sessionId) {
    return;
  }

  lastExpiredSessionId = sessionId;
  window.dispatchEvent(new CustomEvent(SESSION_EXPIRED_EVENT));
}
