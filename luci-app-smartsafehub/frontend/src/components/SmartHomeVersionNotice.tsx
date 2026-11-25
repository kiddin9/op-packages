// SPDX-License-Identifier: GPL-3.0-or-later
import type { AppsCatalog, AppsInstallStatus } from '../types/apps';
import type { JarbisStatus } from '../types/jarbis';
import { assessJarbisCompatibility, compareJarbisVersions, JARBIS_FULL_FEATURE_VERSION } from '../utils/jarbisCompatibility';

interface Props {
  status: JarbisStatus;
  catalog: AppsCatalog | null;
  installation: AppsInstallStatus | null;
  catalogError: string | null;
  installError: string | null;
  demo: boolean;
}

export function SmartHomeVersionNotice({ status, catalog, installation, catalogError, installError, demo }: Props) {
  const compatibility = assessJarbisCompatibility(status);
  if (!compatibility.needsAttention) return null;

  const job = installation?.job;
  const updating = job?.appId === 'jarbis' && (job.phase === 'starting' || job.phase === 'running');
  const restoring = installation?.restore?.appId === 'jarbis' &&
    (installation.restore.phase === 'starting' || installation.restore.phase === 'running');
  const offered = catalog?.ready !== false && !catalogError ? catalog?.apps.find(app => app.id === 'jarbis') : null;
  const approvedComparison = offered ? compareJarbisVersions(offered.version, JARBIS_FULL_FEATURE_VERSION) : null;
  const catalogChecked = catalog?.ready !== false && Boolean(catalog) && !catalogError;
  const hasApprovedCompatible = approvedComparison !== null && approvedComparison >= 0;
  const issueLabels = compatibility.issues.map(issue => issue.label).join(' · ');

  return <section class="ssh-home-version-notice" aria-label="Jarbis 기능 호환성 안내" role="status">
    <div class="min-w-0 flex-1">
      <p class="ssh-home-version-heading">스마트홈 기능 업데이트 확인</p>
      <p class="ssh-home-version-copy">
        Jarbis {status.version || '버전 미확인'} · {compatibility.needsUpgrade
          ? `모든 스마트홈 기능을 사용하려면 ${JARBIS_FULL_FEATURE_VERSION} 이상이 필요합니다.`
          : '일부 스마트홈 기능의 지원 여부를 확인할 수 없습니다.'}
      </p>
      <p class="ssh-home-version-features">확인할 기능: {issueLabels}</p>
      <p class="ssh-home-version-detail">
        {updating || restoring ? 'Jarbis 설치·업데이트 작업이 진행 중입니다. 완료 후 스마트홈으로 돌아와 다시 확인해 주세요.'
          : demo ? '체험 화면의 안내입니다. 실제 앱 업데이트는 실행되지 않습니다.'
            : !compatibility.needsUpgrade ? '현재 Jarbis의 기능 지원 정보가 누락되었거나 설치 버전과 일치하지 않습니다. Apps에서 설치 상태를 확인해 주세요.'
              : catalogError || installError ? '승인된 앱 목록 또는 설치 상태를 확인하지 못했습니다. Apps에서 다시 확인해 주세요.'
              : !catalogChecked || !installation || installation.ready === false ? '현재 배포 채널에서 승인된 버전을 확인하고 있습니다.'
                : !offered ? '현재 채널에서 승인된 Jarbis 배포 버전을 찾지 못했습니다.'
                  : !hasApprovedCompatible ? `현재 채널의 승인 버전(${offered.version})은 전체 기능 최소 버전에 미달합니다. 지원 버전 배포를 기다려 주세요.`
                    : `현재 채널의 승인 버전은 ${offered.version}입니다. Apps에서 업데이트 가능 여부를 확인해 주세요.`}
      </p>
      <p class="ssh-home-version-detail">기존 스마트 전구 등 지원되는 기능은 계속 사용할 수 있습니다. 업데이트는 사용자 승인 후에만 설치합니다.</p>
    </div>
    {!demo ? <a class="ssh-home-version-action" href="#apps?highlight=jarbis">Apps에서 Jarbis 확인</a> : null}
  </section>;
}
