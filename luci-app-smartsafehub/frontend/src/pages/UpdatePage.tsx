import { FirmwareUpdatesCard } from '../components/FirmwareUpdatesCard';
import { SoftwareUpdatesCard } from '../components/SoftwareUpdatesCard';
import type { useFirmwareUpdates } from '../hooks/useFirmwareUpdates';
import type { SoftwareUpdateAction } from '../hooks/useSoftwareUpdates';
import type {
  SoftwareUpdateSettingsInput,
  SoftwareUpdateStatus,
} from '../types/updates';

interface UpdatePageProps {
  action: SoftwareUpdateAction;
  actionError: string | null;
  data: SoftwareUpdateStatus | null;
  error: string | null;
  firmware: ReturnType<typeof useFirmwareUpdates>;
  loading: boolean;
  message: string | null;
  onCheck: () => void;
  onDismissFeedback: () => void;
  onInstall: () => void;
  onRetry: () => void;
  onSaveSettings: (input: SoftwareUpdateSettingsInput) => Promise<boolean>;
}

export function UpdatePage({
  action,
  actionError,
  data,
  error,
  firmware,
  loading,
  message,
  onCheck,
  onDismissFeedback,
  onInstall,
  onRetry,
  onSaveSettings,
}: UpdatePageProps) {
  return (
    <section class="min-w-0 space-y-5">
      <FirmwareUpdatesCard
        action={firmware.action}
        actionError={firmware.actionError}
        data={firmware.data}
        error={firmware.error}
        loading={firmware.loading}
        message={firmware.message}
        reconnecting={firmware.reconnecting}
        uploadProgress={firmware.uploadProgress}
        onCheck={() => void firmware.check()}
        onDiscard={firmware.discard}
        onDismissFeedback={firmware.dismissFeedback}
        onInstall={firmware.install}
        onPrepare={() => void firmware.prepare()}
        onRetry={() => void firmware.refresh()}
        onUpload={firmware.upload}
      />
      <SoftwareUpdatesCard
        action={action}
        actionError={actionError}
        data={data}
        error={error}
        loading={loading}
        message={message}
        onCheck={onCheck}
        onDismissFeedback={onDismissFeedback}
        onInstall={onInstall}
        onRetry={onRetry}
        onSaveSettings={onSaveSettings}
      />
    </section>
  );
}
