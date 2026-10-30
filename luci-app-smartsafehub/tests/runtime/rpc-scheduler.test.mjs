// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import test from 'node:test';
import { acquireRpcSlot } from '../../frontend/src/api/rpcScheduler.ts';

test('RPC queue reserves a slot for interactive actions and releases cancelled waiters', async () => {
  const background = await Promise.all(Array.from({ length: 3 }, () => acquireRpcSlot('low')));
  const pending = acquireRpcSlot('low');
  const interactive = await acquireRpcSlot('high');
  // With four slots taken, a queued request must be cancellable without a leak.
  const controller = new AbortController();
  const cancelled = acquireRpcSlot('normal', controller.signal);
  controller.abort();
  await assert.rejects(cancelled, (error) => error.name === 'AbortError');
  interactive();
  let settled = false;
  void pending.then(() => { settled = true; });
  await Promise.resolve();
  assert.equal(settled, false, 'fourth low-priority RPC must not consume the reserved slot');
  background[0]();
  const fourth = await pending;
  fourth();
  background[1]();
  background[2]();
});

test('pre-aborted signal never starts work', async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(acquireRpcSlot('high', controller.signal), (error) => error.name === 'AbortError');
});

test('queued RPC starts after an earlier queued request is aborted', async () => {
  const active = await Promise.all(Array.from({ length: 4 }, () => acquireRpcSlot('normal')));
  const controller = new AbortController();
  const cancelled = acquireRpcSlot('normal', controller.signal);
  const successor = acquireRpcSlot('high');

  controller.abort();
  await assert.rejects(cancelled, (error) => error.name === 'AbortError');

  active[0]();
  const releaseSuccessor = await successor;
  releaseSuccessor();
  active.slice(1).forEach((release) => release());

  // All accounting must be restored after cancelling, draining and releasing.
  const again = await Promise.all(Array.from({ length: 4 }, () => acquireRpcSlot('normal')));
  again.forEach((release) => release());
});
