import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  appsJobNoticeKey,
  readDismissedAppsJob,
  saveDismissedAppsJob,
} from '../../frontend/src/utils/appsJobNotice.ts';

test('Apps 알림: 같은 작업은 새로고침해도 닫힘 상태를 유지한다', () => {
  const entries = new Map();
  const oldWindow = globalThis.window;
  globalThis.window = {
    localStorage: {
      getItem: (key) => entries.get(key) ?? null,
      setItem: (key, value) => entries.set(key, value),
    },
  };
  try {
    const failed = { phase: 'failed', action: 'install', appId: 'network-usage-monitor', code: 'E22', operationId: '1800000000-1234' };
    const key = appsJobNoticeKey(failed);
    assert.equal(readDismissedAppsJob(), null);
    saveDismissedAppsJob(key);
    assert.equal(readDismissedAppsJob(), key);
    assert.equal(appsJobNoticeKey({ ...failed }), key);
    assert.notEqual(appsJobNoticeKey({ ...failed, operationId: '1800000000-1235' }), key,
      'a new operation with the same error must show a fresh notice');
    assert.equal(appsJobNoticeKey({ ...failed, phase: 'idle' }), '');
  } finally {
    if (oldWindow === undefined) delete globalThis.window;
    else globalThis.window = oldWindow;
  }
});

test('Apps 알림: 저장소 사용을 막아도 UI가 동작하고 구형 작업 상태도 지원한다', () => {
  const oldWindow = globalThis.window;
  globalThis.window = {
    get localStorage() { throw new Error('SecurityError'); },
  };
  try {
    assert.equal(readDismissedAppsJob(), null);
    assert.doesNotThrow(() => saveDismissedAppsJob('operation:1800000000-1234'));
    assert.equal(appsJobNoticeKey({ phase: 'failed', action: 'install', appId: 'retro-arcade', code: 'E29' }),
      'legacy:failed:install:retro-arcade:E29');
    assert.equal(appsJobNoticeKey(null), '');
  } finally {
    if (oldWindow === undefined) delete globalThis.window;
    else globalThis.window = oldWindow;
  }
});
