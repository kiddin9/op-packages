import type { TargetedSubmitEvent } from 'preact';
import { useEffect, useState } from 'preact/hooks';

import { WifiQrDialog } from './WifiQrDialog';
import { AlertIcon, CheckCircleIcon, ChevronDownIcon, QrCodeIcon, RouterIcon } from './Icons';
import type { GuestWifiSummary, GuestWifiUpdateInput } from '../types/wifi';

export function GuestWifiCard({
  guest,
  busy,
  saving,
  onUpdate,
}: {
  guest: GuestWifiSummary;
  busy: boolean;
  saving: boolean;
  onUpdate: (input: GuestWifiUpdateInput) => Promise<boolean>;
}) {
  // Keep guest settings out of the way until the administrator needs them.
  const [expanded, setExpanded] = useState(false);
  const [showQr, setShowQr] = useState(false);
  const [ssid, setSsid] = useState(guest.ssid);
  const [password, setPassword] = useState('');
  const [enabled, setEnabled] = useState(guest.enabled);
  const [validation, setValidation] = useState<string | null>(null);

  useEffect(() => {
    setSsid(guest.ssid);
    setEnabled(guest.enabled);
    setPassword('');
    setValidation(null);
  }, [guest]);

  if (!guest.supported) {
    return (
      <section class="mt-5 rounded-2xl border border-slate-200 bg-white p-5 sm:p-6">
        <h2 class="m-0 text-lg font-extrabold text-slate-900">게스트 Wi-Fi</h2>
        <p class="mt-2 mb-0 text-sm text-slate-600">2.4GHz 기본 Wi-Fi 장치를 찾지 못해 게스트 Wi-Fi를 사용할 수 없습니다.</p>
      </section>
    );
  }

  const dirty = ssid.trim() !== guest.ssid || enabled !== guest.enabled || password.length > 0;
  const qrDisabled = busy || dirty || !guest.enabled || !guest.passwordConfigured;

  const submit = async (event: TargetedSubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const normalizedSsid = ssid.trim();
    const bytes = new TextEncoder().encode(normalizedSsid).length;
    if (bytes < 1 || bytes > 32) {
      setValidation('Wi-Fi 이름은 UTF-8 기준 1~32바이트로 입력해 주세요.');
      return;
    }
    if (password && !((password.length >= 8 && password.length <= 63) || /^[0-9a-fA-F]{64}$/.test(password))) {
      setValidation('비밀번호는 8~63자 또는 64자리 16진수여야 합니다.');
      return;
    }
    if (enabled && !guest.passwordConfigured && !password) {
      setValidation('게스트 전용 비밀번호를 입력해 주세요.');
      return;
    }
    if (!window.confirm('게스트 Wi-Fi 설정을 적용하면 무선 연결이 잠시 끊어질 수 있습니다. 계속하시겠습니까?')) return;
    setValidation(null);
    const saved = await onUpdate({ ssid: normalizedSsid, enabled, password });
    if (saved) setPassword('');
  };

  return (
    <>
      <form
        aria-label="게스트 Wi-Fi 설정"
        class="mt-5 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-6"
        onSubmit={(event) => void submit(event)}
      >
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <button
            aria-controls="ssh-guest-settings"
            aria-expanded={expanded}
            aria-label={`게스트 Wi-Fi 설정 ${expanded ? '접기' : '펼치기'}`}
            class="flex min-w-0 flex-1 items-start gap-3 rounded-xl text-left focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100"
            onClick={() => setExpanded((current) => !current)}
            type="button"
          >
            <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700">
              <RouterIcon class="size-6" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="block text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">2.4 GHz · 분리 네트워크</span>
              <span class="mt-2 block text-xl font-extrabold tracking-tight text-slate-950">게스트 Wi-Fi</span>
              <span class="mt-2 block break-all text-sm text-slate-600">{guest.ssid}</span>
            </span>
            <ChevronDownIcon class={`mt-3 size-5 shrink-0 text-slate-500 transition-transform ${expanded ? 'rotate-180' : ''}`} />
          </button>
          <div class="flex flex-wrap items-center gap-2 sm:justify-end">
            {dirty && (
              <span aria-live="polite" class="inline-flex items-center gap-1 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-extrabold text-amber-800">
                <AlertIcon class="size-3.5" />저장되지 않음
              </span>
            )}
            <button
              aria-label="게스트 Wi-Fi QR 코드 보기"
              class="inline-flex min-h-10 items-center gap-2 rounded-xl border border-slate-300 bg-white px-3.5 py-2 text-sm font-extrabold text-slate-800 transition hover:border-teal-300 hover:text-teal-700 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-not-allowed disabled:opacity-50"
              disabled={qrDisabled}
              onClick={() => setShowQr(true)}
              title={!guest.enabled ? '게스트 Wi-Fi를 켜고 저장하면 QR 코드를 사용할 수 있습니다.' : undefined}
              type="button"
            >
              <QrCodeIcon class="size-4 shrink-0" />
              QR 코드 보기
            </button>
            <span class={`rounded-full px-3 py-1.5 text-xs font-extrabold ${guest.enabled ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}>
              {guest.enabled ? '사용 중' : '꺼짐'}
            </span>
          </div>
        </div>

        <div class={expanded ? '' : 'hidden'} id="ssh-guest-settings">
          <p class="mt-5 mb-0 text-sm leading-6 text-slate-600">방문자는 인터넷만 이용하며 내부 네트워크와 공유기 관리 화면에는 접근할 수 없습니다.</p>
          <div class="mt-5 grid gap-5 lg:grid-cols-2">
            <label class="block">
              <span class="text-sm font-extrabold text-slate-800">게스트 Wi-Fi 이름 (SSID)</span>
              <input
                autocomplete="off"
                class="mt-2 min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold text-slate-950 outline-none focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:opacity-60"
                disabled={busy}
                maxLength={32}
                onInput={(event) => setSsid(event.currentTarget.value)}
                value={ssid}
              />
            </label>
            <label class="block">
              <span class="text-sm font-extrabold text-slate-800">게스트 Wi-Fi 비밀번호</span>
              <input
                autocomplete="new-password"
                class="mt-2 min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold text-slate-950 outline-none focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:opacity-60"
                disabled={busy}
                onInput={(event) => setPassword(event.currentTarget.value)}
                placeholder={guest.passwordConfigured ? '비워 두면 기존 비밀번호 유지' : '8자 이상의 별도 비밀번호 입력'}
                type="password"
                value={password}
              />
              <span class="mt-2 block text-xs text-slate-500">WPA2/WPA3 혼합 · 기본 Wi-Fi와 다른 비밀번호를 권장합니다.</span>
            </label>
          </div>
          <div class="mt-5 rounded-xl bg-slate-50 px-4 py-3 text-sm leading-6 text-slate-700">
            내부망 접근 차단 · 게스트 기기 간 통신 차단 · SafeShield DNS 사용
            {guest.subnet && <span class="block text-xs text-slate-500">게스트 게이트웨이: {guest.subnet}</span>}
          </div>
          <div class="mt-5 flex flex-col gap-4 border-t border-slate-200 pt-5 sm:flex-row sm:items-center sm:justify-between">
            <label class="inline-flex min-h-11 items-center gap-3 text-sm font-extrabold text-slate-800">
              <input
                checked={enabled}
                class="size-5 accent-teal-700"
                disabled={busy}
                onChange={(event) => setEnabled(event.currentTarget.checked)}
                type="checkbox"
              />
              게스트 Wi-Fi 사용
            </label>
            <button
              class="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-xl bg-teal-700 px-5 py-2.5 text-sm font-extrabold text-white transition hover:bg-teal-800 disabled:opacity-60 sm:w-auto"
              disabled={busy || !dirty}
              type="submit"
            >
              <CheckCircleIcon class={`size-5 ${saving ? 'animate-pulse' : ''}`} />
              {saving ? '적용 중' : '설정 저장'}
            </button>
          </div>
          {validation && <p class="mt-4 mb-0 rounded-xl bg-red-50 px-4 py-3 text-sm font-bold text-red-800">{validation}</p>}
        </div>
      </form>
      {showQr && <WifiQrDialog guest section="ssh_guest" onClose={() => setShowQr(false)} />}
    </>
  );
}
