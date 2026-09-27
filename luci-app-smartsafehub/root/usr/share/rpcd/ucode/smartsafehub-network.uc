// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import { failure } from './smartsafehub/core.uc';
import { root_password_configured } from './smartsafehub/security.uc';
import {
	apply_recommended_lan,
	read_lan_settings,
	update_lan_settings
} from './smartsafehub/network-management.uc';
import {
	read_iptv_settings,
	update_iptv_settings
} from './smartsafehub/iptv-management.uc';

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
	lan_settings: {
		call: require_root_password(function(request) {
			return read_lan_settings();
		}),
	},
	lan_update: {
		args: {
			ip_address: '',
			prefix_length: 24,
			dhcp_enabled: true,
			dhcp_start: '',
			dhcp_end: '',
			lease_time: '12h',
			confirm: '',
		},
		call: require_root_password(function(request) {
			return update_lan_settings(request);
		}),
	},
	lan_auto_subnet: {
		args: {
			confirm: '',
		},
		call: require_root_password(function(request) {
			return apply_recommended_lan(request);
		}),
	},
	iptv_settings: {
		call: require_root_password(function(request) {
			return read_iptv_settings();
		}),
	},
	iptv_update: {
		args: {
			enabled: false,
			provider: 'skb',
			confirm: '',
		},
		call: require_root_password(function(request) {
			return update_iptv_settings(request);
		}),
	},
};

return { smartsafehub_network: methods };
