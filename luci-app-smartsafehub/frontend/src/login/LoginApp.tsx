import type { JSX } from 'preact';
import { useEffect, useMemo, useRef, useState } from 'preact/hooks';

import {
  authenticateLuciSession,
  luciSessionUrl,
} from '../auth/session';
import {
  EyeIcon,
  EyeOffIcon,
  KeyIcon,
  MoonIcon,
  ReloadIcon,
  ShieldIcon,
  SunIcon,
  UserIcon,
  WifiIcon,
} from '../components/Icons';
import {
  applyDocumentTheme,
  persistColorTheme,
  readColorTheme,
} from '../utils/theme';
import type { ColorTheme } from '../utils/theme';

type LoginPhase = 'ready' | 'submitting';

interface LoginAppProps {
  notice?: string | undefined;
  onAuthenticated: (sessionId: string) => void;
  probing?: boolean;
}

function LoginFeature({
  icon,
  title,
  description,
}: {
  icon: JSX.Element;
  title: string;
  description: string;
}) {
  return (
    <div class="ssh-login-feature">
      <span class="ssh-login-feature-icon" aria-hidden="true">
        {icon}
      </span>
      <span class="ssh-login-feature-copy">
        <strong>{title}</strong>
        <span>{description}</span>
      </span>
    </div>
  );
}

function ThemeIcon({ theme }: { theme: ColorTheme }) {
  return theme === 'dark' ? <SunIcon /> : <MoonIcon />;
}

