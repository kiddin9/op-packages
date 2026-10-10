// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

// Guest Wi-Fi runs in its own rpcd object. An error in this optional module
// must never prevent the main smartsafehub object (including login) loading.
import { failure, success } from './smartsafehub/core.uc';
import { root_password_configured } from './smartsafehub/security.uc';
import { guest_wifi_summary, read_guest_wifi_qr, update_guest_wifi } from './smartsafehub/guest-wifi.uc';

function require_root_password(handler) {
	return function(request) {
		const configured = root_password_configured();
		if (configured == null) {
			return failure('SYSTEM_ROOT_PASSWORD_STATUS_UNAVAILABLE', 'root 비밀번호 설정 상태를 확인하지 못했습니다.');
		}
		if (!configured) {
			return failure('SYSTEM_ROOT_PASSWORD_REQUIRED', 'SmartSafeHub를 사용하기 전에 root 관리자 비밀번호를 설정해 주세요.');
		}
		return handler(request);
	};
}

const methods = {
	wifi_guest_summary: {
		call: require_root_password(function(request) {
			const guest = guest_wifi_summary();
			return guest == null
				? failure('GUEST_WIFI_READ_FAILED', '게스트 Wi-Fi 설정을 읽지 못했습니다.')
				: success(guest);
		}),
	},
	wifi_guest_qr: {
		call: require_root_password(function(request) {
			return read_guest_wifi_qr();
		}),
	},
	wifi_guest_update: {
		args: { ssid: '', password: '', enabled: false },
		call: require_root_password(function(request) {
			return update_guest_wifi(request);
		}),
	},
};

return { smartsafehub_guest: methods };
