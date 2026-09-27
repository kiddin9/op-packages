import type { JSX } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';

import { setInitialRootPassword } from '../api/initialSetup';
import { logoutLuciSession } from '../auth/session';
import {
  CheckCircleIcon,
  EyeIcon,
  EyeOffIcon,
  KeyIcon,
  MoonIcon,
  ReloadIcon,
  ShieldIcon,
  SunIcon,
} from '../components/Icons';
import { RpcError } from '../api/rpc';
import {
  applyDocumentTheme,
  persistColorTheme,
  readColorTheme,
} from '../utils/theme';
import type { ColorTheme } from '../utils/theme';

interface InitialPasswordSetupPageProps {
  onCompleted: () => void;
}

interface PasswordPolicy {
  length: boolean;
  letter: boolean;
  number: boolean;
}

function passwordPolicy(password: string): PasswordPolicy {
  return {
    length: password.length >= 8,
    letter: /[A-Za-z]/.test(password),
    number: /[0-9]/.test(password),
  };
}

function ThemeIcon({ theme }: { theme: ColorTheme }) {
  return theme === 'dark' ? <SunIcon /> : <MoonIcon />;
}

function Requirement({ met, children }: { met: boolean; children: string }) {
  return (
    <li class={met ? 'ssh-password-requirement is-met' : 'ssh-password-requirement'}>
      <CheckCircleIcon aria-hidden="true" />
      <span>{children}</span>
    </li>
  );
}

