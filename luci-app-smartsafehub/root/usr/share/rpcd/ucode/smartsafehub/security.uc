// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';

import {
	defer_call,
	failure,
	success
} from './core.uc';

const SHADOW_FILE = '/etc/shadow';

function root_password_hash() {
	const shadow = fs.readfile(SHADOW_FILE);
	if (type(shadow) != 'string') {
		return null;
	}

	for (let line in split(shadow, /\n/)) {
		if (!length(line)) {
			continue;
		}

		const fields = split(line, /:/);
		if (fields[0] == 'root') {
			return fields[1] ?? '';
		}
	}

	return null;
}

export function root_password_configured() {
	const password_hash = root_password_hash();

	if (password_hash == null) {
		return null;
	}

	// OpenWrt's factory-default root account has an empty shadow password
	// field. Locked markers such as "!" or "*" are intentionally treated as
	// configured rather than silently replacing an administrator-managed lock.
	return length(password_hash) > 0;
};

function password_policy_error(password) {
	if (type(password) != 'string') {
		return failure(
			'SYSTEM_ROOT_PASSWORD_INVALID',
			'관리자 비밀번호 형식이 올바르지 않습니다.'
		);
	}
	if (length(password) < 8) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_TOO_SHORT',
			'관리자 비밀번호는 8자 이상이어야 합니다.'
		);
	}
	if (match(password, /[A-Za-z]/) == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_LETTER_REQUIRED',
			'관리자 비밀번호에 영문자를 하나 이상 포함해 주세요.'
		);
	}
	if (match(password, /[0-9]/) == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_NUMBER_REQUIRED',
			'관리자 비밀번호에 숫자를 하나 이상 포함해 주세요.'
		);
	}

	return null;
}

export function read_root_password_status(request) {
	const configured = root_password_configured();

	if (configured == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_STATUS_UNAVAILABLE',
			'root 비밀번호 설정 상태를 확인하지 못했습니다.'
		);
	}

	return success({ configured: configured });
};

export function set_initial_root_password(request) {
	const configured = root_password_configured();

	if (configured == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_STATUS_UNAVAILABLE',
			'root 비밀번호 설정 상태를 확인하지 못했습니다.'
		);
	}
	if (configured) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_ALREADY_CONFIGURED',
			'root 비밀번호가 이미 설정되어 있습니다. 이후 변경은 LuCI 관리자 설정을 이용해 주세요.'
		);
	}

	const policy_error = password_policy_error(request.args.password);
	if (policy_error != null) {
		return policy_error;
	}

	// OpenWrt 25.12 exposes luci.setPassword with only username/password.
	// Keep the request to that common contract so the same call also remains
	// compatible with newer LuCI versions where additional args are optional.
	const password_request = defer_call('luci', 'setPassword', {
		username: 'root',
		password: request.args.password,
	}, function(code, response) {
		if (code != 0 || response?.result != true) {
			request.reply(failure(
				'SYSTEM_ROOT_PASSWORD_SET_FAILED',
				'관리자 비밀번호를 설정하지 못했습니다.'
			));
			return;
		}

		if (root_password_configured() != true) {
			request.reply(failure(
				'SYSTEM_ROOT_PASSWORD_VERIFY_FAILED',
				'관리자 비밀번호 설정 결과를 확인하지 못했습니다.'
			));
			return;
		}

		const session_id = request.args.ubus_rpc_session;
		if (type(session_id) == 'string' && length(session_id)) {
			const logout_request = defer_call('session', 'destroy', {
				ubus_rpc_session: session_id,
			}, function(code, response) {
				request.reply(success({ configured: true }));
			});

			if (logout_request != null) {
				return;
			}
		}

		request.reply(success({ configured: true }));
	});

	if (password_request == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_REQUEST_FAILED',
			'관리자 비밀번호 설정 요청을 시작하지 못했습니다.'
		);
	}

	return password_request;
};
