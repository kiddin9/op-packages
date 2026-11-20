import { useEffect, useRef, useState } from 'preact/hooks';

import {
  AlertIcon, CheckCircleIcon, DevicesIcon, KeyIcon, PowerIcon, ReloadIcon,
  SearchIcon, SettingsIcon,
} from '../components/Icons';
import { SectionHeading } from '../components/SectionHeading';
import { ErrorPanel } from '../components/StatePanels';
import { SmartHomeWelcome } from '../components/SmartHomeWelcome';
import { smartHomeEntry } from '../utils/smartHomeEntry';
import type { AppsCatalog, AppsInstallStatus } from '../types/apps';
import type { JarbisCandidate, JarbisCredentials, JarbisDevice, JarbisStatus, JarbisLightState } from '../types/jarbis';

const secondaryButton = 'inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700 transition hover:bg-slate-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600 disabled:cursor-not-allowed disabled:opacity-50';
const primaryButton = 'inline-flex min-h-10 items-center justify-center gap-2 rounded-xl bg-teal-700 px-4 py-2 text-sm font-bold text-white transition hover:bg-teal-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600 disabled:cursor-not-allowed disabled:opacity-50';
const dangerButton = 'inline-flex min-h-10 items-center justify-center rounded-xl border border-rose-200 px-3 py-2 text-sm font-bold text-rose-700 transition hover:bg-rose-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-600 disabled:cursor-not-allowed disabled:opacity-50';

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '요청을 처리하지 못했습니다.';
}

function kelvinFromMired(mired: number): number {
  return Math.max(2700, Math.min(6500, Math.round(1000000 / mired / 100) * 100));
}
function miredFromKelvin(kelvin: number): string {
  return String(Math.max(153, Math.min(500, Math.round(1000000 / kelvin))));
}
function hexColor(value: string | null | undefined): string {
  return value && /^#[0-9a-fA-F]{6}$/.test(value) ? value : '#ffffff';
}

function statusFailureHint(reason: JarbisLightState['reason']): string {
  switch (reason) {
    case 'HTTP_NO_CANDIDATE': return '등록된 전구의 주소를 찾지 못했습니다. 아래에서 기기를 다시 검색해 주세요.';
    case 'HTTP_FETCH_FAILED': return '전구의 로컬 상태 API에 접근하지 못했습니다. 전구가 켜져 있는지, 웹 관리 화면이 열리는지 확인해 주세요.';
    case 'HTTP_INVALID_STATE': return '전구가 응답했지만 현재 상태 형식이 일치하지 않습니다. 전구의 Tasmota 상태 정보를 확인해 주세요.';
    case 'HTTP_CLIENT_MISSING': return '공유기의 HTTP 조회 도구를 사용할 수 없습니다.';
    default: return '전구 상태를 확인하지 못했습니다. 기기 연결 설정을 확인한 뒤 다시 시도해 주세요.';
  }
}

function deviceIdForTopic(topic: string): string {
  return `tasmota_${topic.replace(/[^A-Za-z0-9_]/g, '_').slice(0, 32)}`;
}

// MQTT publish acknowledgements do not prove that a bulb has physically changed.
function pairFeedback(confirmed: boolean): string {
  return confirmed
    ? '전구에서 MQTT 온라인 응답을 확인했습니다. 전원을 조작해 실제 동작도 확인해 주세요.'
    : '전구 연결 정보를 저장했습니다. 온라인 응답은 아직 확인되지 않았습니다. 잠시 후 전원을 조작해 확인해 주세요.';
}

// The authenticated App owns these resources so revisiting this route can
// display the last successful snapshot immediately. No secrets are cached.
interface SmartHomeResource<T> {
  data: T | null;
  error: string | null;
  loading: boolean;
  replaceData: (value: T) => void;
}

// Inject operations: the authenticated router supplies RPC functions, while the
// public demo supplies only local fixture readers. This view never imports RPC.
export interface SmartHomeOperations {
  getJarbisStatus: () => Promise<JarbisStatus>;
  getJarbisDevices: () => Promise<{ devices: JarbisDevice[] }>;
  getJarbisCandidates: () => Promise<{ devices: JarbisCandidate[] }>;
  getJarbisLightState: (id: string, priority?: 'low' | 'normal' | 'high') => Promise<JarbisLightState>;
  scanJarbis: () => Promise<{ devices: JarbisCandidate[] }>;
  setJarbisEnabled: (enabled: boolean) => Promise<{ enabled: boolean }>;
  addJarbisDevice: (id: string, name: string, topic: string) => Promise<{ id: string; added: boolean }>;
  updateJarbisDevice: (id: string, name: string, enabled: boolean) => Promise<{ id: string; updated: boolean }>;
  removeJarbisDevice: (id: string) => Promise<{ id: string; removed: boolean }>;
  setJarbisLight: (id: string, capability: 'power' | 'brightness' | 'color' | 'color_temperature', value: string) => Promise<{ accepted: boolean }>;
  pairJarbisDevice: (id: string, adminPassword?: string, replaceExisting?: boolean) => Promise<{ id: string; configured: boolean; mqttConfirmed: boolean }>;
  getJarbisCredentials: () => Promise<JarbisCredentials>;
}

interface SmartHomePageProps {
  operations: SmartHomeOperations;
  /** Demo never executes a router action, not even a fixture mutation. */
  demo?: boolean;
  onDemoAction?: () => void;
  demoLightStates?: Readonly<Record<string, JarbisLightState>>;
  statusResource: SmartHomeResource<JarbisStatus>;
  devicesResource: SmartHomeResource<{ devices: JarbisDevice[] }>;
  candidatesResource: SmartHomeResource<{ devices: JarbisCandidate[] }>;
  /** Only used if the Jarbis service RPC failed; distinguishes missing and broken services. */
  appsStatus?: AppsInstallStatus | null;
  appsCatalog?: AppsCatalog | null;
  appsStatusError?: string | null;
  appsCatalogError?: string | null;
  onCheckInstallation?: () => void;
}

