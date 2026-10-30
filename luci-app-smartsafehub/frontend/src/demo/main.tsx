import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';

import { AppShell } from '../components/AppShell';
import { DEMO_ROUTES } from '../app/routes';
import { ActivityPage } from '../pages/ActivityPage';
import { AppsPage } from '../pages/AppsPage';
import { SmartSafeHubAccountPage } from '../pages/SmartSafeHubAccountPage';
import { WanPage } from '../pages/WanPage';
import { LanPage } from '../pages/LanPage';
import { WifiPage } from '../pages/WifiPage';
import { SafeShieldRulesPage } from '../pages/SafeShieldRulesPage';
import { UpdatePage } from '../pages/UpdatePage';
import { useHashRoute } from '../hooks/useHashRoute';
import { usePageTabs } from '../hooks/usePageTabs';
import { PageTabs } from '../components/PageTabs';
import { ConnectedDevicesPage } from '../pages/ConnectedDevicesPage';
import { HomePage } from '../pages/HomePage';
import { SafeShieldPage } from '../pages/SafeShieldPage';
import {
  demoActivity, demoDevices, demoFirmware, demoHealth, demoLan,
  demoSafeShield, demoStatistics, demoStatus, demoUpdates,
  demoWan, demoWifi, demoRules, demoWifiQr, demoGuestWifiQr,
  demoAccount, demoApps, demoAppsStatus, demoAppsMetrics,
} from './data';
import '../styles/app.css';

// This entry MUST NOT import App, auth/session, or api/*. No backend is involved.
const ALLOWED_ROUTES = new Set(DEMO_ROUTES);

