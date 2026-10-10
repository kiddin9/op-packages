// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
import * as fs from 'fs';
import { failure, run_command, success } from './core.uc';
const STATE_FILE = '/tmp/smartsafehub/device.json';
const HELPER = '/usr/libexec/smartsafehub-device';
function read_state() {
 const raw = fs.readfile(STATE_FILE);
 if (raw == null || length(raw) == 0) return { schema:1, component:'device', phase:'pending', lastResult:'never', lastErrorCode:null, accountRegistered:null, plan:null, pairingCode:null, pairingExpiresAt:null, protectionRefreshPending:false, nextSyncAt:0, lastSuccessAt:0 };
 try { return json(raw); } catch (e) { return null; }
}
export function read_device_registration_status(request) { const state = read_state(); return state != null ? success(state) : failure('DEVICE_STATE_INVALID', '기기 등록 상태를 읽지 못했습니다.'); };
export function refresh_device_registration_status(request) { if (!run_command([ HELPER, 'status-sync' ], 25000)) return failure('DEVICE_SYNC_FAILED', 'SmartSafeHub 계정 연결 상태를 확인하지 못했습니다.'); const state = read_state(); return state != null ? success(state) : failure('DEVICE_STATE_INVALID', '기기 등록 상태를 읽지 못했습니다.'); };
export function refresh_device_pairing(request) { if (!run_command([ HELPER, 'pairing-session' ], 15000)) return failure('DEVICE_PAIRING_FAILED', 'SmartSafeHub 계정 연결 코드를 발급하지 못했습니다.'); const state = read_state(); return state != null ? success(state) : failure('DEVICE_STATE_INVALID', '기기 등록 상태를 읽지 못했습니다.'); };
