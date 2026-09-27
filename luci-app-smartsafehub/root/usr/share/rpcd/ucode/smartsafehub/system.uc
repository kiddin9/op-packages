// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';

import { read_activity_history } from './activity.uc';

import {
	defer_call,
	emit_activity_event,
	failure,
	memory_value,
	new_uci_cursor,
	number_value,
	run_command,
	string_value,
	success
} from './core.uc';

const AUTO_INSTALL_MARKER = '/tmp/smartsafehub/updater-auto-date';
const AUTO_RETRY_MARKER = '/tmp/smartsafehub/updater-auto-retry-at';
const AUTO_RETRY_COUNT_MARKER = '/tmp/smartsafehub/updater-auto-retry-count';
const MAINTENANCE_HELPER = '/usr/libexec/smartsafehub-maintenance';
const MAINTENANCE_INIT = '/etc/init.d/smartsafehub-maintenance';

function first_system_section(ctx) {
	let found = null;

	ctx.foreach('system', 'system', function(section) {
		if (found == null) {
			found = section;
		}
	});

	return found;
}

function timezone_map(timezones, configured_zonename, configured_timezone) {
	const zones = {};

	if (type(timezones) == 'object') {
		for (let zonename in keys(timezones)) {
			const tzstring = string_value(timezones[zonename]?.tzstring, null);
			if (tzstring != null) {
				zones[zonename] = tzstring;
			}
		}
	}

	// Keep a legacy/custom current zone visible in the UI even when a newer
	// timezone database no longer advertises it. New writes still validate
	// against luci.getTimezones() before changing UCI.
	if (
		configured_zonename != null &&
		configured_timezone != null &&
		zones[configured_zonename] == null
	) {
		zones[configured_zonename] = configured_timezone;
	}

	return zones;
}

function time_settings_payload(timezones) {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return failure('SYSTEM_TIME_CONFIG_UNAVAILABLE', '시간대 설정을 읽지 못했습니다.');
	}

	const system_section = first_system_section(ctx);
	if (system_section == null) {
		return failure('SYSTEM_TIME_SECTION_MISSING', '시스템 시간대 설정을 찾지 못했습니다.');
	}

	const zonename = string_value(system_section?.zonename, 'UTC');
	const timezone = string_value(system_section?.timezone, 'GMT0');
	const ntp = ctx.get_all('system', 'ntp');

	return success({
		localtime: time(),
		zonename: zonename,
		timezone: timezone,
		ntpEnabled: ntp != null && string_value(ntp?.enabled, '1') != '0',
		timezones: timezone_map(timezones, zonename, timezone),
	});
}

function restore_system_time(ctx, section_name, zonename, timezone) {
	const restored_zonename = zonename == null
		? ctx.delete('system', section_name, 'zonename') == true
		: ctx.set('system', section_name, 'zonename', zonename) == true;
	const restored_timezone = timezone == null
		? ctx.delete('system', section_name, 'timezone') == true
		: ctx.set('system', section_name, 'timezone', timezone) == true;

	return restored_zonename && restored_timezone && ctx.commit('system') == true;
}

function reset_automatic_update_schedule() {
	fs.unlink(AUTO_INSTALL_MARKER);
	fs.unlink(AUTO_RETRY_MARKER);
	fs.unlink(AUTO_RETRY_COUNT_MARKER);

	// The software updater evaluates its scheduled install time with the
	// router's local timezone. Restart it after a timezone change so today's
	// marker is recalculated with the new local date/time.
	run_command([
		'/bin/sh',
		'-c',
		'/etc/init.d/smartsafehub-updater restart >/dev/null 2>&1 </dev/null &',
	], 2000);

	// Reserved reboot schedules also use the router's local timezone. Restart
	// the lightweight maintenance daemon so a timezone change is reflected
	// immediately instead of waiting for its next configuration reload.
	run_command([ MAINTENANCE_INIT, 'restart' ], 5000);
}

