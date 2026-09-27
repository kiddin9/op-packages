import type { ComponentChildren } from 'preact';

import { AppShell } from '../components/AppShell';
import { useActivityHistory } from '../hooks/useActivityHistory';
import { useConfigurationBackup } from '../hooks/useConfigurationBackup';
import { useConnectedDevices } from '../hooks/useConnectedDevices';
import { useFirmwareUpdates } from '../hooks/useFirmwareUpdates';
import { useHashRoute } from '../hooks/useHashRoute';
import { useHealth } from '../hooks/useHealth';
import { useIptv } from '../hooks/useIptv';
import { useLan } from '../hooks/useLan';
import { useSafeShieldActions } from '../hooks/useSafeShieldActions';
import { useSafeShieldRules } from '../hooks/useSafeShieldRules';
import { useSafeShieldStatistics } from '../hooks/useSafeShieldStatistics';
import { useSafeShieldStatus } from '../hooks/useSafeShieldStatus';
import { useSoftwareUpdates } from '../hooks/useSoftwareUpdates';
import { useStatus } from '../hooks/useStatus';
import { useScheduledRebootSettings } from '../hooks/useScheduledRebootSettings';
import { useSystemActions } from '../hooks/useSystemActions';
import { useSystemTimeSettings } from '../hooks/useSystemTimeSettings';
import { useWifi } from '../hooks/useWifi';
import { ActivityPage } from '../pages/ActivityPage';
import { ConnectedDevicesPage } from '../pages/ConnectedDevicesPage';
import { HomePage } from '../pages/HomePage';
import { IptvPage } from '../pages/IptvPage';
import { LanPage } from '../pages/LanPage';
import { SafeShieldPage } from '../pages/SafeShieldPage';
import { SafeShieldRulesPage } from '../pages/SafeShieldRulesPage';
import { SettingsPage } from '../pages/SettingsPage';
import { UpdatePage } from '../pages/UpdatePage';
import { WifiPage } from '../pages/WifiPage';

export function App() {
  const route = useHashRoute();
  const configurationBackup = useConfigurationBackup();
  const activity = useActivityHistory(route === 'home' || route === 'activity');
  const status = useStatus(route === 'home' || route === 'settings');
  const updates = useSoftwareUpdates(true);
  const firmware = useFirmwareUpdates(
    route === 'system' || route === 'home' || route === 'settings',
  );
  const lan = useLan(route === 'home' || route === 'lan');
  const iptv = useIptv(route === 'iptv');
  const wifi = useWifi(route === 'wifi');
  const dashboardDevices = useConnectedDevices(route === 'home', false);
  const devices = useConnectedDevices(route === 'devices');
  const dashboardSafeShield = useSafeShieldStatus(route === 'home');
  const dashboardSafeShieldStatistics = useSafeShieldStatistics(route === 'home', false);
  const safeshield = useSafeShieldStatus(route === 'safeshield');
  const safeshieldStatistics = useSafeShieldStatistics(route === 'safeshield');
  const rules = useSafeShieldRules(route === 'rules');
  const systemActions = useSystemActions(status.data);
  const health = useHealth(route === 'home' || route === 'settings');
  const scheduledReboot = useScheduledRebootSettings(route === 'settings');
  const systemTime = useSystemTimeSettings(route === 'settings');
  const safeshieldActions = useSafeShieldActions(
    safeshield.refresh,
    safeshieldStatistics.refresh,
  );

  const current =
    route === 'activity'
      ? activity
      : route === 'lan'
        ? lan
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
                  : route === 'system'
                    ? updates
                    : status;

  let content: ComponentChildren;

  switch (route) {
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

    case 'lan':
      content = (
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
          firmware={firmware.data}
          firmwareError={firmware.error}
          firmwareLoading={firmware.loading}
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
          actionFeedbackTarget={safeshieldActions.feedbackTarget}
          actionMessage={safeshieldActions.message}
          data={safeshield.data}
          error={safeshield.error}
          loading={safeshield.loading}
          statistics={safeshieldStatistics.data}
          statisticsError={safeshieldStatistics.error}
          statisticsLoading={safeshieldStatistics.loading}
          statisticsRefreshing={safeshieldStatistics.refreshing}
          onDismissFeedback={safeshieldActions.dismissFeedback}
          onReadLicense={safeshieldActions.readLicense}
          onRefreshBlocklist={() => void safeshieldActions.refreshBlocklist()}
          onRemoveLicense={safeshieldActions.removeLicense}
          onRetry={() => void safeshield.refresh()}
          onRetryStatistics={() => void safeshieldStatistics.refresh()}
          onSetEnabled={(enabled) => void safeshieldActions.setEnabled(enabled)}
          onSetStatisticsEnabled={(enabled) =>
            void safeshieldActions.setStatisticsEnabled(enabled)
          }
          onUpdateLicense={safeshieldActions.updateLicense}
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
          onDismissFeedback={rules.dismissFeedback}
          onRetry={() => void rules.refresh()}
        />
      );
      break;

    default:
      content = (
        <HomePage
          activity={activity.data}
          activityError={activity.error}
          activityLoading={activity.loading}
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
              activity.refresh(),
              status.refresh(),
              dashboardDevices.refresh(),
              dashboardSafeShield.refresh(),
              dashboardSafeShieldStatistics.refresh(),
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
        activity.refresh(),
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

  return (
    <AppShell
      loading={current.loading}
      onRefresh={refreshCurrent}
      refreshing={
        current.refreshing ||
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
      updateCount={updates.data?.updateCount ?? 0}
    >
      {content}
    </AppShell>
  );
}
