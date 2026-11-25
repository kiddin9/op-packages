// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const welcome = read('frontend/src/components/SmartHomeWelcome.tsx');
const scene = read('frontend/src/components/SmartHomeScene.tsx');
const css = read('frontend/src/styles/app.css');
const app = read('frontend/src/pages/SmartHomePage.tsx');

test('스마트홈 시작 화면은 일러스트와 상태별 안내를 제공한다', () => {
  for (const stage of ['checking', 'install', 'installing', 'repair', 'unavailable', 'service-error', 'unknown']) {
    assert.match(welcome, new RegExp(`(?:^|\\n)  ['"]?${stage}['"]?: \\{`, 'm'));
  }
  assert.match(welcome, /<SmartHomeScene\s*\/>/);
  assert.match(welcome, /data-stage=\{stage\}/);
  assert.match(welcome, /ssh-home-welcome/);
  assert.match(welcome, /ssh-home-features/);
  assert.match(welcome, /ssh-home-steps/);
  assert.match(welcome, /실제 연결 상태가 아닙니다/);
  assert.match(app, /if \(entry !== 'ready'\) return <SmartHomeWelcome/);
});

test('스마트홈 본 화면은 관리 센터와 기기 중심 2열 레이아웃을 사용한다', () => {
  assert.match(app, /스마트홈 관리 센터/);
  assert.match(app, /SMART HOME CONTROL/);
  assert.match(app, /PAIR & DISCOVERY/);
  assert.match(app, /ssh-home-device-grid grid gap-5 xl:grid-cols-2/);
  assert.match(app, /온습도 센서/);
});

test('스마트홈 설치 안내는 승인된 Apps 링크만 사용하고 설치 명령을 실행하지 않는다', () => {
  assert.match(welcome, /href="#apps\?highlight=jarbis"/);
  assert.match(welcome, /stage === 'install' \? 'Jarbis 설치하기'/);
  assert.match(welcome, /stage === 'repair' \? 'Apps에서 복원하기'/);
  assert.match(welcome, /stage === 'install' \|\| stage === 'unavailable'/);
  assert.match(welcome, /stage !== 'unknown'/);
  assert.match(welcome, /onClick=\{onRetry\}/);
  assert.doesNotMatch(welcome, /callApi\(|installVerifiedApp\(|repairVerifiedApp\(|fetch\(/);
});

test('일러스트는 외부 이미지 의존성과 실시간 상태 표시 없이 가벼운 SVG로 동작한다', () => {
  assert.match(scene, /<svg[\s\S]*?viewBox="0 0 520 340"/);
  assert.match(scene, /aria-hidden="true"/);
  assert.match(scene, /SMART HOME/);
  assert.doesNotMatch(scene, /<(?:image|use)\b|setInterval|setTimeout|requestAnimationFrame|fetch\(/);
  assert.doesNotMatch(scene, /(?:href|src)="https?:\/\//);
  assert.doesNotMatch(scene, /onClick=|onPointer/);
});

test('다크·라이트 테마, 모바일 레이아웃 및 모션 감소 설정을 제공한다', () => {
  assert.match(css, /\.ssh-home-welcome\s*\{/);
  assert.match(css, /\.ssh-app\[data-theme='dark'\] \.ssh-home-welcome/);
  assert.match(css, /\.ssh-app\[data-theme='dark'\] \.ssh-home-feature/);
  assert.match(css, /@media \(max-width: 700px\)\s*\{/);
  assert.match(css, /\.ssh-home-features\s*\{\s*grid-template-columns: 1fr;/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)\s*\{[\s\S]*?\.ssh-home-light-float/);
  assert.match(css, /\.ssh-home-sparkle\s*\{ animation: none;/);
  assert.match(css, /data-stage='unavailable'/);
  assert.match(css, /data-stage='service-error'/);
  assert.match(css, /\.ssh-home-primary:focus-visible/);
  assert.match(css, /\.ssh-home-secondary:focus-visible/);
});

test('패키지·Changelog·화면 자산 버전은 현재 revision과 일치한다', () => {
  const makefile = read('Makefile');
  const version = makefile.match(/^PKG_VERSION:=(\d+\.\d+\.\d+)$/m)?.[1];
  const release = makefile.match(/^PKG_RELEASE:=(\d+)$/m)?.[1];
  assert.ok(version && release, 'Makefile must declare a version and revision');
  const assetVersion = `${version}-r${release}`;

  const changelogVersion = read('CHANGELOG.md').match(/^## \[([^\]]+)\]/m)?.[1];
  assert.equal(changelogVersion, assetVersion, 'latest changelog entry must match Makefile');
  assert.ok(read('frontend/src/main.tsx').includes(`assetVersion: host.dataset.assetVersion ?? '${assetVersion}'`));

  const login = read('root/usr/share/ucode/luci/template/smartsafehub/login.ut');
  assert.ok(login.includes(`data-asset-version="${assetVersion}"`));
  assert.ok(login.includes(`favicon.svg?v=${assetVersion}"`));
  assert.ok(login.includes(`app.js?v=${assetVersion}"`));
});
