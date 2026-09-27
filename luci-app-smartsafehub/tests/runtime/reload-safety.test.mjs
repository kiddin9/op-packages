// SPDX-License-Identifier: GPL-3.0-or-later

import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = fileURLToPath(new URL('../..', import.meta.url));
const updatesHookPath = join(rootDir, 'frontend/src/hooks/useSoftwareUpdates.ts');
const firmwareHookPath = join(rootDir, 'frontend/src/hooks/useFirmwareUpdates.ts');
const updatesHook = readFileSync(updatesHookPath, 'utf8');
const firmwareHook = readFileSync(firmwareHookPath, 'utf8');

function collectSourceFiles(directory) {
  const files = [];

  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);

    if (entry.isDirectory()) {
      files.push(...collectSourceFiles(path));
      continue;
    }

    if (/\.(?:ts|tsx)$/.test(entry.name)) {
      files.push(path);
    }
  }

  return files;
}

function fullDocumentNavigations(source) {
  const pattern = /(?:window\.)?location\.(reload|replace|assign)\s*\(|(?:window\.)?location\.href\s*=/g;
  const matches = [];
  let match;

  while ((match = pattern.exec(source)) !== null) {
    matches.push({ method: match[1] ?? 'href', index: match.index });
  }

  return matches;
}

const navigationSites = [];
for (const file of collectSourceFiles(join(rootDir, 'frontend/src'))) {
  for (const navigation of fullDocumentNavigations(readFileSync(file, 'utf8'))) {
    navigationSites.push({
      file: relative(rootDir, file),
      method: navigation.method,
    });
  }
}

assert.deepEqual(
  navigationSites,
  [
    { file: 'frontend/src/hooks/useFirmwareUpdates.ts', method: 'reload' },
    { file: 'frontend/src/hooks/useSoftwareUpdates.ts', method: 'reload' },
  ],
  'full-document navigation must stay restricted to guarded software-update and firmware-reconnect paths',
);

assert.ok(
  firmwareHook.includes('const RECONNECT_INITIAL_DELAY_MS = 15_000;'),
  'firmware reconnect must wait before probing the router after sysupgrade starts',
);
assert.ok(
  firmwareHook.includes('if (response.ok) {\n          window.location.reload();'),
  'firmware reload must only occur after the router responds successfully again',
);
assert.equal(
  (firmwareHook.match(/window\.location\.reload\(\);/g) ?? []).length,
  1,
  'firmware reconnect path must contain exactly one reload call',
);

const effectStartMarker = '  useEffect(() => {';
const effectEndMarker = '  }, [resource.data]);';
let searchFrom = 0;
let effectBody = null;

while (searchFrom < updatesHook.length) {
  const start = updatesHook.indexOf(effectStartMarker, searchFrom);
  if (start < 0) {
    break;
  }

  const bodyStart = start + effectStartMarker.length;
  const end = updatesHook.indexOf(effectEndMarker, bodyStart);
  assert.notEqual(end, -1, 'reload effect must have a resource.data dependency terminator');

  const candidate = updatesHook.slice(bodyStart, end);
  if (candidate.includes('window.location.reload();')) {
    assert.equal(effectBody, null, 'self-update reload must exist in exactly one effect');
    effectBody = candidate;
  }

  searchFrom = end + effectEndMarker.length;
}

assert.notEqual(effectBody, null, 'self-update reload effect was not found');
assert.equal(
  (effectBody.match(/window\.location\.reload\(\);/g) ?? []).length,
  1,
  'self-update effect must contain exactly one reload call',
);
assert.equal(
  effectBody.includes('resource.error'),
  false,
  'resource errors must never drive a full-page reload',
);
assert.ok(
  effectBody.indexOf('if (reloadRequested.current || !resource.data)') <
    effectBody.indexOf('const lastInstallAt = resource.data.lastInstallAt ?? null;'),
  'empty data and an already-requested reload must be rejected before reading update state',
);
assert.ok(
  effectBody.indexOf('if (previousLastInstallAt === undefined)') <
    effectBody.lastIndexOf('lastObservedInstallAt.current = lastInstallAt;'),
  'the first real update state must establish the baseline before change detection',
);
assert.ok(
  effectBody.indexOf("resource.data.phase !== 'idle'") <
    effectBody.indexOf('installedVersion !== loadedAssetVersion'),
  'non-idle updater phases must be rejected before version mismatch can request a reload',
);
assert.ok(
  effectBody.indexOf('installedVersion !== loadedAssetVersion') <
    effectBody.indexOf('reloadRequested.current = true;'),
  'asset mismatch must be proven before arming the reload latch',
);
assert.ok(
  effectBody.indexOf('reloadRequested.current = true;') <
    effectBody.indexOf('window.location.reload();'),
  'the reload latch must be armed before invoking browser reload',
);

const runReloadEffect = new Function(
  'resource',
  'reloadRequested',
  'lastObservedInstallAt',
  'window',
  `'use strict';\nconst UPDATE_PACKAGE = 'luci-app-smartsafehub';\n${effectBody}`,
);

function updateStatus({
  phase = 'idle',
  lastInstallAt = 100,
  installedVersion = '0.2.12-r12',
  includePackage = true,
} = {}) {
  return {
    phase,
    lastInstallAt,
    packages: includePackage
      ? [
          {
            name: 'luci-app-smartsafehub',
            installedVersion,
          },
        ]
      : [],
  };
}

function createHarness({ assetVersion = '0.2.12-r10' } = {}) {
  let reloadCount = 0;
  const reloadRequested = { current: false };
  const lastObservedInstallAt = { current: undefined };
  const windowMock = {
    __SMARTHUB_BOOTSTRAP__: assetVersion === null ? {} : { assetVersion },
    location: {
      reload() {
        reloadCount += 1;
      },
    },
  };

  return {
    observe(data) {
      runReloadEffect(
        { data },
        reloadRequested,
        lastObservedInstallAt,
        windowMock,
      );
    },
    get reloadCount() {
      return reloadCount;
    },
    get reloadRequested() {
      return reloadRequested.current;
    },
    get lastObservedInstallAt() {
      return lastObservedInstallAt.current;
    },
  };
}

// Regression: data=null is the hook's initial render and must not become a fake baseline.
{
  const page = createHarness();
  page.observe(null);
  assert.equal(page.reloadCount, 0);
  assert.equal(page.reloadRequested, false);
  assert.equal(page.lastObservedInstallAt, undefined);
}

// Regression: a historical install timestamp plus stale asset mismatch on first load must never reload.
{
  const page = createHarness();
  page.observe(updateStatus({ lastInstallAt: 500 }));
  assert.equal(page.reloadCount, 0);
  assert.equal(page.lastObservedInstallAt, 500);
  page.observe(updateStatus({ lastInstallAt: 500 }));
  assert.equal(page.reloadCount, 0);
}

// Expected path: only a newly observed completed install with stale browser assets reloads once.
{
  const page = createHarness();
  page.observe(updateStatus({ lastInstallAt: 500 }));
  page.observe(updateStatus({ lastInstallAt: 600 }));
  assert.equal(page.reloadCount, 1);
  assert.equal(page.reloadRequested, true);
  page.observe(updateStatus({ lastInstallAt: 700 }));
  assert.equal(page.reloadCount, 1, 'mounted page must never request a second reload');
}

// Fatal-loop regression: the fresh document after a reload sees the completed timestamp as baseline.
{
  const staleDocument = createHarness();
  staleDocument.observe(updateStatus({ lastInstallAt: 500 }));
  staleDocument.observe(updateStatus({ lastInstallAt: 600 }));
  assert.equal(staleDocument.reloadCount, 1);

  const freshDocument = createHarness();
  freshDocument.observe(null);
  freshDocument.observe(updateStatus({ lastInstallAt: 600 }));
  freshDocument.observe(updateStatus({ lastInstallAt: 600 }));
  assert.equal(
    freshDocument.reloadCount,
    0,
    'same completed install must not reload again after document bootstrap',
  );
}

// A page opened before the first recorded install may reload when that install actually completes.
{
  const page = createHarness();
  page.observe(updateStatus({ lastInstallAt: null }));
  page.observe(updateStatus({ lastInstallAt: 600 }));
  assert.equal(page.reloadCount, 1);
}

// Null timestamps, active/error phases, missing package data, and matching assets are all non-reload states.
{
  const noTimestamp = createHarness();
  noTimestamp.observe(updateStatus({ lastInstallAt: null }));
  noTimestamp.observe(updateStatus({ lastInstallAt: null }));
  assert.equal(noTimestamp.reloadCount, 0);

  for (const phase of ['checking', 'installing', 'error']) {
    const page = createHarness();
    page.observe(updateStatus({ lastInstallAt: 500 }));
    page.observe(updateStatus({ phase, lastInstallAt: 600 }));
    assert.equal(page.reloadCount, 0, `${phase} phase must not reload`);
  }

  const missingPackage = createHarness();
  missingPackage.observe(updateStatus({ lastInstallAt: 500 }));
  missingPackage.observe(updateStatus({ lastInstallAt: 600, includePackage: false }));
  assert.equal(missingPackage.reloadCount, 0);

  const matchingAssets = createHarness({ assetVersion: '0.2.12-r12' });
  matchingAssets.observe(updateStatus({ lastInstallAt: 500 }));
  matchingAssets.observe(updateStatus({ lastInstallAt: 600 }));
  assert.equal(matchingAssets.reloadCount, 0);

  const missingAssetVersion = createHarness({ assetVersion: null });
  missingAssetVersion.observe(updateStatus({ lastInstallAt: 500 }));
  missingAssetVersion.observe(updateStatus({ lastInstallAt: 600 }));
  assert.equal(missingAssetVersion.reloadCount, 0);
}

console.log('PASS: full-document reload is allowlisted and the self-update reload guard survives regression scenarios');