function apply_timezone(request, timezones) {
	const requested_zonename = request.args.zonename;
	if (type(requested_zonename) != 'string' || !length(requested_zonename)) {
		return failure('SYSTEM_TIMEZONE_INVALID', '시간대를 선택해 주세요.');
	}

	const ctx = new_uci_cursor();
	if (!ctx) {
		return failure('SYSTEM_TIME_CONFIG_UNAVAILABLE', '시간대 설정을 읽지 못했습니다.');
	}

	const system_section = first_system_section(ctx);
	const section_name = string_value(system_section?.['.name'], null);
	if (system_section == null || section_name == null) {
		return failure('SYSTEM_TIME_SECTION_MISSING', '시스템 시간대 설정을 찾지 못했습니다.');
	}

	const current_zonename = string_value(system_section?.zonename, null);
	const current_timezone = string_value(system_section?.timezone, null);
	const requested_timezone = string_value(timezones?.[requested_zonename]?.tzstring, null);

	// A current legacy zone that disappeared from the active timezone database
	// may remain selected, but it must not be rewritten with guessed metadata.
	if (requested_timezone == null) {
		if (requested_zonename == current_zonename) {
			return time_settings_payload(timezones);
		}

		return failure(
			'SYSTEM_TIMEZONE_UNSUPPORTED',
			'이 장치에서 지원하는 시간대를 선택해 주세요.'
		);
	}

	if (
		requested_zonename == current_zonename &&
		requested_timezone == current_timezone
	) {
		return time_settings_payload(timezones);
	}

	const updated =
		ctx.set('system', section_name, 'zonename', requested_zonename) == true &&
		ctx.set('system', section_name, 'timezone', requested_timezone) == true;

	if (!updated || ctx.commit('system') != true) {
		return failure('SYSTEM_TIMEZONE_COMMIT_FAILED', '시간대 설정을 저장하지 못했습니다.');
	}

	if (!run_command([ '/etc/init.d/system', 'reload' ], 5000)) {
		const restored = restore_system_time(
			ctx,
			section_name,
			current_zonename,
			current_timezone
		);
		if (restored) {
			run_command([ '/etc/init.d/system', 'reload' ], 5000);
		}

		return restored
			? failure(
				'SYSTEM_TIMEZONE_APPLY_FAILED',
				'시간대를 적용하지 못해 이전 설정으로 되돌렸습니다.'
			)
			: failure(
				'SYSTEM_TIMEZONE_ROLLBACK_FAILED',
				'시간대 적용과 설정 복구에 실패했습니다. LuCI 시스템 설정을 확인해 주세요.'
			);
	}

	reset_automatic_update_schedule();
	emit_activity_event('system', 'settings.timezone.updated', 'info', {
		origin: 'direct',
		zonename: requested_zonename,
	});
	return time_settings_payload(timezones);
}

export function read_time_settings(request) {
	const timezone_request = defer_call('luci', 'getTimezones', {}, function(code, timezones) {
		if (code != 0 || type(timezones) != 'object') {
			request.reply(failure(
				'SYSTEM_TIMEZONE_DATABASE_UNAVAILABLE',
				'장치의 시간대 목록을 불러오지 못했습니다.'
			));
			return;
		}

		request.reply(time_settings_payload(timezones));
	});

	if (timezone_request == null) {
		return failure(
			'SYSTEM_TIMEZONE_REQUEST_FAILED',
			'시간대 목록 요청을 시작하지 못했습니다.'
		);
	}

	return timezone_request;
};

export function update_timezone(request) {
	const timezone_request = defer_call('luci', 'getTimezones', {}, function(code, timezones) {
		if (code != 0 || type(timezones) != 'object') {
			request.reply(failure(
				'SYSTEM_TIMEZONE_DATABASE_UNAVAILABLE',
				'장치의 시간대 목록을 불러오지 못했습니다.'
			));
			return;
		}

		request.reply(apply_timezone(request, timezones));
	});

	if (timezone_request == null) {
		return failure(
			'SYSTEM_TIMEZONE_REQUEST_FAILED',
			'시간대 목록 요청을 시작하지 못했습니다.'
		);
	}

	return timezone_request;
};

export function sync_time(request) {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return failure('SYSTEM_TIME_CONFIG_UNAVAILABLE', '시간 동기화 설정을 읽지 못했습니다.');
	}

	const ntp = ctx.get_all('system', 'ntp');
	const ntp_enabled = ntp != null && string_value(ntp?.enabled, '1') != '0';
	if (!ntp_enabled) {
		return failure(
			'SYSTEM_NTP_DISABLED',
			'NTP 자동 동기화가 꺼져 있어 지금 동기화할 수 없습니다.'
		);
	}

	// OpenWrt sysntpd starts BusyBox ntpd immediately with the configured
	// peers. Restarting it forces a fresh NTP request without changing the
	// user's persistent NTP configuration.
	if (!run_command([ '/etc/init.d/sysntpd', 'restart' ], 5000)) {
		return failure(
			'SYSTEM_TIME_SYNC_FAILED',
			'NTP 시간 동기화를 시작하지 못했습니다.'
		);
	}

	return success({
		accepted: true,
		requestedAt: time(),
	});
};

