import type { ComponentChildren } from 'preact';
import { useEffect, useRef } from 'preact/hooks';

import { fetchAppsCatalog, fetchAppsStatus, fetchAppsMetrics, refreshAppsCatalog, refreshAppsStatus, refreshAppsMetrics, installVerifiedApp, updateVerifiedApp, removeVerifiedApp, fetchGuestWifiQr, fetchRecommendedRulesStatus, refreshRecommendedRulesStatus,
  revokeRecommendedRule, fetchWifiQr, initializeSystemTimezone } from '../api/smartsafehub';

import { AppShell } from '../components/AppShell';
import { PageTabs } from '../components/PageTabs';
import { useActivityHistory } from '../hooks/useActivityHistory';
import { useAsyncResource } from '../hooks/useAsyncResource';
import type { AppsCatalog, AppsInstallStatus, AppsMetrics } from '../types/apps';
import { useConfigurationBackup } from '../hooks/useConfigurationBackup';
import { useConnectedDevices } from '../hooks/useConnectedDevices';
import { useFirmwareUpdates } from '../hooks/useFirmwareUpdates';
import { useHashRoute } from '../hooks/useHashRoute';
import { usePageTabs } from '../hooks/usePageTabs';
import { useHealth } from '../hooks/useHealth';
import { useIptv } from '../hooks/useIptv';
import { useLan } from '../hooks/useLan';
import { useWan } from '../hooks/useWan';
import { useSafeShieldActions } from '../hooks/useSafeShieldActions';
import { useSafeShieldRules } from '../hooks/useSafeShieldRules';
import { useSafeShieldStatistics } from '../hooks/useSafeShieldStatistics';
import { useSafeShieldStatus } from '../hooks/useSafeShieldStatus';
import { useSoftwareUpdates } from '../hooks/useSoftwareUpdates';
import { useStatus } from '../hooks/useStatus';
import { useScheduledRebootSettings } from '../hooks/useScheduledRebootSettings';
import { useSystemActions } from '../hooks/useSystemActions';
import { useSystemTimeSettings } from '../hooks/useSystemTimeSettings';
import { useDeviceRegistration } from '../hooks/useDeviceRegistration';
import { useDashboardAccountStatus } from '../hooks/useDashboardAccountStatus';
import { useWifi } from '../hooks/useWifi';
import { ActivityPage } from '../pages/ActivityPage';
import { AppsPage } from '../pages/AppsPage';
import { ConnectedDevicesPage } from '../pages/ConnectedDevicesPage';
import { HomePage } from '../pages/HomePage';
import { IptvPage } from '../pages/IptvPage';
import { LanPage } from '../pages/LanPage';
import { WanPage } from '../pages/WanPage';
import { SafeShieldPage } from '../pages/SafeShieldPage';
import { SafeShieldRulesPage } from '../pages/SafeShieldRulesPage';
import { SettingsPage } from '../pages/SettingsPage';
import { SmartSafeHubAccountPage } from '../pages/SmartSafeHubAccountPage';
import { UpdatePage } from '../pages/UpdatePage';
import { WifiPage } from '../pages/WifiPage';
import { browserTimezone } from '../utils/timezone';

interface AppProps {
  onAdministratorPasswordChanged: () => void;
}

