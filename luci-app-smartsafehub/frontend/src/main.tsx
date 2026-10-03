import { render } from 'preact';

import { requestPasswordRecoverySession } from './api/passwordRecovery';
import { probeLuciSession } from './auth/session';
import {
  markSessionActive,
  SESSION_EXPIRED_EVENT,
  SESSION_EXPIRED_MESSAGE,
} from './auth/sessionEvents';
import { AuthenticatedEntry } from './app/AuthenticatedEntry';
import { LoginApp } from './login/LoginApp';
import { luciUrl, smartSafeHubPublicUrl } from './utils/luci';
import { applyDocumentTheme, readColorTheme } from './utils/theme';
import './styles/app.css';

const ENTRY_HOST_ID = 'smartsafehub-entry-root';
const MOUNT_ATTRIBUTE = 'data-smartsafehub-mount';
const STYLESHEET_ATTRIBUTE = 'data-smartsafehub-shadow-style';


function canonicalizeEntryUrl(): void {
  const luciRootPath = luciUrl('/');
  const compatibilityPaths = new Set([
    luciRootPath,
    luciRootPath.replace(/\/$/, ''),
    luciUrl('/smartsafehub'),
    luciUrl('/admin/smartsafehub'),
  ]);

  if (!compatibilityPaths.has(window.location.pathname)) {
    return;
  }

  window.history.replaceState(
    null,
    '',
    `${smartSafeHubPublicUrl()}${window.location.search}${window.location.hash}`,
  );
}

function installBootstrap(sessionId: string, host: HTMLElement): void {
  markSessionActive();
  window.__SMARTHUB_BOOTSTRAP__ = Object.freeze({
    sessionId,
    rpcUrl: luciUrl('/admin/ubus'),
    assetBase: host.dataset.assetBase ?? '/luci-static/smartsafehub/',
    assetVersion: host.dataset.assetVersion ?? '0.2.27-r1',
    locale: document.documentElement.lang || 'ko',
  });
}

function assetUrl(name: string, host: HTMLElement): string {
  const bootstrap = window.__SMARTHUB_BOOTSTRAP__;
  const base =
    bootstrap?.assetBase ?? host.dataset.assetBase ?? '/luci-static/smartsafehub/';
  const version = bootstrap?.assetVersion ?? host.dataset.assetVersion;
  const separator = base.endsWith('/') ? '' : '/';
  const url = `${base}${separator}${name}`;

  return version ? `${url}?v=${encodeURIComponent(version)}` : url;
}

function getMountPoint(host: HTMLElement, className: string): HTMLElement {
  const shadow = host.shadowRoot ?? host.attachShadow({ mode: 'open' });

  let stylesheet = shadow.querySelector<HTMLLinkElement>(
    `link[${STYLESHEET_ATTRIBUTE}]`,
  );

  const stylesheetUrl = assetUrl('app.css', host);

  if (!stylesheet) {
    stylesheet = document.createElement('link');
    stylesheet.rel = 'stylesheet';
    stylesheet.href = stylesheetUrl;
    stylesheet.setAttribute(STYLESHEET_ATTRIBUTE, '');
    shadow.appendChild(stylesheet);
  } else if (stylesheet.getAttribute('href') !== stylesheetUrl) {
    stylesheet.href = stylesheetUrl;
  }

  let mountPoint = shadow.querySelector<HTMLElement>(`[${MOUNT_ATTRIBUTE}]`);

  if (!mountPoint) {
    mountPoint = document.createElement('div');
    mountPoint.className = className;
    mountPoint.setAttribute(MOUNT_ATTRIBUTE, '');
    shadow.appendChild(mountPoint);
  } else if (mountPoint.className !== className) {
    mountPoint.className = className;
  }

  return mountPoint;
}

function renderAuthenticated(
  host: HTMLElement,
  mountPoint: HTMLElement,
  sessionId: string,
): void {
  installBootstrap(sessionId, host);
  mountPoint.className = 'smartsafehub-shadow-root';
  render(
    <AuthenticatedEntry
      onAdministratorPasswordChanged={() => {
        renderLogin(
          host,
          mountPoint,
          '관리자 비밀번호가 변경되었습니다. 새 비밀번호로 다시 로그인해 주세요.',
        );
      }}
      onPasswordConfigured={(recovery) => {
        renderLogin(
          host,
          mountPoint,
          recovery
            ? '관리자 비밀번호 복구가 완료되었습니다. 새 비밀번호로 다시 로그인해 주세요.'
            : '관리자 비밀번호가 설정되었습니다. 새 비밀번호로 다시 로그인해 주세요.',
        );
      }}
    />,
    mountPoint,
  );
}

function renderLogin(
  host: HTMLElement,
  mountPoint: HTMLElement,
  notice?: string,
): void {
  delete window.__SMARTHUB_BOOTSTRAP__;
  mountPoint.className = 'smartsafehub-login-shadow-root';
  render(
    <LoginApp
      notice={notice}
      onAuthenticated={(sessionId) => {
        renderAuthenticated(host, mountPoint, sessionId);
      }}
    />,
    mountPoint,
  );
}

async function bootstrapEntry(): Promise<void> {
  applyDocumentTheme(readColorTheme());

  const host = document.getElementById(ENTRY_HOST_ID);

  if (!host) {
    return;
  }

  canonicalizeEntryUrl();

  host.style.display = 'block';
  host.style.width = '100%';
  host.style.minWidth = '0';
  host.style.minHeight = '100dvh';
  host.style.maxWidth = '100%';
  host.style.isolation = 'isolate';

  const mountPoint = getMountPoint(host, 'smartsafehub-login-shadow-root');

  window.addEventListener(SESSION_EXPIRED_EVENT, () => {
    renderLogin(host, mountPoint, SESSION_EXPIRED_MESSAGE);
  });

  render(
    <LoginApp
      onAuthenticated={(sessionId) => {
        renderAuthenticated(host, mountPoint, sessionId);
      }}
      probing
    />,
    mountPoint,
  );

  try {
    const recoverySessionId = await requestPasswordRecoverySession();

    if (recoverySessionId) {
      renderAuthenticated(host, mountPoint, recoverySessionId);
      return;
    }
  } catch {
    // Recovery session creation is deliberately best-effort here. If the
    // public recovery bridge is temporarily unavailable, keep the normal LuCI
    // login path reachable instead of leaving the entry page blank.
  }

  try {
    const sessionId = await probeLuciSession();

    if (sessionId) {
      renderAuthenticated(host, mountPoint, sessionId);
      return;
    }
  } catch {
    // Keep the public entry usable. A manual login attempt will surface
    // connectivity problems if the protected session endpoint is unreachable.
  }

  renderLogin(host, mountPoint);
}

void bootstrapEntry();
