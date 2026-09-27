// SPDX-License-Identifier: GPL-3.0-or-later

import assert from 'node:assert/strict';

const events = [];

globalThis.CustomEvent = class CustomEvent {
  constructor(type) {
    this.type = type;
  }
};

globalThis.window = {
  dispatchEvent(event) {
    events.push(event.type);
    return true;
  },
};

const {
  markSessionActive,
  notifySessionExpired,
  SESSION_EXPIRED_EVENT,
} = await import('../../frontend/src/auth/sessionEvents.ts');

notifySessionExpired('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
notifySessionExpired('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
notifySessionExpired('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
assert.deepEqual(
  events,
  [SESSION_EXPIRED_EVENT],
  'concurrent/repeated Access denied failures from one session must emit one expiry event',
);

notifySessionExpired('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
assert.deepEqual(
  events,
  [SESSION_EXPIRED_EVENT, SESSION_EXPIRED_EVENT],
  'a distinct expired session may emit its own event',
);

markSessionActive();
notifySessionExpired('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
assert.deepEqual(
  events,
  [SESSION_EXPIRED_EVENT, SESSION_EXPIRED_EVENT, SESSION_EXPIRED_EVENT],
  'a successful authentication must reset expiry deduplication for the new session lifecycle',
);

console.log('PASS: session-expiry events are deduplicated per active session lifecycle');