function scheduled_reboot_frequency(value) {
	return value == 'daily' || value == 'weekly' ? value : 'weekly';
}

function scheduled_reboot_day(value) {
	return (
		value == 'mon' ||
		value == 'tue' ||
		value == 'wed' ||
		value == 'thu' ||
		value == 'fri' ||
		value == 'sat' ||
		value == 'sun'
	) ? value : 'sun';
}

function scheduled_reboot_time(value) {
	return type(value) == 'string' && match(value, /^([01][0-9]|2[0-3]):[0-5][0-9]$/) != null
		? value
		: '04:00';
}

function scheduled_reboot_payload() {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return failure(
			'SYSTEM_SCHEDULED_REBOOT_CONFIG_UNAVAILABLE',
			'예약 재부팅 설정을 읽지 못했습니다.'
		);
	}

	const maintenance = ctx.get_all('smartsafehub', 'maintenance') ?? {};
	const system_section = first_system_section(ctx);
	const zonename = string_value(system_section?.zonename, 'UTC');

	return success({
		enabled: string_value(maintenance?.scheduled_reboot_enabled, '0') == '1',
		frequency: scheduled_reboot_frequency(maintenance?.scheduled_reboot_frequency),
		dayOfWeek: scheduled_reboot_day(maintenance?.scheduled_reboot_day),
		time: scheduled_reboot_time(maintenance?.scheduled_reboot_time),
		timezone: zonename,
	});
}

export function read_scheduled_reboot_settings(request) {
	return scheduled_reboot_payload();
};

export function update_scheduled_reboot_settings(request) {
	const enabled = request.args.enabled;
	const frequency = request.args.frequency;
	const day = request.args.day_of_week;
	const reboot_time = request.args.time;

	if (type(enabled) != 'bool') {
		return failure(
			'SYSTEM_SCHEDULED_REBOOT_ARGUMENT_INVALID',
			'예약 재부팅 사용 여부가 올바르지 않습니다.'
		);
	}
	if (frequency != 'daily' && frequency != 'weekly') {
		return failure(
			'SYSTEM_SCHEDULED_REBOOT_FREQUENCY_INVALID',
			'예약 재부팅 주기가 올바르지 않습니다.'
		);
	}
	if (scheduled_reboot_day(day) != day) {
		return failure(
			'SYSTEM_SCHEDULED_REBOOT_DAY_INVALID',
			'예약 재부팅 요일이 올바르지 않습니다.'
		);
	}
	if (type(reboot_time) != 'string' || scheduled_reboot_time(reboot_time) != reboot_time) {
		return failure(
			'SYSTEM_SCHEDULED_REBOOT_TIME_INVALID',
			'예약 재부팅 시간을 HH:MM 형식으로 선택해 주세요.'
		);
	}

	const ctx = new_uci_cursor();
	const current = ctx?.get_all('smartsafehub', 'maintenance') ?? {};
	const changed =
		(string_value(current?.scheduled_reboot_enabled, '0') == '1') != enabled ||
		scheduled_reboot_frequency(current?.scheduled_reboot_frequency) != frequency ||
		scheduled_reboot_day(current?.scheduled_reboot_day) != day ||
		scheduled_reboot_time(current?.scheduled_reboot_time) != reboot_time;

	if (!run_command([
		MAINTENANCE_HELPER,
		'configure',
		enabled ? '1' : '0',
		frequency,
		day,
		reboot_time,
	], 5000)) {
		return failure(
			'SYSTEM_SCHEDULED_REBOOT_SAVE_FAILED',
			'예약 재부팅 설정을 저장하지 못했습니다.'
		);
	}

	// The package registers a procd UCI reload trigger, but restarting here
	// also makes a newly saved schedule effective immediately on older rpcd/
	// procd combinations where trigger delivery can be delayed.
	run_command([ MAINTENANCE_INIT, 'restart' ], 5000);

	if (changed) {
		emit_activity_event('system', 'settings.scheduled_reboot.updated', 'info', {
			origin: 'direct',
			enabled: enabled,
			frequency: frequency,
			day_of_week: day,
			time: reboot_time,
		});
	}

	return scheduled_reboot_payload();
};

