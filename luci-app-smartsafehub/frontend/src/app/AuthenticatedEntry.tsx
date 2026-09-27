import { useCallback, useEffect, useState } from 'preact/hooks';

import { readRootPasswordStatus } from '../api/initialSetup';
import { ReloadIcon, ShieldIcon } from '../components/Icons';
import { InitialPasswordSetupPage } from '../pages/InitialPasswordSetupPage';
import { App } from './App';

type SetupPhase = 'checking' | 'required' | 'ready' | 'error';

interface AuthenticatedEntryProps {
  onPasswordConfigured: () => void;
}

export function AuthenticatedEntry({
  onPasswordConfigured,
}: AuthenticatedEntryProps) {
  const [phase, setPhase] = useState<SetupPhase>('checking');

  const refresh = useCallback(async () => {
    setPhase('checking');

    try {
      const status = await readRootPasswordStatus();
      setPhase(status.configured ? 'ready' : 'required');
    } catch {
      setPhase('error');
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  if (phase === 'ready') {
    return <App />;
  }

  if (phase === 'required') {
    return <InitialPasswordSetupPage onCompleted={onPasswordConfigured} />;
  }

  return (
    <main class="ssh-initial-setup-probe" role={phase === 'error' ? 'alert' : 'status'}>
      <div class="ssh-initial-setup-probe-card">
        {phase === 'checking' ? (
          <ReloadIcon class="ssh-login-probe-spinner" aria-hidden="true" />
        ) : (
          <ShieldIcon aria-hidden="true" />
        )}
        <strong>
          {phase === 'checking'
            ? '관리자 보안 상태 확인 중'
            : '관리자 보안 상태를 확인할 수 없습니다'}
        </strong>
        <span>
          {phase === 'checking'
            ? 'root 비밀번호 설정 여부를 확인하고 있습니다.'
            : '공유기 연결을 확인한 뒤 다시 시도해 주세요.'}
        </span>
        {phase === 'error' ? (
          <button onClick={() => void refresh()} type="button">
            다시 시도
          </button>
        ) : null}
      </div>
    </main>
  );
}
