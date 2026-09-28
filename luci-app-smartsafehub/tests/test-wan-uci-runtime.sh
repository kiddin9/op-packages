#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
UCODE_ROOT="$ROOT_DIR/root/usr/share/rpcd/ucode"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

if ! command -v ucode >/dev/null 2>&1; then
	if [ "${SMARTSAFEHUB_REQUIRE_UCODE:-0}" = '1' ]; then
		fail 'ucode runtime regression test requires ucode in PATH'
	fi
	printf '%s\n' 'PASS: ucode runtime is unavailable locally; CI still requires the WAN UCI regression test'
	exit 0
fi

command -v jq >/dev/null 2>&1 || fail 'jq is required for the WAN UCI runtime regression test'

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/smartsafehub-wan-uci.XXXXXX")"
RUNNER="$UCODE_ROOT/.smartsafehub-wan-uci-runtime.$$.uc"
trap 'rm -rf "$TMP_ROOT"; rm -f "$RUNNER"' EXIT HUP INT TERM

cat > "$TMP_ROOT/ubus.uc" <<'STUB'
export function connect() {
	return {
		call: function(object, method, args) {
			if (object == 'network.interface.wan' && method == 'status') {
				return {
					up: true,
					pending: false,
					proto: 'pppoe',
					l3_device: 'pppoe-wan',
					uptime: 321,
					'ipv4-address': [ { address: '203.0.113.7', mask: 32 } ],
					route: [ { target: '0.0.0.0', mask: 0, nexthop: '203.0.113.1' } ],
					'dns-server': [ '1.1.1.1', '8.8.8.8' ],
				};
			}
			if (object == 'network.interface' && method == 'dump') {
				return { interface: [] };
			}
			return {};
		},
	};
};
STUB

cat > "$TMP_ROOT/fs.uc" <<'STUB'
export function stat(path) { return null; };
export function mkdir(path) { return true; };
export function rmdir(path) { return true; };
STUB

cat > "$TMP_ROOT/uci.uc" <<'STUB'
export function cursor() {
	return {
		get_all: function(config, section) {
			if (config == 'network' && section == 'wan') {
				return {
					'.anonymous': false,
					'.type': 'interface',
					'.name': 'wan',
					device: 'wan',
					proto: 'pppoe',
					username: 'subscriber@example.net',
					password: 'super-secret',
					ipv6: 'auto',
				};
			}
			return null;
		},
		get: function(config, section, option) { return null; },
		set: function(config, section, option, value) { return true; },
		delete: function(config, section, option) { return true; },
		commit: function(config) { return true; },
	};
};
STUB

cat > "$RUNNER" <<'EOF_UCODE'
import {
	read_wan_settings,
	update_wan_settings
} from './smartsafehub/network-management.uc';

const read_result = read_wan_settings();
const update_result = update_wan_settings({
	args: {
		confirm: 'apply',
		protocol: 'pppoe',
		pppoe_username: 'subscriber@example.net',
		pppoe_password: '',
		pppoe_password_changed: false,
		static_address: '',
		static_prefix_length: 24,
		static_gateway: '',
		dns_primary: '',
		dns_secondary: '',
	},
});

printf('%J\n', { read: read_result, update: update_result });
EOF_UCODE

OUTPUT="$TMP_ROOT/result.json"
LOG="$TMP_ROOT/runtime.log"
if ! ucode -L "$TMP_ROOT" -L "$UCODE_ROOT" "$RUNNER" >"$OUTPUT" 2>"$LOG"; then
	cat "$LOG" >&2
	fail 'PPPoE WAN UCI fixture 실행에 실패했습니다.'
fi
[ ! -s "$LOG" ] || { cat "$LOG" >&2; fail 'WAN UCI fixture 실행 중 stderr가 발생했습니다.'; }

if grep -Fq 'super-secret' "$OUTPUT"; then
	cat "$OUTPUT" >&2
	fail 'WAN 읽기 응답에 PPPoE 비밀번호 원문이 노출되었습니다.'
fi

jq -e '
	.read.ok == true and
	.read.data.configuration.protocol == "pppoe" and
	.read.data.configuration.supported == true and
	.read.data.configuration.pppoe.username == "subscriber@example.net" and
	.read.data.configuration.pppoe.passwordConfigured == true and
	.read.data.status.connected == true and
	.read.data.status.protocol == "pppoe" and
	.read.data.status.address == "203.0.113.7" and
	.read.data.status.prefixLength == 32 and
	.read.data.status.gateway == "203.0.113.1" and
	.read.data.status.dns == ["1.1.1.1", "8.8.8.8"] and
	.update.ok == true and
	.update.data.changed == false and
	.update.data.reconnectScheduled == false
' "$OUTPUT" >/dev/null || {
	cat "$OUTPUT" >&2
	fail 'PPPoE WAN 상태를 안전하게 읽거나 기존 비밀번호를 유지한 무변경 저장을 판정하지 못했습니다.'
}

printf '%s\n' 'PASS: PPPoE WAN runtime status is parsed without exposing the stored password and unchanged settings preserve it'