export function reboot_system(request) {
	if (request.args.confirm != 'reboot') {
		return failure(
			'SYSTEM_REBOOT_CONFIRMATION_REQUIRED',
			'재부팅 확인 값이 올바르지 않습니다.'
		);
	}

	const scheduled_at = time() + 2;
	const command = '(sleep 2; /sbin/reboot) >/dev/null 2>&1 </dev/null &';
	if (!run_command([ '/bin/sh', '-c', command ], 2000)) {
		return failure(
			'SYSTEM_REBOOT_START_FAILED',
			'공유기 재부팅을 시작하지 못했습니다.'
		);
	}

	return success({
		accepted: true,
		scheduledAt: scheduled_at,
	});
};

function system_status_payload(board, info, wan) {
	const release = board?.release ?? {};
	const memory = info?.memory ?? {};
	const load = info?.load ?? [ 0, 0, 0 ];
	const ipv4 = wan?.['ipv4-address'];
	const first_ipv4 = type(ipv4) == 'array' && length(ipv4) ? ipv4[0] : {};

	return {
		device: {
			hostname: string_value(board?.hostname, 'OpenWrt'),
			model: string_value(board?.model, 'OpenWrt device'),
			boardName: string_value(board?.board_name, null),
		},
		software: {
			distribution: string_value(release?.distribution, 'OpenWrt'),
			version: string_value(release?.version, 'unknown'),
			revision: string_value(release?.revision, 'unknown'),
			kernel: string_value(board?.kernel, 'unknown'),
		},
		runtime: {
			uptime: number_value(info?.uptime),
			localtime: number_value(info?.localtime),
			load: [
				number_value(load?.[0]),
				number_value(load?.[1]),
				number_value(load?.[2]),
			],
			memory: {
				total: memory_value(memory, 'total'),
				free: memory_value(memory, 'free'),
				shared: memory_value(memory, 'shared'),
				buffered: memory_value(memory, 'buffered'),
				available: memory_value(memory, 'available'),
				cached: memory_value(memory, 'cached'),
			},
		},
		network: {
			available: type(wan) == 'object' && length(keys(wan)) > 0,
			up: wan?.up == true,
			protocol: string_value(wan?.proto, null),
			ipv4Address: string_value(first_ipv4?.address, null),
		},
	};
}

function collect_system_status(done) {
	// OpenWrt's rpcd ucode API requires nested ubus requests to be deferred.
	// Returning this first deferred request keeps the original rpcd request
	// alive until done() eventually calls request.reply().
	const board_request = defer_call('system', 'board', {}, function(board_code, board) {
		if (
			board_code != 0 ||
			type(board) != 'object' ||
			length(keys(board)) == 0
		) {
			done(failure(
				'SYSTEM_BOARD_UNAVAILABLE',
				'OpenWrt board information is unavailable'
			));
			return;
		}

		const info_request = defer_call('system', 'info', {}, function(info_code, info) {
			if (info_code != 0 || type(info) != 'object') {
				done(failure(
					'SYSTEM_INFO_UNAVAILABLE',
					'OpenWrt runtime information is unavailable'
				));
				return;
			}

			const wan_request = defer_call(
				'network.interface.wan',
				'status',
				{},
				function(wan_code, wan) {
					const wan_payload = wan_code == 0 && type(wan) == 'object'
						? wan
						: {};

					done(success(system_status_payload(board, info, wan_payload)));
				}
			);

			if (wan_request == null) {
				// A WAN interface is optional. Keep valid board/runtime values and
				// report the network portion as unavailable instead of failing all.
				done(success(system_status_payload(board, info, {})));
			}
		});

		if (info_request == null) {
			done(failure(
				'SYSTEM_INFO_REQUEST_FAILED',
				'OpenWrt runtime information request could not be started'
			));
		}
	});

	if (board_request == null) {
		return failure(
			'SYSTEM_BOARD_REQUEST_FAILED',
			'OpenWrt board information request could not be started'
		);
	}

	return board_request;
}

export function read_status(request) {
	return collect_system_status(function(result) {
		if (result?.ok == true) {
			const activity_result = read_activity_history();
			if (activity_result?.ok == true) {
				result.data.activityHistory = activity_result.data;
			}
		}

		request.reply(result);
	});
};