function DemoApp() {
  const currentRoute = useHashRoute();
  const tabs = usePageTabs();
  const route = ALLOWED_ROUTES.has(currentRoute) ? currentRoute : 'home';
  const [notice, setNotice] = useState('');
  useEffect(() => {
    if (!ALLOWED_ROUTES.has(currentRoute)) {
      window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}#home`);
      setNotice('해당 기능은 현재 데모에서 제공하지 않습니다.');
    }
  }, [currentRoute]);
  const readonlyNotice = () => setNotice('체험 모드에서는 실제 계정 연결, 앱 설치·제거·실행 및 공유기 설정 변경을 수행하지 않습니다.');
  const dismiss = () => setNotice('');
  const reset = () => setNotice('예시 데이터가 표시되고 있습니다. 실제 공유기에는 연결되지 않습니다.');

  // All callbacks are local-only. Never load router hooks or the authenticated App.
  const disabledAction = async (): Promise<boolean> => {
    readonlyNotice();
    return false;
  };
  const firmware = {
    action: null, actionError: null, data: demoFirmware, error: null,
    loading: false, message: null, reconnecting: false, uploadProgress: null,
    check: readonlyNotice, discard: disabledAction, dismissFeedback: dismiss,
    install: disabledAction, prepare: readonlyNotice, refresh: reset, upload: disabledAction,
  };

  let content;
  switch (route) {
    case 'account':
      content = <SmartSafeHubAccountPage data={demoAccount} error={null} loading={false}
        pairingBusy={false} refreshing={false} syncError={null} demo
        onDemoAction={readonlyNotice} onRequestPairing={async () => { readonlyNotice(); return null; }}
        onRetry={reset} />;
      break;
    case 'apps':
      content = <AppsPage data={demoApps} error={null} loading={false} refreshing={false}
        installStatus={demoAppsStatus} metrics={demoAppsMetrics} statusError={null}
        demo onDemoAction={readonlyNotice} onRefreshStatus={reset} onRetry={reset}
        onInstall={async () => { readonlyNotice(); }}
        onRemove={async () => { readonlyNotice(); }}
        onUpdate={async () => { readonlyNotice(); }} />;
      break;
    case 'activity':
      content = <ActivityPage actionError={null} actionMessage={null} data={demoActivity}
        error={null} loading={false} onDismissActionFeedback={dismiss} onRetry={reset}
        onSetCloudSync={readonlyNotice} savingCloudSync={false} />;
      break;
    case 'network':
      content = <div class="min-w-0">
        <PageTabs active={tabs.network} label="네트워크 설정 메뉴" tabs={[
          { id: 'internet', label: '인터넷 연결', href: '#network' },
          { id: 'lan', label: 'LAN 및 DHCP', href: '#network/lan' },
        ]} />
        <div aria-label="인터넷 연결 설정" aria-labelledby="internet-tab" hidden={tabs.network !== 'internet'} id="internet-panel" role="tabpanel"><WanPage action={null} data={demoWan} error={null}
          feedback={null} loading={false} onDismissFeedback={dismiss} onReconnect={readonlyNotice}
          onRetry={reset} onSave={disabledAction} /></div>
        <div aria-label="내부 네트워크 설정" aria-labelledby="lan-tab" hidden={tabs.network !== 'lan'} id="lan-panel" role="tabpanel">
          <LanPage action={null} data={demoLan} error={null} feedback={null} loading={false}
            onApplyRecommendation={disabledAction} onDismissFeedback={dismiss} onRetry={reset}
            onSave={disabledAction} />
        </div>
      </div>;
      break;
    case 'wifi':
      content = <WifiPage data={demoWifi} error={null} feedback={null} loading={false}
        updatingSection={null} onDismissFeedback={dismiss} onRetry={reset}
        onUpdate={disabledAction} onUpdateGuest={disabledAction}
        onLoadQr={demoWifiQr} onLoadGuestQr={demoGuestWifiQr} />;
      break;
    case 'rules':
      content = <SafeShieldRulesPage action={null} data={demoRules} error={null}
        feedback={null} loading={false} onAddRule={disabledAction} onDeleteRule={disabledAction}
        onDismissFeedback={dismiss} onRetry={reset} />;
      break;
    case 'system':
      content = <UpdatePage action={null} actionError={null} data={demoUpdates}
        error={null} firmware={firmware} loading={false} message={null}
        onCheck={readonlyNotice} onDismissFeedback={dismiss} onInstall={readonlyNotice}
        onRetry={reset} onSaveSettings={disabledAction} />;
      break;
    case 'devices':
      content = <ConnectedDevicesPage data={demoDevices} error={null} loading={false} onRetry={reset} />;
      break;
    case 'safeshield':
      content = (
        <SafeShieldPage
          action={null} actionError={null} actionMessage={null} data={demoSafeShield}
          error={null} loading={false} statistics={demoStatistics} statisticsError={null}
          statisticsLoading={false} statisticsRefreshing={false} onDismissFeedback={dismiss}
          onRefreshBlocklist={readonlyNotice} onRetry={reset} onRetryStatistics={reset}
          onSetEnabled={readonlyNotice} onSetStatisticsEnabled={readonlyNotice}
        />
      );
      break;
    default:
      content = (
        <HomePage
          accountRegistered={demoAccount.accountRegistered} activity={demoActivity} activityError={null} activityLoading={false}
          data={demoStatus} devices={demoDevices} devicesError={null} devicesLoading={false}
          error={null} firmware={demoFirmware} firmwareError={null} firmwareLoading={false}
          health={demoHealth} healthError={null} healthLoading={false}
          lan={demoLan} lanError={null} lanLoading={false} loading={false} onRetry={reset}
          safeshield={demoSafeShield} safeshieldError={null} safeshieldLoading={false}
          statistics={demoStatistics} statisticsError={null} statisticsLoading={false}
          statisticsRefreshing={false} updates={demoUpdates} updatesError={null} updatesLoading={false}
        />
      );
  }

  return (
    <AppShell accountRegistered={demoAccount.accountRegistered} demo loading={false} onRefresh={reset} refreshing={false} route={route} updateCount={0}>
      <div role="status" class="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm font-semibold text-teal-800">
        <span>체험 모드 · 표시되는 기기와 보호 통계는 모두 예시입니다.</span>
        <a class="font-extrabold underline" href="/devices/">지원 기기 살펴보기 →</a>
      </div>
      {notice ? (
        <div role="alert" class="mb-5 flex items-center justify-between gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm font-semibold text-amber-900">
          {notice}
          <button aria-label="안내 닫기" class="font-black" onClick={dismiss} type="button">✕</button>
        </div>
      ) : null}
      {content}
    </AppShell>
  );
}

// The real router app mounts into a shadow root too. Isolate Tailwind Preflight
// from Django's global CSS and keep the same actual router components/styling.
const host = document.getElementById('smartsafehub-demo-root');
if (host) {
  const shadow = host.attachShadow({ mode: 'open' });
  const stylesheet = document.createElement('link');
  stylesheet.rel = 'stylesheet';
  stylesheet.href = host.dataset.demoCss || '/static/router-demo/demo.css';
  shadow.appendChild(stylesheet);
  const mount = document.createElement('div');
  mount.className = 'smartsafehub-shadow-root';
  shadow.appendChild(mount);
  render(<DemoApp />, mount);
}
