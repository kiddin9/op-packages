// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import {
	defer_call,
	emit_activity_event,
	failure,
	number_value,
	run_command,
	success
} from './core.uc';

const ACTIVITY_EVENTS_HELPER = '/usr/libexec/smartsafehub-events';

function reply_failure(request, code, message) {
	request.reply(failure(code, message));
}

function reply_success(request, response) {
	request.reply(success(type(response) == 'object' ? response : {}));
}

function safeshield_error_message(response, fallback) {
	const error = type(response?.error) == 'object' ? response.error : {};

	return type(error?.message) == 'string' && length(error.message) ? error.message : fallback;
}

function safeshield_call(request, method, args, callback) {
	const rpc = defer_call('safeshield', method, args ?? {}, function(code, response) {
		if (code != 0 || type(response) != 'object') {
			reply_failure(
				request,
				'SAFESHIELD_MUTATION_FAILED',
				'SafeShield 설정 요청을 처리하지 못했습니다.'
			);
			return;
		}
		if (response?.ok == false) {
			reply_failure(
				request,
				'SAFESHIELD_MUTATION_REJECTED',
				safeshield_error_message(response, 'SafeShield가 설정 변경 요청을 거부했습니다.')
			);
			return;
		}

		callback(response);
	});

	if (rpc == null) {
		return failure(
			'SAFESHIELD_MUTATION_REQUEST_FAILED',
			'SafeShield 설정 요청을 시작하지 못했습니다.'
		);
	}

	return rpc;
}

export function update_safeshield_enabled(request) {
	const enabled = request.args.enabled;
	if (type(enabled) != 'bool') {
		return failure('SAFESHIELD_ENABLED_INVALID', 'SafeShield 보호 상태가 올바르지 않습니다.');
	}

	return safeshield_call(request, 'set_enabled', { enabled: enabled }, function(response) {
		if (response?.changed == true) {
			emit_activity_event(
				'safeshield',
				enabled ? 'safeshield.protection.enabled' : 'safeshield.protection.disabled',
				enabled ? 'success' : 'warning',
				{ origin: 'direct' }
			);
		}
		reply_success(request, response);
	});
};

export function refresh_safeshield_blocklist(request) {
	const status_request = defer_call('safeshield', 'status', {}, function(status_code, status) {
		const timestamps = type(status?.timestamps) == 'object' ? status.timestamps : {};
		const baseline_success = number_value(timestamps?.last_success);
		const baseline_failure = number_value(timestamps?.last_failure);
		const requested_at = time();

		const refresh_request = defer_call('safeshield', 'refresh', {}, function(code, response) {
			if (code != 0 || type(response) != 'object') {
				reply_failure(
					request,
					'SAFESHIELD_REFRESH_FAILED',
					'SafeShield 차단 목록 갱신 요청을 처리하지 못했습니다.'
				);
				return;
			}
			if (response?.ok == false) {
				reply_failure(
					request,
					'SAFESHIELD_REFRESH_REJECTED',
					safeshield_error_message(response, 'SafeShield가 차단 목록 갱신 요청을 거부했습니다.')
				);
				return;
			}

			if (response?.accepted == true) {
				run_command([
					ACTIVITY_EVENTS_HELPER,
					'watch-refresh-detached',
					sprintf('%d', baseline_success),
					sprintf('%d', baseline_failure),
					sprintf('%d', requested_at),
				], 2000);
			}
			reply_success(request, response);
		});

		if (refresh_request == null) {
			reply_failure(
				request,
				'SAFESHIELD_REFRESH_REQUEST_FAILED',
				'SafeShield 차단 목록 갱신 요청을 시작하지 못했습니다.'
			);
		}
	});

	if (status_request == null) {
		return failure(
			'SAFESHIELD_STATUS_REQUEST_FAILED',
			'SafeShield 현재 상태를 확인하지 못했습니다.'
		);
	}

	return status_request;
};

export function update_safeshield_statistics(request) {
	const enabled = request.args.enabled;
	if (type(enabled) != 'bool') {
		return failure('SAFESHIELD_STATISTICS_INVALID', '차단 통계 수집 상태가 올바르지 않습니다.');
	}

	return safeshield_call(
		request,
		'config_update',
		{ values: { statistics_enabled: enabled } },
		function(response) {
			let changed = false;
			if (type(response?.changed) == 'array') {
				for (let name in response.changed) {
					if (name == 'statistics_enabled') {
						changed = true;
						break;
					}
				}
			}
			if (changed) {
				emit_activity_event(
					'safeshield',
					enabled ? 'safeshield.statistics.enabled' : 'safeshield.statistics.disabled',
					'info',
					{ origin: 'direct' }
				);
			}
			reply_success(request, response);
		}
	);
};

export function mutate_safeshield_rule(request, method) {
	return safeshield_call(request, method, {
		action: request.args.action,
		domain: request.args.domain,
		refresh: request.args.refresh,
	}, function(response) {
		const changed = method == 'rule_add' ? response?.added == true : response?.deleted == true;
		if (changed) {
			emit_activity_event(
				'safeshield',
				method == 'rule_add' ? 'safeshield.rule.added' : 'safeshield.rule.removed',
				'info',
				{
					origin: 'direct',
					rule_action: request.args.action,
				}
			);
		}
		reply_success(request, response);
	});
};

export function update_safeshield_license(request) {
	const license_key = request.args.license_key;
	if (type(license_key) != 'string') {
		return failure('SAFESHIELD_LICENSE_INVALID', '라이선스 키 형식이 올바르지 않습니다.');
	}

	return safeshield_call(request, 'license_update', { license_key: license_key }, function(response) {
		if (response?.changed == true && !length(license_key)) {
			emit_activity_event(
				'license',
				'license.cleared',
				'info',
				{ reason: 'manual', origin: 'direct' }
			);
		}
		reply_success(request, response);
	});
};
