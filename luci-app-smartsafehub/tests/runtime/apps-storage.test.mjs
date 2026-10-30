import assert from 'node:assert/strict';
import { test } from 'node:test';

import { formatStorageBytes, summarizeAppsStorage } from '../../frontend/src/utils/appsStorage.ts';

const MB = 1024 ** 2;

test('앱 공간: /overlay 기준 실제 설치 가능 공간과 백분율을 표시한다', () => {
  const summary = summarizeAppsStorage({ mount: '/overlay', totalBytes: 80 * MB, availableBytes: 68 * MB });
  assert.equal(summary.availablePercent, 85);
  assert.equal(summary.availableText, '68.0 MB');
  assert.equal(summary.usedText, '12.0 MB');
  assert.equal(summary.totalText, '80.0 MB');
  assert.ok(Math.abs(summary.availableRatio - 0.85) < 1e-10);
  assert.equal(summary.level, 'normal');
});

test('앱 공간: 극단값, 경계값과 ext4 루트 파일시스템을 처리한다', () => {
  const empty = summarizeAppsStorage({ mount: '/', totalBytes: 100 * MB, availableBytes: 0 });
  assert.equal(empty.availablePercent, 0);
  assert.equal(empty.usedText, '100.0 MB');
  const full = summarizeAppsStorage({ mount: '/', totalBytes: 100 * MB, availableBytes: 100 * MB });
  assert.equal(full.availableRatio, 1);
  assert.equal(full.usedText, '0 B');
  assert.equal(summarizeAppsStorage({ mount: '/overlay', totalBytes: 100 * MB, availableBytes: 20 * MB }).level, 'warning');
  assert.equal(summarizeAppsStorage({ mount: '/overlay', totalBytes: 100 * MB, availableBytes: 10 * MB }).level, 'critical');
});

test('앱 공간: 실제 시스템 용량은 MiB(표시 MB)로 계산하고 반올림한다', () => {
  const summary = summarizeAppsStorage({ mount: '/', totalBytes: 81031168, availableBytes: 75153408 });
  assert.equal(summary.availableText, '71.7 MB');
  assert.equal(summary.usedText, '5.6 MB');
  assert.equal(summary.totalText, '77.3 MB');
});

test('앱 공간: 누락·유효하지 않은 RPC 응답은 임의의 용량으로 채우지 않는다', () => {
  for (const storage of [null, undefined, {}, { mount: '/tmp', totalBytes: 100, availableBytes: 20 },
    { mount: '/overlay', totalBytes: 0, availableBytes: 0 },
    { mount: '/overlay', totalBytes: 100, availableBytes: -1 },
    { mount: '/overlay', totalBytes: 100, availableBytes: 101 },
    { mount: '/overlay', totalBytes: Infinity, availableBytes: 20 },
    { mount: '/overlay', totalBytes: NaN, availableBytes: 20 }]) {
    assert.equal(summarizeAppsStorage(storage), null);
  }
});

test('앱 공간: 작은 용량과 큰 용량을 올바른 단위로 표시한다', () => {
  assert.equal(formatStorageBytes(512), '512 B');
  assert.equal(formatStorageBytes(512 * 1024), '512.0 KB');
  assert.equal(formatStorageBytes(77.3 * MB), '77.3 MB');
  assert.equal(formatStorageBytes(3 * 1024 ** 3), '3.0 GB');
  assert.equal(formatStorageBytes(-3), '—');
});

test('대시보드 디스크 사용률은 Apps 설치 가능 여유 공간과 정확히 대응한다', () => {
  const summary = summarizeAppsStorage({ mount: '/', totalBytes: 100 * MB, availableBytes: 89 * MB });
  assert.equal(100 - summary.availablePercent, 11);
  assert.equal(summary.usedText, '11.0 MB');
  assert.equal(summary.totalText, '100.0 MB');
  assert.equal(summarizeAppsStorage(null), null); // older RPC: never show a false 0% bar
});