export function InitialPasswordSetupPage({
  onCompleted,
}: InitialPasswordSetupPageProps) {
  const passwordInput = useRef<HTMLInputElement>(null);
  const confirmationInput = useRef<HTMLInputElement>(null);
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [capsLock, setCapsLock] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [theme, setTheme] = useState<ColorTheme>(readColorTheme);

  const policy = passwordPolicy(password);
  const policySatisfied = policy.length && policy.letter && policy.number;
  const confirmationMatches = confirmation.length > 0 && password === confirmation;
  const themeLabel = theme === 'dark' ? '라이트 모드로 전환' : '다크 모드로 전환';

  useEffect(() => {
    persistColorTheme(theme);
    applyDocumentTheme(theme);
  }, [theme]);

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => passwordInput.current?.focus());
    return () => window.cancelAnimationFrame(frame);
  }, []);

  const updateCapsLock = (event: JSX.TargetedKeyboardEvent<HTMLInputElement>) => {
    setCapsLock(event.getModifierState?.('CapsLock') ?? false);
  };

  const submit = async (event: JSX.TargetedSubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);

    if (!policySatisfied) {
      setError('비밀번호는 8자 이상이며 영문과 숫자를 각각 하나 이상 포함해야 합니다.');
      window.requestAnimationFrame(() => passwordInput.current?.focus());
      return;
    }

    if (password !== confirmation) {
      setError('비밀번호 확인 값이 일치하지 않습니다.');
      window.requestAnimationFrame(() => confirmationInput.current?.focus());
      return;
    }

    setSubmitting(true);

    try {
      await setInitialRootPassword(password);
      setPassword('');
      setConfirmation('');

      try {
        await logoutLuciSession();
      } catch {
        // The password RPC invalidates the authenticated ubus session itself.
        // This best-effort LuCI logout only clears the browser cookie when the
        // router is still reachable after the password change.
      }

      onCompleted();
    } catch (caught) {
      setError(
        caught instanceof RpcError
          ? caught.message
          : '관리자 비밀번호를 설정하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main class="ssh-login-page" data-theme={theme}>
      <section class="ssh-login-brand" aria-labelledby="ssh-password-setup-brand-title">
        <div class="ssh-login-brand-orb ssh-login-brand-orb-one" aria-hidden="true" />
        <div class="ssh-login-brand-orb ssh-login-brand-orb-two" aria-hidden="true" />

        <div class="ssh-login-brand-content">
          <span class="ssh-login-brand-mark" aria-hidden="true">
            <ShieldIcon />
          </span>
          <p class="ssh-login-eyebrow">FIRST SECURITY SETUP</p>
          <h1 id="ssh-password-setup-brand-title">
            <span class="ssh-password-setup-brand-title-line">SmartSafeHub</span>
            <span class="ssh-password-setup-brand-title-line">보호 시작</span>
          </h1>
          <p class="ssh-login-brand-description">
            관리자 비밀번호가 없는 상태에서는 SmartSafeHub 관리 기능을 사용할 수 없습니다.
            먼저 이 공유기의 root 관리자 비밀번호를 설정해 주세요.
          </p>

          <div class="ssh-password-setup-summary">
            <ShieldIcon aria-hidden="true" />
            <div>
              <strong>초기 보안 설정이 필요합니다</strong>
              <span>설정이 완료되기 전까지 다른 SmartSafeHub 기능은 잠겨 있습니다.</span>
            </div>
          </div>
        </div>
      </section>

      <section class="ssh-login-panel" aria-labelledby="ssh-password-setup-title">
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
          <div class="ssh-login-card">
            <div class="ssh-login-card-heading">
              <span class="ssh-login-mobile-mark" aria-hidden="true">
                <KeyIcon />
              </span>
              <div>
                <p class="ssh-login-kicker">ADMIN PASSWORD</p>
                <h2 id="ssh-password-setup-title">관리자 비밀번호 설정</h2>
                <p class="ssh-login-subtitle">
                  비밀번호 설정 후 새 비밀번호로 다시 로그인해야 합니다.
                </p>
              </div>
            </div>

            {error ? (
              <div class="ssh-login-alert" role="alert" aria-live="polite">
                {error}
              </div>
            ) : null}

            <form class="ssh-login-form" onSubmit={submit} noValidate>
              <label class="ssh-login-field" for="smartsafehub-new-root-password">
                <span class="ssh-login-label">새 비밀번호</span>
                <span class="ssh-login-input-wrap">
                  <span class="ssh-login-field-icon" aria-hidden="true">
                    <KeyIcon />
                  </span>
                  <input
                    autoComplete="new-password"
                    disabled={submitting}
                    id="smartsafehub-new-root-password"
                    name="new-password"
                    onBlur={() => setCapsLock(false)}
                    onInput={(event) => setPassword(event.currentTarget.value)}
                    onKeyDown={updateCapsLock}
                    onKeyUp={updateCapsLock}
                    placeholder="새 관리자 비밀번호"
                    ref={passwordInput}
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                  />
                  <button
                    aria-label={showPassword ? '비밀번호 숨기기' : '비밀번호 표시'}
                    aria-pressed={showPassword}
                    class="ssh-login-password-toggle"
                    disabled={submitting}
                    onClick={() => setShowPassword((visible) => !visible)}
                    title={showPassword ? '비밀번호 숨기기' : '비밀번호 표시'}
                    type="button"
                  >
                    {showPassword ? <EyeOffIcon /> : <EyeIcon />}
                  </button>
                </span>
              </label>

              <ul class="ssh-password-requirements" aria-label="비밀번호 요구 사항">
                <Requirement met={policy.length}>8자 이상</Requirement>
                <Requirement met={policy.letter}>영문자 1자 이상 포함</Requirement>
                <Requirement met={policy.number}>숫자 1자 이상 포함</Requirement>
              </ul>

              <label class="ssh-login-field" for="smartsafehub-confirm-root-password">
                <span class="ssh-login-label">비밀번호 확인</span>
                <span class="ssh-login-input-wrap">
                  <span class="ssh-login-field-icon" aria-hidden="true">
                    <KeyIcon />
                  </span>
                  <input
                    autoComplete="new-password"
                    disabled={submitting}
                    id="smartsafehub-confirm-root-password"
                    name="confirm-password"
                    onBlur={() => setCapsLock(false)}
                    onInput={(event) => setConfirmation(event.currentTarget.value)}
                    onKeyDown={updateCapsLock}
                    onKeyUp={updateCapsLock}
                    placeholder="새 관리자 비밀번호 다시 입력"
                    ref={confirmationInput}
                    type={showPassword ? 'text' : 'password'}
                    value={confirmation}
                  />
                </span>
              </label>

              {confirmation.length > 0 ? (
                <p
                  class={confirmationMatches ? 'ssh-password-match is-met' : 'ssh-password-match'}
                  role="status"
                >
                  {confirmationMatches
                    ? '비밀번호가 일치합니다.'
                    : '비밀번호가 일치하지 않습니다.'}
                </p>
              ) : null}

              {capsLock ? (
                <p class="ssh-login-caps" role="status">
                  Caps Lock이 켜져 있습니다.
                </p>
              ) : null}

              <button class="ssh-login-submit" disabled={submitting} type="submit">
                {submitting ? (
                  <ReloadIcon class="ssh-login-submit-spinner" aria-hidden="true" />
                ) : null}
                <span>{submitting ? '설정 중…' : '비밀번호 설정'}</span>
              </button>
            </form>

            <div class="ssh-login-security-note">
              <ShieldIcon aria-hidden="true" />
              <span>비밀번호는 현재 공유기에 직접 설정되며 외부 서버로 전송되지 않습니다.</span>
            </div>
          </div>

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
