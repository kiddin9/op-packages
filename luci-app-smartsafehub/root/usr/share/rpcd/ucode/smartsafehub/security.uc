// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';

import {
	defer_call,
	failure,
	run_command,
	success
} from './core.uc';

const SHADOW_FILE = '/etc/shadow';
const PASSWORD_RECOVERY_MARKER = '/etc/smartsafehub/password-recovery';
const PASSWORD_RECOVERY_HELPER = '/usr/libexec/smartsafehub-password-recovery';

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

function root_password_recovery_requested() {
	return fs.stat(PASSWORD_RECOVERY_MARKER) != null;
}

function password_status(configured) {
	return {
		configured: configured,
		recovery: !configured && root_password_recovery_requested(),
	};
}

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

	return success(password_status(configured));
};


function reply_password_change_success(request) {
	const session_id = request.args.ubus_rpc_session;
	if (type(session_id) == 'string' && length(session_id)) {
		const logout_request = defer_call('session', 'destroy', {
			ubus_rpc_session: session_id,
		}, function(code, response) {
			request.reply(success({ configured: true, recovery: false }));
		});

		if (logout_request != null) {
			return logout_request;
		}
	}

	request.reply(success({ configured: true, recovery: false }));
	return null;
}

export function change_root_password(request) {
	const configured = root_password_configured();

	if (configured == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_STATUS_UNAVAILABLE',
			'root 비밀번호 설정 상태를 확인하지 못했습니다.'
		);
	}
	if (!configured) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_REQUIRED',
			'먼저 관리자 비밀번호를 설정해 주세요.'
		);
	}

	const current_password = request.args.current_password;
	const new_password = request.args.new_password;

	if (type(current_password) != 'string' || !length(current_password)) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_CURRENT_REQUIRED',
			'현재 관리자 비밀번호를 입력해 주세요.'
		);
	}

	const policy_error = password_policy_error(new_password);
	if (policy_error != null) {
		return policy_error;
	}

	if (current_password == new_password) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_UNCHANGED',
			'새 관리자 비밀번호는 현재 비밀번호와 다르게 설정해 주세요.'
		);
	}

	// Verify the current password through rpcd authentication rather than
	// reading or comparing /etc/shadow hashes in application code. The short-
	// lived verification session is destroyed immediately after authentication.
	const auth_request = defer_call('session', 'login', {
		username: 'root',
		password: current_password,
		timeout: 60,
	}, function(code, response) {
		const verification_session_id = response?.ubus_rpc_session;

		if (
			code != 0 ||
			type(verification_session_id) != 'string' ||
			!length(verification_session_id)
		) {
			request.reply(failure(
				'SYSTEM_ROOT_PASSWORD_CURRENT_INVALID',
				'현재 관리자 비밀번호가 올바르지 않습니다.'
			));
			return;
		}

		// This session is only proof that the supplied current password was
		// accepted. Do not leave an extra root session alive after verification.
		defer_call('session', 'destroy', {
			ubus_rpc_session: verification_session_id,
		}, function(code, response) {});

		// OpenWrt 25.12 exposes luci.setPassword with username/password only.
		const password_request = defer_call('luci', 'setPassword', {
			username: 'root',
			password: new_password,
		}, function(code, response) {
			if (code != 0 || response?.result != true) {
				request.reply(failure(
					'SYSTEM_ROOT_PASSWORD_CHANGE_FAILED',
					'관리자 비밀번호를 변경하지 못했습니다.'
				));
				return;
			}

			if (root_password_configured() != true) {
				request.reply(failure(
					'SYSTEM_ROOT_PASSWORD_VERIFY_FAILED',
					'관리자 비밀번호 변경 결과를 확인하지 못했습니다.'
				));
				return;
			}

			reply_password_change_success(request);
		});

		if (password_request == null) {
			request.reply(failure(
				'SYSTEM_ROOT_PASSWORD_REQUEST_FAILED',
				'관리자 비밀번호 변경 요청을 시작하지 못했습니다.'
			));
		}
	});

	if (auth_request == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_AUTH_REQUEST_FAILED',
			'현재 관리자 비밀번호 확인 요청을 시작하지 못했습니다.'
		);
	}

	return auth_request;
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
			'관리자 비밀번호가 이미 설정되어 있습니다. 설정 화면에서 변경해 주세요.'
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

		if (root_password_recovery_requested()) {
			// Password recovery deliberately clears only the root password and
			// temporarily disables Dropbear. Once a new password has been set,
			// restore the pre-recovery SSH enable state and clear the marker. A
			// cleanup failure must not turn a successfully changed password into
			// an unrecoverable form error, so keep the web login usable and let
			// the boot reconciler retry on the next restart.
			if (!run_command([PASSWORD_RECOVERY_HELPER, 'complete'], 5000)) {
				warn('smartsafehub: administrator password recovery cleanup failed\n');
			}
		}

		const session_id = request.args.ubus_rpc_session;
		if (type(session_id) == 'string' && length(session_id)) {
			const logout_request = defer_call('session', 'destroy', {
				ubus_rpc_session: session_id,
			}, function(code, response) {
				request.reply(success({ configured: true, recovery: false }));
			});

			if (logout_request != null) {
				return;
			}
		}

		request.reply(success({ configured: true, recovery: false }));
	});

	if (password_request == null) {
		return failure(
			'SYSTEM_ROOT_PASSWORD_REQUEST_FAILED',
			'관리자 비밀번호 설정 요청을 시작하지 못했습니다.'
		);
	}

	return password_request;
};
