// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import { failure } from './smartsafehub/core.uc';
import { read_connected_devices } from './smartsafehub/devices.uc';
import {
	discard_uploaded_backup,
	restore_uploaded_backup,
	validate_uploaded_backup
} from './smartsafehub/backup.uc';
import {
	read_root_password_status,
	root_password_configured,
	set_initial_root_password
} from './smartsafehub/security.uc';
import {
	read_scheduled_reboot_settings,
	read_status,
	read_time_settings,
	reboot_system,
	sync_time,
	update_scheduled_reboot_settings,
	update_timezone
} from './smartsafehub/system.uc';
import {
	check_firmware,
	discard_firmware,
	install_firmware,
	prepare_firmware,
	read_firmware_status,
	validate_uploaded_firmware
} from './smartsafehub/firmware.uc';
import {
	check_updates,
	install_updates,
	read_updates_status,
	update_update_settings
} from './smartsafehub/updates.uc';
import {
	read_wifi_summary,
	update_wifi
} from './smartsafehub/wifi-management.uc';
import {
	read_health_status,
	run_health_diagnostic,
	update_health_reporter
} from './smartsafehub/health.uc';
import {
	activate_license,
	read_license_status
} from './smartsafehub/license.uc';
import {
	update_activity_cloud_sync
} from './smartsafehub/activity.uc';
import {
	mutate_safeshield_rule,
	refresh_safeshield_blocklist,
	update_safeshield_enabled,
	update_safeshield_license,
	update_safeshield_statistics
} from './smartsafehub/safeshield-management.uc';

function require_root_password(handler) {
	return function(request) {
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
				'SmartSafeHub를 사용하기 전에 root 관리자 비밀번호를 설정해 주세요.'
			);
		}

		return handler(request);
	};
}

const methods = {
	system_root_password_status: {
		call: function(request) {
			return read_root_password_status(request);
		},
	},
	system_root_password_set: {
		args: {
			password: '',
		},
		call: function(request) {
			return set_initial_root_password(request);
		},
	},
	status: {
		call: require_root_password(function(request) {
			return read_status(request);
		}),
	},
	connected_devices: {
		call: require_root_password(function(request) {
			return read_connected_devices();
		}),
	},
	wifi_summary: {
		call: require_root_password(function(request) {
			return read_wifi_summary();
		}),
	},
	wifi_update: {
		args: {
			section: '',
			ssid: '',
			security: 'keep',
			password: '',
			enabled: true,
		},
		call: require_root_password(function(request) {
			return update_wifi(request);
		}),
	},
	updates_status: {
		call: require_root_password(function(request) {
			return read_updates_status(request);
		}),
	},
	updates_check: {
		call: require_root_password(function(request) {
			return check_updates(request);
		}),
	},
	updates_install: {
		args: {
			confirm: '',
		},
		call: require_root_password(function(request) {
			return install_updates(request);
		}),
	},
	updates_settings_update: {
		args: {
			check_enabled: true,
			check_interval_s: 21600,
			auto_install: false,
			auto_install_time: '03:00',
		},
		call: require_root_password(function(request) {
			return update_update_settings(request);
		}),
	},
	firmware_status: {
		call: require_root_password(function(request) {
			return read_firmware_status(request);
		}),
	},
	firmware_check: {
		call: require_root_password(function(request) {
			return check_firmware(request);
		}),
	},
	firmware_prepare: {
		call: require_root_password(function(request) {
			return prepare_firmware(request);
		}),
	},
	firmware_validate_upload: {
		args: {
			filename: 'firmware.bin',
		},
		call: require_root_password(function(request) {
			return validate_uploaded_firmware(request);
		}),
	},
	firmware_install: {
		args: {
			confirm: '',
			keep_settings: true,
		},
		call: require_root_password(function(request) {
			return install_firmware(request);
		}),
	},
	firmware_discard: {
		call: require_root_password(function(request) {
			return discard_firmware(request);
		}),
	},
	system_time_settings: {
		call: require_root_password(function(request) {
			return read_time_settings(request);
		}),
	},
	system_time_sync: {
		call: require_root_password(function(request) {
			return sync_time(request);
		}),
	},
	system_scheduled_reboot_settings: {
		call: require_root_password(function(request) {
			return read_scheduled_reboot_settings(request);
		}),
	},
	system_scheduled_reboot_update: {
		args: {
			enabled: false,
			frequency: 'weekly',
			day_of_week: 'sun',
			time: '04:00',
		},
		call: require_root_password(function(request) {
			return update_scheduled_reboot_settings(request);
		}),
	},
	system_timezone_update: {
		args: {
			zonename: '',
		},
		call: require_root_password(function(request) {
			return update_timezone(request);
		}),
	},
	system_backup_validate: {
		args: {
			filename: 'backup.tar.gz',
		},
		call: require_root_password(function(request) {
			return validate_uploaded_backup(request);
		}),
	},
	system_backup_restore: {
		args: {
			confirm: '',
		},
		call: require_root_password(function(request) {
			return restore_uploaded_backup(request);
		}),
	},
	system_backup_discard: {
		call: require_root_password(function(request) {
			return discard_uploaded_backup(request);
		}),
	},
	system_reboot: {
		args: {
			confirm: '',
		},
		call: require_root_password(function(request) {
			return reboot_system(request);
		}),
	},
	license_status: {
		call: require_root_password(function(request) {
			return read_license_status(request);
		}),
	},
	license_activate: {
		args: {
			license_key: '',
		},
		call: require_root_password(function(request) {
			return activate_license(request);
		}),
	},
	health_status: {
		call: require_root_password(function(request) {
			return read_health_status(request);
		}),
	},
	health_run: {
		call: require_root_password(function(request) {
			return run_health_diagnostic(request);
		}),
	},

	safeshield_set_enabled: {
		args: { enabled: true },
		call: require_root_password(function(request) {
			return update_safeshield_enabled(request);
		}),
	},
	safeshield_refresh: {
		call: require_root_password(function(request) {
			return refresh_safeshield_blocklist(request);
		}),
	},
	safeshield_statistics_update: {
		args: { enabled: true },
		call: require_root_password(function(request) {
			return update_safeshield_statistics(request);
		}),
	},
	safeshield_rule_add: {
		args: { action: '', domain: '', refresh: true },
		call: require_root_password(function(request) {
			return mutate_safeshield_rule(request, 'rule_add');
		}),
	},
	safeshield_rule_delete: {
		args: { action: '', domain: '', refresh: true },
		call: require_root_password(function(request) {
			return mutate_safeshield_rule(request, 'rule_delete');
		}),
	},
	safeshield_license_update: {
		args: { license_key: '' },
		call: require_root_password(function(request) {
			return update_safeshield_license(request);
		}),
	},
	activity_cloud_sync_update: {
		args: {
			enabled: false,
		},
		call: require_root_password(function(request) {
			return update_activity_cloud_sync(request);
		}),
	},
	health_reporter_update: {
		args: {
			enabled: false,
		},
		call: require_root_password(function(request) {
			return update_health_reporter(request);
		}),
	},
};

return { smartsafehub: methods };
