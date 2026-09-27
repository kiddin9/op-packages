import { luciUrl } from '../utils/luci';

const SESSION_ID_PATTERN = /^[0-9a-f]{32}$/i;

export function luciSessionUrl(): string {
  return luciUrl('/smartsafehub/session');
}

function loginRequired(response: Response): boolean {
  return response.headers.get('X-LuCI-Login-Required') === 'yes';
}

async function sessionIdFromResponse(response: Response): Promise<string | null> {
  if (
    response.status === 401 ||
    response.status === 403 ||
    loginRequired(response)
  ) {
    return null;
  }

  if (!response.ok) {
    throw new Error(`LuCI session endpoint returned HTTP ${response.status}`);
  }

  const sessionId = (await response.text()).trim();

  if (SESSION_ID_PATTERN.test(sessionId)) {
    return sessionId;
  }

  if (
    response.redirected ||
    /^(?:access|permission)\s+denied\.?$/i.test(sessionId) ||
    /^<!doctype\s+html/i.test(sessionId) ||
    /<html(?:\s|>)/i.test(sessionId)
  ) {
    return null;
  }

  throw new Error('LuCI session endpoint returned an invalid session id');
}

async function fetchSession(options: RequestInit = {}): Promise<string | null> {
  const response = await fetch(luciSessionUrl(), {
    cache: 'no-store',
    credentials: 'same-origin',
    redirect: 'follow',
    ...options,
  });

  return sessionIdFromResponse(response);
}

export function probeLuciSession(): Promise<string | null> {
  return fetchSession();
}

export async function logoutLuciSession(): Promise<void> {
  await fetch(luciUrl('/admin/logout'), {
    cache: 'no-store',
    credentials: 'same-origin',
    redirect: 'manual',
  });
}

export function authenticateLuciSession(
  username: string,
  password: string,
): Promise<string | null> {
  const body = new URLSearchParams();
  body.set('luci_username', username);
  body.set('luci_password', password);

  return fetchSession({
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
    },
    body,
  });
}