export function SmartHomePage({ statusResource, devicesResource, candidatesResource,
  operations, demo = false, onDemoAction, demoLightStates,
  appsStatus = null, appsCatalog = null, appsStatusError = null, appsCatalogError = null,
  onCheckInstallation }: SmartHomePageProps) {
  const {
    addJarbisDevice, getJarbisCandidates, getJarbisCredentials, getJarbisDevices, getJarbisLightState,
    getJarbisStatus, pairJarbisDevice, removeJarbisDevice, scanJarbis,
    setJarbisEnabled, setJarbisLight, updateJarbisDevice,
  } = operations;
  const demoAction = (): boolean => {
    if (!demo) return false;
    onDemoAction?.();
    return true;
  };
  const status = statusResource.data;
  const deviceData = devicesResource.data;
  const candidateData = candidatesResource.data;
  const devices = deviceData?.devices ?? [];
  const candidates = candidateData?.devices ?? [];
  const entry = demo ? 'ready' : smartHomeEntry(status, statusResource.error, appsStatus, appsCatalog, appsStatusError, appsCatalogError);
  // MQTT credentials are sensitive: retain them only while this page is mounted.
  const [credentials, setCredentials] = useState<JarbisCredentials | null>(null);
  const [reveal, setReveal] = useState(false);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [brightness, setBrightness] = useState<Record<string, number>>({});
  // A switch is still operable when the bulb has not reported its state.
  // Pending values represent the user's last request, never an observed state.
  const [requestedPower, setRequestedPower] = useState<Record<string, 'ON' | 'OFF'>>({});
  const [colors, setColors] = useState<Record<string, string>>({});
  const [kelvins, setKelvins] = useState<Record<string, number>>({});
  const [lightStates, setLightStates] = useState<Record<string, JarbisLightState>>(() => ({ ...demoLightStates }));
  const [checkingStates, setCheckingStates] = useState<Record<string, boolean>>({});
  const stateRequest = useRef(0);
  const discoverySection = useRef<HTMLElement | null>(null);
  const manageMenus = useRef<Record<string, HTMLDetailsElement | null>>({});
  const editingDevice = useRef<string | null>(null);
  const [pairTarget, setPairTarget] = useState<JarbisDevice | null>(null);
  const [pairOptionsVisible, setPairOptionsVisible] = useState(false);
  const [adminPassword, setAdminPassword] = useState('');
  const [replaceExisting, setReplaceExisting] = useState(false);

  // Native <details> does not close on outside clicks. Keep the menu as a
  // small popup, but dismiss it on outside pointer interaction and Escape.
  useEffect(() => {
    const dismiss = (target: Node | null) => {
      for (const menu of Object.values(manageMenus.current)) {
        if (menu?.open && (!target || !menu.contains(target))) menu.open = false;
      }
    };
    const onOutside = (event: PointerEvent) => dismiss(event.target instanceof Node ? event.target : null);
    const onEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') dismiss(null); };
    document.addEventListener('pointerdown', onOutside);
    document.addEventListener('keydown', onEscape);
    return () => {
      document.removeEventListener('pointerdown', onOutside);
      document.removeEventListener('keydown', onEscape);
    };
  }, []);

  // Match the other SmartSafeHub pages: transient successes must not keep
  // pushing device controls down, while errors remain until acknowledged.
  useEffect(() => {
    if (!message) return;
    const timeout = window.setTimeout(() => setMessage(''), 5000);
    return () => window.clearTimeout(timeout);
  }, [message]);

  // Independent requests: slow discovery must not delay service status or
  // the registered bulbs. Each successful result updates its own snapshot.
  const refresh = async () => {
    const [fresh] = await Promise.all([
      getJarbisStatus().then(result => { statusResource.replaceData(result); return result; }),
      getJarbisDevices().then(result => { devicesResource.replaceData(result); }),
      getJarbisCandidates().then(result => { candidatesResource.replaceData(result); }),
    ]);
    return fresh;
  };

  const refreshLight = async (id: string, background = false): Promise<JarbisLightState | null> => {
    if (demoAction()) return null;
    setCheckingStates(old => ({ ...old, [id]: true }));
    try {
      const state = await getJarbisLightState(id, background ? 'low' : 'high');
      setLightStates(old => ({ ...old, [id]: state }));
      if (state.observed && state.power !== null) {
        setRequestedPower(old => {
          if (old[id] !== state.power) return old;
          const next = { ...old };
          delete next[id];
          return next;
        });
      }
      if (state.observed && editingDevice.current !== id) {
        if (state.brightness !== null) setBrightness(old => ({ ...old, [id]: state.brightness! }));
        if (state.color) setColors(old => ({ ...old, [id]: state.color! }));
        if (state.colorTemperature !== null) setKelvins(old => ({ ...old, [id]: kelvinFromMired(state.colorTemperature!) }));
      }
      return state;
    } catch {
      setLightStates(old => ({ ...old, [id]: { id, observed: false, power: null,
        brightness: null, color: null, colorTemperature: null, reason: 'STATE_TIMEOUT_OR_UNAVAILABLE' } }));
      return null;
    } finally {
      setCheckingStates(old => ({ ...old, [id]: false }));
    }
  };

  // One bounded on-demand MQTT query per registered bulb, refreshed only while
  // this page is mounted. No background polling daemon or raw MQTT stream.
  const stateIds = devices.filter(device => device.enabled).slice(0, 6).map(device => device.id).join('|');
  useEffect(() => {
    if (demo || !status?.enabled || !status.brokerReady || !stateIds) return;
    const seq = ++stateRequest.current;
    const ids = stateIds.split('|');
    let polling = false;
    const poll = async () => {
      if (polling || seq !== stateRequest.current || document.visibilityState === 'hidden') return;
      polling = true;
      try {
        // At most two simultaneous MQTT queries on low-memory routers.
        for (let i = 0; i < ids.length && seq === stateRequest.current; i += 2) {
          await Promise.all(ids.slice(i, i + 2).map(id => refreshLight(id, true)));
        }
      } finally { polling = false; }
    };
    void poll();
    const timer = window.setInterval(poll, 30000);
    return () => { stateRequest.current++; window.clearInterval(timer); };
  }, [stateIds, status?.enabled, status?.brokerReady]);

  const sendLight = async (device: JarbisDevice,
    capability: 'power' | 'brightness' | 'color' | 'color_temperature', value: string): Promise<boolean> => {
    if (demoAction()) return false;
    editingDevice.current = null;
    // A skipped request is not a successful MQTT command.
    if (busy) return false;
    setBusy(`light:${device.id}`);
    setError('');
    setMessage('');
    try {
      await setJarbisLight(device.id, capability, value);
      const state = await refreshLight(device.id);
      const matched = state?.observed && (
        (capability === 'power' && state.power === value) ||
        (capability === 'brightness' && state.brightness === Number(value)) ||
        (capability === 'color' && state.color?.toLowerCase() === `#${value.toLowerCase()}`) ||
        (capability === 'color_temperature' && state.colorTemperature === Number(value))
      );
      setMessage(matched
        ? '전구의 상태 응답에서 변경된 값을 확인했습니다.'
        : '명령은 전송됐지만 요청한 상태로 변경됐는지는 아직 확인되지 않았습니다.');
      return true;
    } catch (cause) {
      setError(errorMessage(cause));
      return false;
    } finally { setBusy(''); }
  };

  const toggleBulbPower = async (device: JarbisDevice, currentlyOn: boolean) => {
    if (demoAction()) return;
    if (busy) return;
    const nextPower = currentlyOn ? 'OFF' : 'ON';
    const previous = requestedPower[device.id];
    setRequestedPower(old => ({ ...old, [device.id]: nextPower }));
    const sent = await sendLight(device, 'power', nextPower);
    if (!sent) {
      setRequestedPower(old => {
        if (old[device.id] !== nextPower) return old;
        const restored = { ...old };
        if (previous) restored[device.id] = previous;
        else delete restored[device.id];
        return restored;
      });
    }
  };

  const run = async (key: string, action: () => Promise<unknown>, ok: string, reload = true) => {
    if (demoAction()) return;
    setBusy(key);
    setError('');
    setMessage('');
    try {
      await action();
      if (reload) await refresh();
      setMessage(ok);
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy('');
    }
  };

  const retry = async () => {
    if (demoAction()) return;
    setBusy('refresh');
    setError('');
    try {
      await refresh();
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy('');
    }
  };

  const toggleEnabled = async () => {
    if (demoAction()) return;
    if (!status) return;
    const next = !status.enabled;
    await run('enabled', () => setJarbisEnabled(next), next
      ? '스마트홈 기능을 켰습니다.'
      : '스마트홈 기능을 껐습니다. 다른 서비스가 사용하는 MQTT Broker는 계속 실행될 수 있습니다.');
    setCredentials(null);
    setReveal(false);
  };

  const scan = async () => {
    if (demoAction()) return;
    await run('scan', async () => {
      const result = await scanJarbis();
      candidatesResource.replaceData(result);
    }, '기기 검색을 마쳤습니다.', false);
  };

  const closePair = () => {
    setPairTarget(null);
    setAdminPassword('');
    setReplaceExisting(false);
    setPairOptionsVisible(false);
  };

  const openPair = (device: JarbisDevice) => {
    if (demoAction()) return;
    setPairTarget(device);
    setAdminPassword('');
    setReplaceExisting(false);
    setPairOptionsVisible(false);
    setError('');
    setMessage('');
  };

  const pair = async (id: string, password = '', override = false) => {
    if (demoAction()) return;
    setBusy(`pair:${id}`);
    setError('');
    setMessage('');
    try {
      const result = await pairJarbisDevice(id, password, override);
      setMessage(pairFeedback(result.mqttConfirmed));
      closePair();
      await refresh();
    } catch (cause) {
      const explanation = errorMessage(cause);
      setError(explanation);
      // WebPassword is optional; only expose credentials/override controls
      // when required or deliberately requested by the user.
      if (/관리자 인증|비밀번호|기존 연결|다른 MQTT Broker/i.test(explanation)) {
        setPairOptionsVisible(true);
      }
    } finally {
      setBusy('');
    }
  };

  const add = async (candidate: JarbisCandidate) => {
    if (demoAction()) return;
    const id = deviceIdForTopic(candidate.topic);
    if (!candidate.topic) { setError('기기 연결 정보를 확인할 수 없습니다. 다시 검색해 주세요.'); return; }
    if (!window.confirm(`${candidate.name} 전구를 추가할까요? ${candidate.source === 'http' ? '추가 후 자동 연결을 시도합니다.' : '기존 MQTT 설정은 유지됩니다.'}`)) return;
    setBusy(`add:${id}`);
    setError('');
    setMessage('');
    try {
      await addJarbisDevice(id, candidate.name, candidate.topic);
      await refresh();
    } catch (cause) {
      setError(errorMessage(cause));
      setBusy('');
      return;
    }
    setBusy('');
    if (candidate.source !== 'http' || !candidate.ip) {
      setMessage('전구를 등록했습니다. 이미 설정된 MQTT 연결은 변경하지 않았습니다.');
      return;
    }
    // Registration persists on pairing failure, so retry does not add duplicates.
    setPairTarget({ id, name: candidate.name, kind: 'light', protocol: 'tasmota',
      topic: candidate.topic, enabled: true, capabilities: ['power', 'brightness'] });
    setPairOptionsVisible(false);
    await pair(id);
  };

  const retryPair = async () => {
    if (!pairTarget) return;
    const pass = adminPassword;
    await pair(pairTarget.id, pass, replaceExisting);
    setAdminPassword('');
  };

  const remove = async (device: JarbisDevice) => {
    if (demoAction()) return;
    if (!window.confirm(`${device.name}을(를) 목록에서 삭제할까요? 실제 전구 설정은 변경하지 않습니다.`)) return;
    await run(`remove:${device.id}`, () => removeJarbisDevice(device.id), '등록된 기기를 삭제했습니다.');
    if (pairTarget?.id === device.id) closePair();
  };

  const loadCredentials = async () => {
    if (demoAction()) return;
    if (credentials) { setCredentials(null); setReveal(false); return; }
    await run('credentials', async () => {
      setCredentials(await getJarbisCredentials());
      setReveal(false);
    }, '', false);
  };

  const ready = Boolean(status?.enabled && status.brokerReady);
  const availableCandidates = candidates.filter(candidate => !candidate.registered);

  if (entry !== 'ready') return <SmartHomeWelcome stage={entry} onRetry={() => {
    if (onCheckInstallation) onCheckInstallation();
    else void retry();
  }} />;

  return <div class="space-y-5">
    {demo ? <p role="status" class="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm font-semibold text-teal-800">
      스마트홈 체험 · 전구와 MQTT 상태는 모두 가상 예시이며 실제 제어·검색·연결은 실행되지 않습니다.
    </p> : null}
    {status && deviceData && devices.length === 0 ? <section aria-label="첫 스마트 전구 연결 안내" class="rounded-2xl border border-teal-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
      <p class="m-0 text-xs font-extrabold tracking-widest text-teal-700">스마트홈 시작하기 · 2단계</p>
      <h2 class="mt-2 mb-0 text-xl font-black text-slate-950">첫 번째 스마트 전구를 연결해 보세요</h2>
      <p class="mt-2 mb-0 text-sm leading-6 text-slate-600">Jarbis 설치가 완료되었습니다. Tasmota 전구를 공유기와 같은 Wi-Fi에 연결한 다음, 아래에서 검색하고 추가할 수 있습니다.</p>
      <div class="mt-4 grid gap-2 text-xs leading-5 text-slate-700 sm:grid-cols-3">
        <div class="rounded-lg bg-slate-50 p-3"><strong class="block text-slate-900">1. 전구 준비</strong>전원을 켜고 공유기 Wi-Fi에 연결</div>
        <div class="rounded-lg bg-slate-50 p-3"><strong class="block text-slate-900">2. 기기 검색</strong>검색된 전구의 이름 확인</div>
        <div class="rounded-lg bg-slate-50 p-3"><strong class="block text-slate-900">3. 연결 승인</strong>직접 추가한 전구만 제어</div>
      </div>
      <button class={`${primaryButton} mt-4`} type="button"
        onClick={() => discoverySection.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })}>전구 찾으러 가기</button>
      {!status.enabled ? <p class="mt-2 mb-0 text-xs text-slate-500">기기를 검색하려면 아래에서 스마트홈 사용을 먼저 켜 주세요.</p> : null}
    </section> : null}
    <SectionHeading eyebrow="Smart Home" title="스마트 전구" description="같은 Wi-Fi에 연결된 전구의 상태를 확인하고, 전원·밝기·색상·색온도를 조절합니다."
      action={<button class={secondaryButton} type="button" disabled={!!busy} onClick={() => void retry()}>
        <ReloadIcon class={`size-4 ${busy === 'refresh' ? 'animate-spin' : ''}`} />새로고침
      </button>} />

    {!status && statusResource.error ? <ErrorPanel message={statusResource.error}
      onRetry={() => void retry()} /> : !status ? <section aria-label="스마트홈 서비스 현황"
        aria-busy="true" class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
        <h2 class="m-0 text-base font-extrabold text-slate-950">스마트홈 사용</h2>
        <p role="status" class="mt-2 mb-0 text-sm text-slate-500">스마트홈 서비스 상태를 확인하고 있습니다…</p>
      </section> : <section aria-label="스마트홈 서비스 현황" class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <div class="grid gap-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
        <div class="flex min-w-0 items-center gap-3">
          <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700"><SettingsIcon class="size-5" /></span>
          <div class="min-w-0">
            <h2 class="m-0 text-base font-extrabold text-slate-950">스마트홈 사용</h2>
            <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">공유기에서 전구를 검색하고 제어합니다.</p>
          </div>
        </div>
        <div class="flex items-center gap-3 sm:justify-end">
          <span class="text-sm font-extrabold text-slate-700">{status?.enabled ? '켜짐' : '꺼짐'}</span>
          <button type="button" role="switch" aria-checked={Boolean(status?.enabled)} aria-label="스마트홈 기능 사용"
            disabled={!!busy || !status} onClick={() => void toggleEnabled()}
            class={`ssh-switch-control relative inline-flex shrink-0 items-center rounded-full border-0 p-0 transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600 disabled:cursor-not-allowed disabled:opacity-50 ${status?.enabled ? 'bg-teal-600' : 'bg-slate-300'}`}>
            <span aria-hidden="true" class={`ssh-switch-thumb absolute top-1 shadow-sm transition-[left] ${status?.enabled ? 'left-6' : 'left-1'}`} />
          </button>
        </div>
      </div>
      <div class="mt-4 grid gap-3 border-t border-slate-100 pt-4 sm:grid-cols-3">
        <div class="rounded-xl bg-slate-50 p-3">
          <p class="m-0 text-xs font-semibold text-slate-500">서비스 상태</p>
          <p class="mt-1 mb-0 text-lg font-extrabold text-slate-900">{status?.enabled ? '사용 중' : '중지됨'}</p>
        </div>
        <div class="rounded-xl bg-slate-50 p-3">
          <p class="m-0 text-xs font-semibold text-slate-500">전구 제어 연결</p>
          <p class={`mt-1 mb-0 text-lg font-extrabold ${ready ? 'text-teal-700' : status?.enabled ? 'text-rose-700' : 'text-slate-700'}`}>
            {!status?.enabled ? '대기 중' : status.brokerReady ? '연결 준비됨' : '연결 문제'}
          </p>
        </div>
        <div class="rounded-xl bg-slate-50 p-3">
          <p class="m-0 text-xs font-semibold text-slate-500">등록된 전구</p>
          <p class="mt-1 mb-0 text-lg font-extrabold text-slate-900">{deviceData ? devices.length : '—'}{deviceData ? <span class="ml-1 text-sm font-semibold text-slate-500">대</span> : null}</p>
        </div>
      </div>
      {status?.enabled && !status.brokerReady ? <div role="alert" class="mt-4 flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900">
        <AlertIcon class="mt-0.5 size-4 shrink-0" />전구 제어 연결을 확인하지 못했습니다. 잠시 후 새로고침하거나 고급 설정의 MQTT 연결 상태를 확인해 주세요.
      </div> : null}
      {!status?.enabled ? <p role="status" class="mt-3 mb-0 text-xs text-slate-500">스마트홈 기능을 켜면 기기를 검색하고 제어할 수 있습니다.</p> : null}
    </section>}

    {error ? <div role="alert" aria-live="assertive" class="flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">
      <AlertIcon class="mt-0.5 size-4 shrink-0" /><span class="min-w-0 flex-1">{error}</span>
      <button class="shrink-0 font-bold underline" type="button" onClick={() => setError('')}>닫기</button>
    </div> : null}
    {((status && statusResource.error) || devicesResource.error || candidatesResource.error) ? <div role="alert" class="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
      {devicesResource.error ? `등록된 전구 목록: ${devicesResource.error} ` : ''}
      {candidatesResource.error ? `발견된 전구 목록: ${candidatesResource.error} ` : ''}
      {status && statusResource.error ? `서비스 상태 갱신: ${statusResource.error}` : ''}
      <button class="ml-2 font-bold underline" type="button" disabled={!!busy} onClick={() => void retry()}>다시 확인</button>
    </div> : null}
    {message ? <div role="status" aria-live="polite" class="flex w-full items-start gap-2 rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">
      <CheckCircleIcon class="mt-0.5 size-4 shrink-0" />
      <span class="min-w-0 flex-1">{message}</span>
      <button class="shrink-0 rounded-lg px-1 text-xs font-bold underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600" type="button" aria-label="성공 알림 닫기" onClick={() => setMessage('')}>닫기</button>
    </div> : null}

    <section aria-label="등록된 전구" class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div><h2 class="m-0 text-base font-extrabold text-slate-950">내 전구</h2>
          <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">등록된 전구의 전원을 켜고 끄거나 밝기를 조절합니다.</p></div>
        <span class="rounded-full bg-slate-100 px-3 py-1.5 text-xs font-bold text-slate-600">{deviceData ? `${devices.length}대 등록` : '확인 중'}</span>
      </div>
      {!deviceData ? <div aria-busy={devicesResource.loading} role="status" class="mt-4 rounded-xl border border-dashed border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
        {devicesResource.error ? '전구 목록을 읽을 수 없습니다. 위에서 다시 확인해 주세요.' : '등록된 전구를 확인하고 있습니다…'}
      </div> : devices.length === 0 ? <div class="mt-4 rounded-xl border border-dashed border-slate-200 bg-slate-50 px-4 py-8 text-center">
        <DevicesIcon class="mx-auto size-8 text-slate-400" />
        <p class="mt-3 mb-1 text-sm font-extrabold text-slate-900">아직 등록된 전구가 없습니다</p>
        <p class="m-0 text-xs text-slate-500">아래에서 기기를 검색한 뒤 추가해 주세요.</p>
      </div> : <div class="mt-4 grid grid-cols-1 gap-3 lg:grid-cols-2">
        {devices.map(device => {
          const controlsDisabled = Boolean(busy) || !ready || !device.enabled;
          const activePair = pairTarget?.id === device.id;
          const observed = lightStates[device.id];
          const bulbOnline = observed?.observed === true;
          const pendingPower = requestedPower[device.id];
          const confirmedPower = observed?.observed === true ? observed.power : null;
          // When unknown, start from OFF so the first tap requests ON.
          const powerOn = pendingPower ? pendingPower === 'ON' : confirmedPower === 'ON';
          const powerNeedsConfirmation = !!pendingPower && pendingPower !== confirmedPower;
          const currentBrightness = observed?.brightness;
          const chosenBrightness = brightness[device.id] ?? currentBrightness ?? 50;
          const chosenKelvin = kelvins[device.id] ?? (observed?.colorTemperature ? kelvinFromMired(observed.colorTemperature) : 4000);
          const chosenColor = colors[device.id] ?? hexColor(observed?.color);
          return <article key={device.id} class="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 sm:p-5">
            <div class="flex min-w-0 items-start gap-3">
              <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700"><PowerIcon class="size-5" /></span>
              <div class="min-w-0 flex-1">
                <h3 class="m-0 truncate text-sm font-extrabold text-slate-950" title={device.name}>{device.name}</h3>
                <p class="mt-1 mb-0 break-all text-xs text-slate-500">Tasmota 스마트 전구</p>
              </div>
              <span class={`inline-flex shrink-0 rounded-full px-2.5 py-1 text-[0.7rem] font-bold ${!device.enabled ? 'bg-slate-100 text-slate-600' : bulbOnline ? 'bg-teal-50 text-teal-800' : 'bg-amber-50 text-amber-800'}`}>
                {!device.enabled ? '사용 중지' : bulbOnline
                  ? (observed.power === 'ON' ? '응답 확인 · 켜짐' : observed.power === 'OFF' ? '응답 확인 · 꺼짐' : '응답 확인 · 전원 미확인')
                  : !observed || checkingStates[device.id] ? '상태 확인 중' : '상태 응답 없음'}
              </span>
            </div>
            <div class="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs text-slate-500">
              <span>{bulbOnline ? `전구에서 확인한 현재 밝기: ${currentBrightness === null ? '미확인' : `${currentBrightness}%`}${observed?.source === 'http' ? ' · 로컬 직접 조회' : ''}` : statusFailureHint(observed?.reason)}</span>
              <button class={secondaryButton} type="button" disabled={!!busy || !ready || !device.enabled || Boolean(checkingStates[device.id])}
                onClick={() => void refreshLight(device.id)}>상태 새로고침</button>
            </div>
            <div aria-label="전구 조명 제어" class="mt-4 w-full min-w-0 space-y-3 rounded-xl bg-slate-50 p-3 sm:p-4">
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <p class="m-0 text-sm font-extrabold text-slate-900">전구 전원</p>
                  <p class="mt-1 mb-0 text-xs text-slate-500">
                    {powerNeedsConfirmation ? '전원 변경을 요청했습니다 · 실제 상태 확인 중'
                      : confirmedPower ? `전구 응답: ${confirmedPower === 'ON' ? '켜짐' : '꺼짐'}`
                      : '실제 전원 상태 미확인 · 스위치로 제어할 수 있습니다.'}
                  </p>
                </div>
                <div class="flex shrink-0 items-center gap-2">
                  <span class="text-xs font-bold text-slate-700">{pendingPower
                    ? (powerOn ? '켜기 요청' : '끄기 요청')
                    : confirmedPower === 'ON' ? '켜짐' : confirmedPower === 'OFF' ? '꺼짐' : '미확인'}</span>
                  <button type="button" role="switch" aria-checked={powerOn}
                    aria-label={`${device.name} 전원`} aria-busy={busy === `light:${device.id}`}
                    disabled={controlsDisabled}
                    onClick={() => void toggleBulbPower(device, powerOn)}
                    class={`ssh-switch-control relative inline-flex shrink-0 items-center rounded-full border-0 p-0 transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600 disabled:cursor-not-allowed disabled:opacity-50 ${powerOn ? 'bg-teal-600' : 'bg-slate-300'}`}>
                    <span aria-hidden="true" class={`ssh-switch-thumb absolute top-1 shadow-sm transition-[left] ${powerOn ? 'left-6' : 'left-1'}`} />
                  </button>
                </div>
              </div>
              <div class="flex min-w-0 flex-wrap items-center justify-between gap-2 border-t border-slate-200 pt-3">
                <label class="text-xs font-bold text-slate-700" for={`color-${device.id}`}>RGB 색상</label>
                <div class="flex items-center gap-2">
                  <input id={`color-${device.id}`} type="color" class="h-10 w-14 cursor-pointer rounded-lg border border-slate-200 bg-white p-1"
                    disabled={controlsDisabled || demo} value={chosenColor}
                    onInput={event => setColors(old => ({ ...old, [device.id]: event.currentTarget.value }))}
                    onChange={event => void sendLight(device, 'color', event.currentTarget.value.slice(1).toUpperCase())} />
                  <span class="font-mono text-xs text-slate-500">{chosenColor.toUpperCase()}</span>
                </div>
              </div>
              <div class="border-t border-slate-200 pt-3">
                <div class="flex items-center justify-between gap-2">
                  <label class="text-xs font-bold text-slate-700" for={`brightness-${device.id}`}>밝기 조절</label>
                  <span class="text-sm font-extrabold tabular-nums text-slate-900">{chosenBrightness}%</span>
                </div>
                <input id={`brightness-${device.id}`} type="range" min="0" max="100" step="5"
                  class="mt-2 w-full min-w-0 accent-teal-700" disabled={controlsDisabled || demo}
                  value={chosenBrightness} onPointerDown={() => { editingDevice.current = device.id; }}
                  onInput={event => setBrightness(old => ({ ...old, [device.id]: Number(event.currentTarget.value) }))}
                  onPointerUp={event => void sendLight(device, 'brightness', event.currentTarget.value)}
                  onKeyUp={event => { if (['ArrowLeft','ArrowRight','Home','End','PageUp','PageDown'].includes(event.key)) void sendLight(device, 'brightness', event.currentTarget.value); }} />
              </div>
              <div class="border-t border-slate-200 pt-3">
                <div class="flex items-center justify-between gap-2">
                  <label class="text-xs font-bold text-slate-700" for={`kelvin-${device.id}`}>색온도</label>
                  <span class="text-sm font-extrabold tabular-nums text-slate-900">{chosenKelvin}K</span>
                </div>
                <input id={`kelvin-${device.id}`} type="range" min="2700" max="6500" step="100"
                  class="mt-2 w-full min-w-0 accent-teal-700" disabled={controlsDisabled || demo}
                  value={chosenKelvin} onPointerDown={() => { editingDevice.current = device.id; }}
                  onInput={event => setKelvins(old => ({ ...old, [device.id]: Number(event.currentTarget.value) }))}
                  onPointerUp={event => void sendLight(device, 'color_temperature', miredFromKelvin(Number(event.currentTarget.value)))}
                  onKeyUp={event => { if (['ArrowLeft','ArrowRight','Home','End','PageUp','PageDown'].includes(event.key)) void sendLight(device, 'color_temperature', miredFromKelvin(Number(event.currentTarget.value))); }} />
                <div class="mt-1 flex items-center justify-between gap-2 text-xs text-slate-500"><span>따뜻한색 · 2700K</span><span>차가운색 · 6500K</span></div>
              </div>
            </div>
            <div class="mt-4 flex flex-wrap items-center gap-2 border-t border-slate-100 pt-3">
              <button class={secondaryButton} type="button" disabled={!!busy || !ready || !device.enabled}
                onClick={() => activePair ? closePair() : openPair(device)}>
                {activePair ? '연결 설정 닫기' : '전구 연결 설정'}
              </button>
              <details ref={element => { manageMenus.current[device.id] = element; }}
                class="relative z-20 min-w-0 text-sm text-slate-600">
                <summary class={`${secondaryButton} cursor-pointer list-none [&::-webkit-details-marker]:hidden`}>관리</summary>
                <div class="absolute left-0 top-full z-30 mt-2 flex w-64 max-w-[calc(100vw-3rem)] flex-col gap-2 rounded-xl border border-slate-200 bg-white p-3 shadow-xl">
                  <p class="m-0 break-all text-xs text-slate-500">기기 ID: {device.id}<br />Topic: {device.topic}</p>
                  <button class={secondaryButton} type="button" disabled={!!busy}
                    onClick={() => { manageMenus.current[device.id]!.open = false; void run(`update:${device.id}`, () => updateJarbisDevice(device.id, device.name, !device.enabled), device.enabled ? '기기를 사용 중지했습니다.' : '기기를 다시 사용합니다.'); }}>
                    {device.enabled ? '기기 사용 중지' : '기기 다시 사용'}
                  </button>
                  <button class={dangerButton} type="button" disabled={!!busy} onClick={() => { manageMenus.current[device.id]!.open = false; void remove(device); }}>기기 삭제</button>
                </div>
              </details>
            </div>
            {activePair ? <div aria-label="전구 자동 연결 설정" class="mt-4 space-y-3 rounded-xl border border-teal-200 bg-white p-4">
              <h4 class="m-0 text-sm font-extrabold text-slate-900">{device.name} 연결 설정</h4>
              <p class="m-0 text-xs leading-5 text-slate-600">공유기가 필요한 설정을 전구에 자동으로 전달합니다. 보통 별도 입력이 필요하지 않습니다.</p>
              <button class="text-left text-xs font-bold text-teal-800 underline" type="button" onClick={() => setPairOptionsVisible(!pairOptionsVisible)}>
                {pairOptionsVisible ? '추가 연결 옵션 닫기' : '연결이 안 되나요? 비밀번호·기존 연결 옵션'}
              </button>
              {pairOptionsVisible ? <div class="space-y-3 rounded-xl border border-slate-200 bg-white p-3">
                <div>
                  <label class="block text-xs font-bold text-slate-700" for="jarbis-admin-password">전구 웹 관리자 비밀번호 (설정한 경우에만)</label>
                  <input id="jarbis-admin-password" class="mt-2 min-h-10 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900"
                    type="password" autoComplete="off" value={adminPassword}
                    onInput={event => setAdminPassword(event.currentTarget.value)} placeholder="설정하지 않았다면 비워두세요" />
                  <p class="mt-2 mb-0 text-xs leading-5 text-slate-600">이 비밀번호는 <strong>전구의 Tasmota 관리 화면 → Configuration → Configure Other → Web Admin Password</strong>에서 설정합니다. 공유기 로그인 비밀번호나 MQTT 비밀번호가 아닙니다.</p>
                </div>
                <label class="flex items-start gap-2 text-xs leading-5 text-slate-700">
                  <input class="mt-1" type="checkbox" checked={replaceExisting}
                    onChange={event => setReplaceExisting(event.currentTarget.checked)} />
                  다른 스마트홈 서비스와의 기존 연결을 변경하는 데 동의합니다.
                </label>
                <p class="m-0 text-xs text-amber-800">전구 설정은 암호화되지 않은 Tasmota HTTP를 통해 전달됩니다. 신뢰할 수 있는 내부 네트워크에서만 사용하세요. 비밀번호는 저장하지 않습니다.</p>
              </div> : null}
              <div class="flex flex-wrap gap-2">
                <button class={primaryButton} type="button" disabled={!!busy || !ready}
                  onClick={() => void retryPair()}>{busy.startsWith('pair:') ? '전구 연결 중…' : '자동 연결 시작'}</button>
                <button class={secondaryButton} type="button" disabled={!!busy} onClick={closePair}>취소</button>
              </div>
            </div> : null}
          </article>;
        })}
      </div>}
      <p class="mt-3 mb-0 text-xs leading-5 text-slate-500">전원·밝기·색상은 전구에서 직접 확인한 상태만 실제 값으로 표시합니다. MQTT 응답이 없을 때는 검증된 내부망 HTTP 조회를 시도합니다. 확인되지 않은 값은 실제 상태로 표시하지 않습니다.</p>
    </section>

    <section ref={discoverySection} aria-label="새 전구 찾기" class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="m-0 text-base font-extrabold text-slate-950">새 전구 찾기</h2>
          <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">전구를 같은 Wi-Fi에 연결한 뒤 검색하세요. 검색에 최대 25초 정도 걸릴 수 있습니다.</p>
        </div>
        <button class={primaryButton} type="button" disabled={!!busy || !status?.enabled}
          onClick={() => void scan()} aria-busy={busy === 'scan'}>
          <SearchIcon class={`size-4 ${busy === 'scan' ? 'animate-pulse' : ''}`} />{busy === 'scan' ? '검색 중…' : '기기 검색'}
        </button>
      </div>
      {!candidateData ? <div role="status" aria-busy={candidatesResource.loading} class="mt-4 rounded-xl border border-dashed border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
        {candidatesResource.error ? '발견된 전구 목록을 읽을 수 없습니다. 위에서 다시 확인해 주세요.' : '검색된 전구 목록을 확인하고 있습니다…'}
      </div> : availableCandidates.length === 0 ? <div class="mt-4 rounded-xl border border-dashed border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
        {busy === 'scan' ? '근처에서 Tasmota 전구를 찾고 있습니다…' : candidates.length > 0 ? '발견된 전구는 모두 등록되어 있습니다.' : '아직 발견된 전구가 없습니다. 기기가 같은 네트워크에 연결돼 있는지 확인해 주세요.'}
      </div> : <ul class="mt-4 space-y-3 p-0" aria-label="검색된 기기">
        {availableCandidates.map(candidate => <li key={`${candidate.topic}:${candidate.ip}:${candidate.source}`} class="flex flex-wrap items-center gap-3 rounded-xl border border-slate-200 p-3 sm:p-4">
          <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-600"><DevicesIcon class="size-5" /></span>
          <div class="min-w-0 flex-1">
            <strong class="block text-sm text-slate-900">{candidate.name}</strong>
            <p class="mt-1 mb-0 break-all text-xs text-slate-500">{candidate.ip || '주소 미확인'} · Tasmota</p>
            <p class="mt-1 mb-0 text-xs text-slate-500">{candidate.source === 'http' ? 'Wi-Fi에서 발견' : 'MQTT에서 발견'}</p>
          </div>
          <button class={primaryButton} type="button"
            disabled={!!busy || !status?.enabled || candidate.registered || !candidate.topic}
            onClick={() => void add(candidate)}>
            {candidate.registered ? '등록됨' : candidate.topic ? (candidate.source === 'http' ? '추가 및 자동 연결' : '기기 추가') : '추가 불가'}
          </button>
        </li>)}
      </ul>}
    </section>

    <details class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <summary class="flex cursor-pointer items-center gap-2 text-sm font-extrabold text-slate-800 focus-visible:outline-2 focus-visible:outline-teal-600">
        <KeyIcon class="size-4 text-slate-500" />고급 설정 · 연결 진단
      </summary>
      <div class="mt-4 space-y-3 border-t border-slate-100 pt-4 text-sm text-slate-700">
        <div class="grid gap-2 sm:grid-cols-2">
          <div class="rounded-xl bg-slate-50 p-3"><p class="m-0 text-xs text-slate-500">홈 자동화 엔진</p><p class="mt-1 mb-0 font-bold">Jarbis {status?.version || '-'}</p></div>
          <div class="rounded-xl bg-slate-50 p-3"><p class="m-0 text-xs text-slate-500">메시지 서버</p><p class="mt-1 mb-0 font-bold">{status?.brokerMode === 'managed' ? '공유기 내장 MQTT' : '외부 MQTT'} · {ready ? '연결 준비됨' : '상태 확인 필요'}</p></div>
        </div>
        {!demo && status?.enabled && status.brokerMode === 'managed' ? <div class="rounded-xl border border-slate-200 p-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <strong class="text-sm text-slate-900">수동 MQTT 인증 정보</strong>
            <button class={secondaryButton} type="button" disabled={!!busy} onClick={() => void loadCredentials()}>
              {credentials ? '인증 정보 숨기기' : '인증 정보 확인'}
            </button>
          </div>
          <p class="mt-2 mb-0 text-xs leading-5 text-slate-500">자동 연결에는 필요하지 않습니다. 전구 설정을 수동 확인할 때만 열어보세요.</p>
          {credentials ? <div class="mt-3 space-y-3 rounded-lg bg-slate-50 p-3">
            <p class="m-0 break-all text-xs">호스트: <strong>{credentials.host}</strong> · 포트: <strong>{credentials.port}</strong></p>
            <p class="m-0 text-xs">사용자: <strong>{credentials.username}</strong></p>
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-xs font-semibold">MQTT 비밀번호</span>
              {reveal
                ? <input class="min-w-0 flex-1 rounded-lg border border-slate-300 bg-white px-2 py-2 font-mono text-xs" type="text" readOnly value={credentials.secret} aria-label="MQTT 비밀번호" />
                : <input class="min-w-0 flex-1 rounded-lg border border-slate-300 bg-white px-2 py-2 font-mono text-xs" type="password" readOnly value={credentials.secret} aria-label="MQTT 비밀번호" />}
              <button class={secondaryButton} type="button" onClick={() => setReveal(!reveal)}>{reveal ? '가리기' : '보기'}</button>
            </div>
            <p class="m-0 text-xs text-slate-500">이 비밀번호는 전구 웹 관리자 비밀번호와 다릅니다. 다른 사람과 공유하지 마세요.</p>
          </div> : null}
        </div> : null}
        <p class="m-0 text-xs leading-5 text-slate-500">기기 설정을 자동 변경하지 않고, 기기 추가와 연결 작업은 사용자가 승인한 경우에만 실행합니다.</p>
      </div>
    </details>
  </div>;
}