export function LoginApp({
  notice: initialNotice,
  onAuthenticated,
  probing = false,
}: LoginAppProps) {
  const fallbackUrl = useMemo(luciSessionUrl, []);
  const usernameInput = useRef<HTMLInputElement>(null);
  const passwordInput = useRef<HTMLInputElement>(null);
  const [username, setUsername] = useState('root');
  const [password, setPassword] = useState('');
  const [phase, setPhase] = useState<LoginPhase>('ready');
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(initialNotice ?? null);
  const [showFallback, setShowFallback] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [capsLock, setCapsLock] = useState(false);
  const [theme, setTheme] = useState<ColorTheme>(readColorTheme);

  const busy = phase === 'submitting';
  const themeLabel = theme === 'dark' ? '라이트 모드로 전환' : '다크 모드로 전환';

  useEffect(() => {
    persistColorTheme(theme);
    applyDocumentTheme(theme);
  }, [theme]);

  useEffect(() => {
    if (probing) {
      return;
    }

    const frame = window.requestAnimationFrame(() => passwordInput.current?.focus());
    return () => window.cancelAnimationFrame(frame);
  }, [probing]);

  useEffect(() => {
    setNotice(initialNotice ?? null);

    if (!initialNotice) {
      return;
    }

    const timeout = window.setTimeout(() => setNotice(null), 7_000);
    return () => window.clearTimeout(timeout);
  }, [initialNotice]);

  const updateCapsLock = (event: JSX.TargetedKeyboardEvent<HTMLInputElement>) => {
    setCapsLock(event.getModifierState?.('CapsLock') ?? false);
  };

  const submit = async (event: JSX.TargetedSubmitEvent<HTMLFormElement>) => {
    event.preventDefault();

    const user = username.trim();
    const secret = password;

    setError(null);
    setShowFallback(false);

    if (!user || (!secret && user !== 'root')) {
      setError(
        !user
          ? '사용자 이름을 입력해 주세요.'
          : '비밀번호를 입력해 주세요.',
      );

      window.requestAnimationFrame(() => {
        if (!user) {
          usernameInput.current?.focus();
          return;
        }

        passwordInput.current?.focus();
      });
      return;
    }

    setPhase('submitting');

    try {
      const sessionId = await authenticateLuciSession(user, secret);

      if (sessionId) {
        setPassword('');
        onAuthenticated(sessionId);
        return;
      }

      setPassword('');
      setShowFallback(true);
      setError(
        '로그인하지 못했습니다. 계정 정보를 확인해 주세요. 추가 인증이 설정된 장치는 기본 LuCI 로그인에서 계속할 수 있습니다.',
      );
      window.requestAnimationFrame(() => passwordInput.current?.focus());
    } catch {
      setError(
        '공유기와 통신할 수 없습니다. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
      );
    } finally {
      setPhase('ready');
    }
  };

  return (
    <main class="ssh-login-page" data-theme={theme}>
      {notice ? (
        <div
          aria-atomic="true"
          aria-live="assertive"
          class="ssh-login-toast"
          role="alert"
        >
          <ShieldIcon aria-hidden="true" />
          <span>{notice}</span>
        </div>
      ) : null}

      <section class="ssh-login-brand" aria-labelledby="ssh-login-brand-title">
        <div class="ssh-login-brand-orb ssh-login-brand-orb-one" aria-hidden="true" />
        <div class="ssh-login-brand-orb ssh-login-brand-orb-two" aria-hidden="true" />

        <div class="ssh-login-brand-content">
          <span class="ssh-login-brand-mark" aria-hidden="true">
            <ShieldIcon />
          </span>
          <p class="ssh-login-eyebrow">SMART NETWORK PROTECTION</p>
          <h1 id="ssh-login-brand-title">SmartSafeHub</h1>
          <p class="ssh-login-brand-description">
            네트워크와 보안을 하나의 허브에서 관리하세요. SafeShield 보호 상태부터
            Wi-Fi와 연결 기기까지 로컬에서 빠르게 확인할 수 있습니다.
          </p>

          <div class="ssh-login-features" aria-label="SmartSafeHub 주요 기능">
            <LoginFeature
              description="DNS 기반 광고·피싱 차단과 사용자 보호 정책을 관리합니다."
              icon={<ShieldIcon />}
              title="SafeShield 보호"
            />
            <LoginFeature
              description="Wi-Fi 설정과 현재 연결된 기기의 상태를 한눈에 확인합니다."
              icon={<WifiIcon />}
              title="네트워크 관리"
            />
            <LoginFeature
              description="관리 기능과 인증은 현재 SmartSafeHub 장치에서 직접 처리됩니다."
              icon={<KeyIcon />}
              title="로컬 우선 관리"
            />
          </div>
        </div>
      </section>

      <section class="ssh-login-panel" aria-labelledby="ssh-login-title">
        <button
          aria-label={themeLabel}
          class="ssh-login-theme-toggle"
          onClick={() => setTheme((current) => (current === 'dark' ? 'light' : 'dark'))}
          title={themeLabel}
          type="button"
        >
          <ThemeIcon theme={theme} />
        </button>

        <div class="ssh-login-panel-inner">
          {probing ? (
            <div class="ssh-login-probe" role="status" aria-live="polite">
              <ReloadIcon class="ssh-login-probe-spinner" aria-hidden="true" />
              <strong>SmartSafeHub 연결 확인 중</strong>
              <span>로그인 세션을 확인하고 있습니다.</span>
            </div>
          ) : (
            <div class="ssh-login-card">
              <div class="ssh-login-card-heading">
                <span class="ssh-login-mobile-mark" aria-hidden="true">
                  <ShieldIcon />
                </span>
                <div>
                  <p class="ssh-login-kicker">SMARTSAFEHUB ACCESS</p>
                  <h2 id="ssh-login-title">SmartSafeHub에 로그인</h2>
                  <p class="ssh-login-subtitle">
                    공유기 관리자 계정의 사용자 이름과 비밀번호를 입력해 주세요.
                  </p>
                </div>
              </div>

              {error ? (
                <div class="ssh-login-alert" id="ssh-login-error" role="alert" aria-live="polite">
                  {error}
                </div>
              ) : null}

              <form class="ssh-login-form" onSubmit={submit} noValidate>
                <label class="ssh-login-field" for="smartsafehub-username">
                  <span class="ssh-login-label">사용자 이름</span>
                  <span class="ssh-login-input-wrap">
                    <span class="ssh-login-field-icon" aria-hidden="true">
                      <UserIcon />
                    </span>
                    <input
                      autoCapitalize="none"
                      autoComplete="username"
                      disabled={busy}
                      id="smartsafehub-username"
                      name="username"
                      onInput={(event) => setUsername(event.currentTarget.value)}
                      placeholder="관리자 계정"
                      ref={usernameInput}
                      required
                      spellcheck={false}
                      type="text"
                      value={username}
                    />
                  </span>
                </label>

                <label class="ssh-login-field" for="smartsafehub-password">
                  <span class="ssh-login-label">비밀번호</span>
                  <span class="ssh-login-input-wrap">
                    <span class="ssh-login-field-icon" aria-hidden="true">
                      <KeyIcon />
                    </span>
                    <input
                      autoComplete="current-password"
                      disabled={busy}
                      id="smartsafehub-password"
                      name="password"
                      onBlur={() => setCapsLock(false)}
                      onInput={(event) => setPassword(event.currentTarget.value)}
                      onKeyDown={updateCapsLock}
                      onKeyUp={updateCapsLock}
                      placeholder="관리자 비밀번호"
                      ref={passwordInput}
                      type={showPassword ? 'text' : 'password'}
                      value={password}
                    />
                    <button
                      aria-label={showPassword ? '비밀번호 숨기기' : '비밀번호 표시'}
                      aria-pressed={showPassword}
                      class="ssh-login-password-toggle"
                      disabled={busy}
                      onClick={() => {
                        setShowPassword((visible) => !visible);
                        window.requestAnimationFrame(() => passwordInput.current?.focus());
                      }}
                      title={showPassword ? '비밀번호 숨기기' : '비밀번호 표시'}
                      type="button"
                    >
                      {showPassword ? <EyeOffIcon /> : <EyeIcon />}
                    </button>
                  </span>
                </label>

                {username.trim() === 'root' && password.length === 0 ? (
                  <p class="ssh-login-password-hint">
                    초기 설정 전 root 계정은 비밀번호가 비어 있을 수 있습니다.
                  </p>
                ) : null}

                {capsLock ? (
                  <p class="ssh-login-caps" role="status">
                    Caps Lock이 켜져 있습니다.
                  </p>
                ) : null}

                <button class="ssh-login-submit" disabled={busy} type="submit">
                  {busy ? <ReloadIcon class="ssh-login-submit-spinner" aria-hidden="true" /> : null}
                  <span>{busy ? '로그인 중…' : '로그인'}</span>
                </button>
              </form>

              <div class="ssh-login-security-note">
                <ShieldIcon aria-hidden="true" />
                <span>입력한 계정 정보는 현재 공유기의 LuCI 인증 경로로만 전송됩니다.</span>
              </div>

              {showFallback ? (
                <a class="ssh-login-fallback" href={fallbackUrl}>
                  기본 LuCI 로그인으로 계속
                </a>
              ) : null}
            </div>
          )}

          <footer class="ssh-login-footer">
            <span>SmartSafeHub</span>
            <span aria-hidden="true">·</span>
            <span>{window.location.host}</span>
          </footer>
        </div>
      </section>
    </main>
  );
}
