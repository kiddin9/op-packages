// SPDX-License-Identifier: GPL-3.0-or-later
import { DevicesIcon, PowerIcon, SearchIcon } from './Icons';
import { SmartHomeScene } from './SmartHomeScene';
import type { SmartHomeEntry } from '../utils/smartHomeEntry';

const descriptions: Record<Exclude<SmartHomeEntry, 'ready'>, { eyebrow: string; title: string; body: string; status: string }> = {
  checking: {
    eyebrow: '스마트홈 시작 안내', title: '우리 집 스마트홈을 준비해요',
    body: 'Jarbis 서비스와 앱 설치 상태를 확인하고 있습니다. 확인이 끝나면 다음 단계를 안내해 드립니다.',
    status: '상태 확인 중',
  },
  install: {
    eyebrow: '스마트홈 시작하기 · 1단계', title: '우리 집 조명을, 더 스마트하게',
    body: 'Jarbis를 설치하고 같은 Wi-Fi의 지원 전구를 연결하세요. 별도의 외부 클라우드 없이 공유기에서 직접 조명을 제어할 수 있습니다.',
    status: '설치 준비',
  },
  installing: {
    eyebrow: '스마트홈 시작 안내', title: '스마트홈을 준비하고 있어요',
    body: 'SmartSafeHub Apps에서 승인된 Jarbis를 설치하는 중입니다. 설치가 끝나면 스마트홈으로 돌아와 주세요. 설치 중에는 공유기를 재부팅하지 마세요.',
    status: '설치 진행 중',
  },
  repair: {
    eyebrow: '스마트홈 설치 복원', title: '조금만 더 준비하면 됩니다',
    body: '이전에 설치한 Jarbis의 일부 또는 전체 패키지가 누락되었습니다. SmartSafeHub Apps에서 재설치 또는 설치 마무리를 진행해 주세요.',
    status: '복원 필요',
  },
  unavailable: {
    eyebrow: '스마트홈 지원 확인', title: 'Jarbis 설치 지원을 확인해 주세요',
    body: '현재 펌웨어에서 승인된 Jarbis를 찾지 못했습니다. SmartSafeHub Apps에서 지원 여부를 확인하거나 앱 목록을 새로고침해 주세요.',
    status: '지원 확인 필요',
  },
  'service-error': {
    eyebrow: '스마트홈 연결 점검', title: 'Jarbis 연결을 확인해 주세요',
    body: 'Jarbis 설치는 확인했지만 서비스에서 응답하지 않습니다. 잠시 후 다시 확인하거나 Apps에서 앱 상태를 점검해 주세요.',
    status: '서비스 응답 없음',
  },
  unknown: {
    eyebrow: '스마트홈 상태 확인', title: '연결 상태를 확인해 주세요',
    body: '공유기 또는 앱 정보 조회에 문제가 있습니다. Jarbis 미설치로 단정할 수 없으므로 연결을 확인한 뒤 다시 시도해 주세요.',
    status: '확인 필요',
  },
};

const steps = [
  { number: '01', label: 'Jarbis 설치', detail: 'Apps에서 설치 승인' },
  { number: '02', label: '전구 연결', detail: 'Wi-Fi의 Tasmota 전구 검색' },
  { number: '03', label: '조명 제어', detail: '전원과 밝기·색상 조절' },
];

export function SmartHomeWelcome({ stage, onRetry }: { stage: Exclude<SmartHomeEntry, 'ready'>; onRetry: () => void }) {
  const info = descriptions[stage];
  const checking = stage === 'checking';
  const installing = stage === 'installing';
  const showFeatures = stage === 'install' || stage === 'unavailable';
  const actionLabel = stage === 'install' ? 'Jarbis 설치하기'
    : stage === 'repair' ? 'Apps에서 복원하기'
      : installing ? '설치 상태 보기' : 'SmartSafeHub Apps 열기';

  return <div class="ssh-home-onboarding" data-stage={stage} aria-label="스마트홈 시작 안내" aria-busy={checking || installing}>
    <section class="ssh-home-welcome">
      <div class="ssh-home-copy">
        <div class="ssh-home-brand"><span class="ssh-home-brand-mark" aria-hidden="true"><PowerIcon class="size-4" /></span> SMARTSAFEHUB <span class="ssh-home-brand-divider" /> SMART HOME</div>
        <div class="ssh-home-stage-label"><span class="ssh-home-status-dot" aria-hidden="true" />{info.status}</div>
        <p class="ssh-home-eyebrow">{info.eyebrow}</p>
        <h2 class="ssh-home-title">{info.title}</h2>
        <p class="ssh-home-description">{info.body}</p>
        <div class="ssh-home-actions">
          {!checking && stage !== 'unknown' ? <a class="ssh-home-primary" href="#apps?highlight=jarbis">{actionLabel}<span aria-hidden="true">↗</span></a> : null}
          <button class="ssh-home-secondary" type="button" onClick={onRetry}>다시 확인</button>
        </div>
        {showFeatures ? <p class="ssh-home-action-note">설치는 SmartSafeHub Apps에서 직접 승인해야 시작됩니다. 다른 공유기 기능은 설치 없이 사용할 수 있습니다.</p> : null}
      </div>
      <div class="ssh-home-visual">
        <SmartHomeScene />
        <p class="ssh-home-visual-note">스마트 전구 제어를 표현한 예시 그림이며 실제 연결 상태가 아닙니다.</p>
      </div>
    </section>

    {showFeatures ? <>
      <div class="ssh-home-features" aria-label="Jarbis로 할 수 있는 일">
        <article class="ssh-home-feature">
          <span class="ssh-home-feature-icon" aria-hidden="true"><SearchIcon class="size-5" /></span>
          <div><h3>전구를 손쉽게 찾고</h3><p>같은 Wi-Fi의 지원 Tasmota 전구를 검색합니다.</p></div>
        </article>
        <article class="ssh-home-feature">
          <span class="ssh-home-feature-icon" aria-hidden="true"><DevicesIcon class="size-5" /></span>
          <div><h3>원하는 분위기로 제어하고</h3><p>지원 전구의 전원·밝기·색상을 조절합니다.</p></div>
        </article>
        <article class="ssh-home-feature">
          <span class="ssh-home-feature-icon" aria-hidden="true"><PowerIcon class="size-5" /></span>
          <div><h3>집 안에서 직접 연결해요</h3><p>외부 클라우드를 거치지 않고 제어합니다.</p></div>
        </article>
      </div>
      <section class="ssh-home-steps" aria-label="스마트홈 시작 순서">
        <div class="ssh-home-steps-heading">
          <span class="ssh-home-steps-eyebrow">GET STARTED</span>
          <h3>스마트홈 시작은 간단합니다</h3>
        </div>
        <ol class="ssh-home-step-list">
          {steps.map((step, index) => <li class="ssh-home-step" key={step.number}>
            <span class="ssh-home-step-number">{step.number}</span>
            <div><strong>{step.label}</strong><p>{step.detail}</p></div>
            {index < steps.length - 1 ? <span class="ssh-home-step-arrow" aria-hidden="true">→</span> : null}
          </li>)}
        </ol>
      </section>
    </> : null}
  </div>;
}