export function App({ onAdministratorPasswordChanged }: AppProps) {
  const route = useHashRoute();
  const tabs = usePageTabs();
  const configurationBackup = useConfigurationBackup();
  const activity = useActivityHistory(route === 'activity');
  const apps = useAsyncResource<AppsCatalog>({
    active: route === 'apps',
    fallbackError: '검증된 앱 목록을 불러오지 못했습니다.',
    loader: fetchAppsCatalog,
    pollInterval: (data) => data?.refreshing ? 2_000 : !data?.ready ? (data?.refreshFailed ? 15_000 : 2_000) : 60_000,
    staleTimeMs: 2_000,
  });
  const appsStatus = useAsyncResource<AppsInstallStatus>({
    active: route === 'apps',
    fallbackError: '앱 설치 상태를 불러오지 못했습니다.',
    loader: fetchAppsStatus,
    pollInterval: (data) => !data?.ready || data?.refreshing ? 2_000 : data?.job.phase === 'running' || data?.job.phase === 'starting' || data?.restore?.phase === 'running' || data?.restore?.phase === 'starting' ? 3000 : 12000,
    staleTimeMs: 3000,
  });
  // Optional metrics never participate in the status/error guard for buttons.
  const appsMetrics = useAsyncResource<AppsMetrics>({
    active: route === 'apps',
    fallbackError: '저장 공간 정보를 확인하지 못했습니다.',
    loader: fetchAppsMetrics,
    pollInterval: (data) => data?.refreshing || !data?.ready ? 3_000 : 60000,
    staleTimeMs: 5000,
  });
  const status = useStatus(route === 'home' || route === 'settings');
  const updates = useSoftwareUpdates(true);
  const firmware = useFirmwareUpdates(true);
  const wan = useWan(route === 'network');
  const lan = useLan(route === 'home' || route === 'network');
  const iptv = useIptv(route === 'iptv');
  const wifi = useWifi(route === 'wifi');
  const dashboardDevices = useConnectedDevices(route === 'home', false);
  const devices = useConnectedDevices(route === 'devices');
  // Both views consume the same resource: switching pages must not re-query RPC.
  const safeshield = useSafeShieldStatus(route === 'home' || route === 'safeshield');
  const safeshieldStatistics = useSafeShieldStatistics(route === 'home' || route === 'safeshield', route === 'safeshield');
  const dashboardSafeShield = safeshield;
  const dashboardSafeShieldStatistics = safeshieldStatistics;
  const rules = useSafeShieldRules(route === 'rules');
  const deviceRegistration = useDeviceRegistration(route === 'account');
  const dashboardAccountRegistered = useDashboardAccountStatus(
    route === 'account',
    deviceRegistration.data?.accountRegistered ?? null,
  );
  const systemActions = useSystemActions(status.data);
  const health = useHealth(route === 'home' || route === 'settings');
  const scheduledReboot = useScheduledRebootSettings(route === 'settings');
  const systemTime = useSystemTimeSettings(route === 'settings');

  useEffect(() => {
    const detectedTimezone = browserTimezone();
    if (!detectedTimezone) {
      return;
    }

    void initializeSystemTimezone(detectedTimezone)
      .then((result) => {
        if (result.applied && route === 'settings') {
          void systemTime.refresh();
        }
      })
      .catch(() => {
        // Automatic initialization is best-effort. Manual timezone controls in
        // Settings remain available when browser detection or RPC application
        // cannot complete.
      });
  }, []);

  // A completed install/remove invalidates both APK snapshots even if their
  // background TTL has not elapsed. Never force them on every render/poll.
  const appsJobId = appsStatus.data?.job.operationId;
  const appsJobPhase = appsStatus.data?.job.phase;
  const appsRestorePhase = appsStatus.data?.restore?.phase;
  const previousAppsRefreshKey = useRef('');
  useEffect(() => {
    if (route !== 'apps' || (appsJobPhase !== 'success' && appsRestorePhase !== 'success')) return;
    const key = `${appsJobId ?? ''}:${appsJobPhase}:${appsRestorePhase ?? ''}`;
    if (key === previousAppsRefreshKey.current) return;
    previousAppsRefreshKey.current = key;
    void Promise.allSettled([refreshAppsStatus(), refreshAppsMetrics()]).then(() => {
      void appsStatus.refresh();
      void appsMetrics.refresh();
    });
  }, [route, appsJobId, appsJobPhase, appsRestorePhase]);

  const safeshieldActions = useSafeShieldActions(
    safeshield.refresh,
    safeshieldStatistics.refresh,
  );

  const current =
    route === 'activity'
      ? activity
      : route === 'network'
        ? wan
        : route === 'wifi'
          ? wifi
          : route === 'iptv'
            ? iptv
            : route === 'devices'
              ? devices
              : route === 'safeshield'
                ? safeshield
                : route === 'rules'
                  ? rules
                  : route === 'account'
                    ? deviceRegistration
                    : route === 'apps'
                      ? apps
                      : route === 'system'
                        ? updates
                        : status;

  let content: ComponentChildren;

  switch (route) {
    case 'apps':
      content = (
        <AppsPage
          data={apps.data?.ready === false ? null : apps.data}
          error={apps.error ?? (apps.data?.refreshFailed && !apps.data?.ready ? '앱 목록 갱신에 실패했습니다. 서버 연결을 확인해 주세요.' : null)}
          loading={apps.loading || (!!apps.data && !apps.data.ready && !apps.data.refreshFailed)}
          refreshing={apps.refreshing || !!apps.data?.refreshing}
          onRetry={() => void refreshAppsCatalog().then(() => apps.refresh()).then(() =>
            Promise.all([appsStatus.refresh(), appsMetrics.refresh()])).catch(() => apps.refresh())}
          installStatus={appsStatus.data?.ready === false ? null : appsStatus.data}
          metrics={appsMetrics.data}
          statusError={appsStatus.error ?? (appsStatus.data?.ready === false ? '설치 상태를 확인하고 있습니다.' : null)}
          onRefreshStatus={() => void appsStatus.refresh()}
          onInstall={async (id) => {
            await installVerifiedApp(id);
            await appsStatus.refresh();
          }}
          onUpdate={async (id) => {
            await updateVerifiedApp(id);
            await appsStatus.refresh();
          }}
          onRemove={async (id) => {
            await removeVerifiedApp(id);
            await appsStatus.refresh();
          }}
        />
      );
      break;

    case 'network':
      content = (
        <div class="min-w-0">
          <PageTabs
            active={tabs.network === 'internet' ? 'internet' : 'lan'}
            label="네트워크 설정 메뉴"
            tabs={[
              { id: 'internet', label: '인터넷 연결', href: '#network' },
              { id: 'lan', label: 'LAN 및 DHCP', href: '#network/lan' },
            ]}
          />
          <div
            aria-label="인터넷 연결 설정"
            aria-labelledby="internet-tab"
            class="min-w-0"
            hidden={tabs.network !== 'internet'}
            id="internet-panel"
            role="tabpanel"
          >
            <WanPage
              action={wan.action}
              data={wan.data}
              error={wan.error}
              feedback={wan.feedback}
              loading={wan.loading}
              onDismissFeedback={wan.dismissFeedback}
              onReconnect={() => void wan.reconnect()}
              onRetry={() => void wan.refresh()}
              onSave={wan.save}
            />
          </div>
          <div
            aria-label="내부 네트워크 설정"
            aria-labelledby="lan-tab"
            class="min-w-0"
            hidden={tabs.network !== 'lan'}
            id="lan-panel"
            role="tabpanel"
          >
            <LanPage
              action={lan.action}
              data={lan.data}
              error={lan.error}
              feedback={lan.feedback}
              loading={lan.loading}
              onApplyRecommendation={lan.applyRecommendation}
              onDismissFeedback={lan.dismissFeedback}
              onRetry={() => void lan.refresh()}
              onSave={lan.save}
            />
          </div>
        </div>
      );
      break;

    case 'activity':
      content = (
        <ActivityPage
          actionError={activity.actionError}
          actionMessage={activity.actionMessage}
          data={activity.data}
          error={activity.error}
          loading={activity.loading}
          onDismissActionFeedback={activity.dismissActionFeedback}
          onRetry={() => void activity.refresh()}
          onSetCloudSync={(enabled) => void activity.setCloudSyncEnabled(enabled)}
          savingCloudSync={activity.savingCloudSync}
        />
      );
      break;

    case 'wifi':
      content = (
        <WifiPage
          data={wifi.data}
          error={wifi.error}
          feedback={wifi.feedback}
          loading={wifi.loading}
          onDismissFeedback={wifi.dismissFeedback}
          onRetry={() => void wifi.refresh()}
          onUpdate={wifi.update}
          onUpdateGuest={wifi.updateGuest}
          onLoadQr={fetchWifiQr}
          onLoadGuestQr={fetchGuestWifiQr}
          updatingSection={wifi.updatingSection}
        />
      );
      break;

    case 'iptv':
      content = (
        <IptvPage
          data={iptv.data}
          error={iptv.error}
          feedback={iptv.feedback}
          loading={iptv.loading}
          onDismissFeedback={iptv.dismissFeedback}
          onRetry={() => void iptv.refresh()}
          onSave={iptv.save}
          saving={iptv.saving}
        />
      );
      break;

    case 'devices':
      content = (
        <ConnectedDevicesPage
          data={devices.data}
          error={devices.error}
          loading={devices.loading}
          onRetry={() => void devices.refresh()}
        />
      );
      break;

    case 'account':
      content = (
        <SmartSafeHubAccountPage
          data={deviceRegistration.data}
          error={deviceRegistration.error}
          loading={deviceRegistration.loading}
          pairingBusy={deviceRegistration.pairingBusy}
          refreshing={deviceRegistration.refreshing}
          syncError={deviceRegistration.syncError}
          onRequestPairing={deviceRegistration.requestPairing}
          onRetry={() => void deviceRegistration.refresh()}
        />
      );
      break;

    case 'system':
      content = (
        <UpdatePage
          action={updates.action}
          actionError={updates.actionError}
          data={updates.data}
          error={updates.error}
          firmware={firmware}
          loading={updates.loading}
          message={updates.message}
          onCheck={() => void updates.check()}
          onDismissFeedback={updates.dismissFeedback}
          onInstall={() => void updates.install()}
          onRetry={() => void updates.refresh()}
          onSaveSettings={updates.saveSettings}
        />
      );
      break;

    case 'settings':
      content = (
        <SettingsPage
          activeTab={tabs.settings}
          action={systemActions.action}
          backupAction={configurationBackup.action}
          backupError={configurationBackup.error}
          backupMessage={configurationBackup.message}
          backupRestoreAccepted={configurationBackup.restoreAccepted}
          backupUploadProgress={configurationBackup.uploadProgress}
          backupValidated={configurationBackup.validated}
          data={status.data}
          error={status.error}
          feedbackError={systemActions.error}
          feedbackMessage={systemActions.message}
          health={health.data}
          healthActionError={health.actionError}
          healthActionMessage={health.actionMessage}
          healthError={health.error}
          healthLoading={health.loading}
          healthRunning={health.running}
          healthSavingReporter={health.savingReporter}
          loading={status.loading}
          onBackupDiscard={configurationBackup.discard}
          onBackupDownload={() => void configurationBackup.download()}
          onBackupRestore={configurationBackup.restore}
          onBackupUpload={configurationBackup.upload}
          onDismissBackupFeedback={configurationBackup.dismissFeedback}
          onDismissFeedback={systemActions.dismissFeedback}
          onDismissHealthFeedback={health.dismissActionFeedback}
          onDismissTimeFeedback={systemTime.dismissSaveFeedback}
          onDownloadDiagnostics={() => void systemActions.downloadDiagnostics()}
          onRunHealth={() => void health.runDiagnostic()}
          onSetHealthReporter={(enabled) => void health.setReporterEnabled(enabled)}
          onReboot={() => void systemActions.reboot()}
          onRetry={() =>
            void Promise.all([
              status.refresh(),
              firmware.refresh(),
              systemTime.refresh(),
              scheduledReboot.refresh(),
              health.refresh(),
            ])
          }
          onDismissScheduledRebootFeedback={scheduledReboot.dismissSaveFeedback}
          onSaveScheduledReboot={scheduledReboot.saveSettings}
          onSaveTimezone={systemTime.saveTimezone}
          onSyncTime={systemTime.syncTime}
          onAdministratorPasswordChanged={onAdministratorPasswordChanged}
          rebootAccepted={systemActions.rebootAccepted}
          scheduledRebootData={scheduledReboot.data}
          scheduledRebootError={scheduledReboot.error}
          scheduledRebootLoading={scheduledReboot.loading}
          scheduledRebootSaveError={scheduledReboot.saveError}
          scheduledRebootSaveMessage={scheduledReboot.saveMessage}
          scheduledRebootSaving={scheduledReboot.saving}
          timeData={systemTime.data}
          timeError={systemTime.error}
          timeLoading={systemTime.loading}
          timeSaveError={systemTime.saveError}
          timeSaveMessage={systemTime.saveMessage}
          timeSaving={systemTime.saving}
          timeSyncing={systemTime.syncing}
        />
      );
      break;

    case 'safeshield':
      content = (
        <SafeShieldPage
          action={safeshieldActions.action}
          actionError={safeshieldActions.error}
          actionMessage={safeshieldActions.message}
          data={safeshield.data}
          error={safeshield.error}
          loading={safeshield.loading}
          statistics={safeshieldStatistics.data}
          statisticsError={safeshieldStatistics.error}
          statisticsLoading={safeshieldStatistics.loading}
          statisticsRefreshing={safeshieldStatistics.refreshing}
          onDismissFeedback={safeshieldActions.dismissFeedback}
          onRefreshBlocklist={() => void safeshieldActions.refreshBlocklist()}
          onRetry={() => void safeshield.refresh()}
          onRetryStatistics={() => void safeshieldStatistics.refresh()}
          onSetEnabled={(enabled) => void safeshieldActions.setEnabled(enabled)}
          onSetStatisticsEnabled={(enabled) =>
            void safeshieldActions.setStatisticsEnabled(enabled)
          }
        />
      );
      break;

    case 'rules':
      content = (
        <SafeShieldRulesPage
          action={rules.action}
          data={rules.data}
          error={rules.error}
          feedback={rules.feedback}
          loading={rules.loading}
          onAddRule={rules.addRule}
          onDeleteRule={rules.deleteRule}
          onLoadRecommendedRulesStatus={fetchRecommendedRulesStatus}
          onSyncRecommendedRules={refreshRecommendedRulesStatus}
          onRevokeRecommendedRule={revokeRecommendedRule}
          onDismissFeedback={rules.dismissFeedback}
          onRetry={() => void rules.refresh()}
        />
      );
      break;

    default:
      content = (
        <HomePage
          accountRegistered={dashboardAccountRegistered}
          activity={status.data?.activityHistory ?? null}
          activityError={status.error}
          activityLoading={status.loading}
          data={status.data}
          devices={dashboardDevices.data}
          devicesError={dashboardDevices.error}
          devicesLoading={dashboardDevices.loading}
          error={status.error}
          firmware={firmware.data}
          firmwareError={firmware.error}
          firmwareLoading={firmware.loading}
          health={health.data}
          healthError={health.error}
          healthLoading={health.loading}
          lan={lan.data}
          lanError={lan.error}
          lanLoading={lan.loading}
          loading={status.loading}
          onRetry={() =>
            void Promise.all([
              status.refresh(),
              dashboardDevices.refresh(),
              safeshield.refresh(),
              safeshieldStatistics.refresh(),
              updates.refresh(),
              firmware.refresh(),
              health.refresh(),
              lan.refresh(),
            ])
          }
          safeshield={dashboardSafeShield.data}
          safeshieldError={dashboardSafeShield.error}
          safeshieldLoading={dashboardSafeShield.loading}
          statistics={dashboardSafeShieldStatistics.data}
          statisticsError={dashboardSafeShieldStatistics.error}
          statisticsLoading={dashboardSafeShieldStatistics.loading}
          statisticsRefreshing={dashboardSafeShieldStatistics.refreshing}
          updates={updates.data}
          updatesError={updates.error}
          updatesLoading={updates.loading}
        />
      );
  }

  const refreshCurrent = () => {
    if (route === 'home') {
      void Promise.all([
        status.refresh(),
        dashboardDevices.refresh(),
        dashboardSafeShield.refresh(),
        dashboardSafeShieldStatistics.refresh(),
        updates.refresh(),
        firmware.refresh(),
        health.refresh(),
        lan.refresh(),
      ]);
      return;
    }

    if (route === 'network') {
      void Promise.all([wan.refresh(), lan.refresh()]);
      return;
    }

    if (route === 'system') {
      void Promise.all([updates.refresh(), firmware.refresh()]);
      return;
    }

    if (route === 'settings') {
      void Promise.all([
        status.refresh(),
        firmware.refresh(),
        systemTime.refresh(),
        scheduledReboot.refresh(),
        health.refresh(),
      ]);
      return;
    }

    if (route === 'safeshield') {
      void Promise.all([safeshield.refresh(), safeshieldStatistics.refresh()]);
      return;
    }

    void current.refresh();
  };

  const managementSoftwareUpdateAvailable = (updates.data?.updateCount ?? 0) > 0;
  const updateCount =
    (managementSoftwareUpdateAvailable ? 1 : 0) +
    (firmware.data?.updateAvailable ? 1 : 0);

  return (
    <AppShell
      accountRegistered={dashboardAccountRegistered}
      loading={route === 'network' ? wan.loading || lan.loading : current.loading}
      onRefresh={refreshCurrent}
      refreshing={
        current.refreshing ||
        (route === 'network' && lan.refreshing) ||
        (route === 'home' &&
          (activity.refreshing ||
            dashboardDevices.refreshing ||
            dashboardSafeShield.refreshing ||
            dashboardSafeShieldStatistics.refreshing ||
            updates.refreshing ||
            firmware.refreshing ||
            health.refreshing ||
            lan.refreshing)) ||
        (route === 'system' && firmware.refreshing) ||
        (route === 'settings' &&
          (firmware.refreshing ||
            systemTime.refreshing ||
            scheduledReboot.refreshing ||
            health.refreshing)) ||
        (route === 'safeshield' && safeshieldStatistics.refreshing)
      }
      route={route}
      updateCount={updateCount}
    >
      {content}
    </AppShell>
  );
}
