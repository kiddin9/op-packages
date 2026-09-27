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

	printf '%s\n' 'PASS: ucode runtime is unavailable locally; CI still requires the OpenWrt 25.12 LAN UCI regression test'
	exit 0
fi

command -v jq >/dev/null 2>&1 || fail 'jq is required for the LAN UCI runtime regression test'

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/smartsafehub-lan-uci.XXXXXX")"
RUNNER="$UCODE_ROOT/.smartsafehub-lan-uci-runtime.$$.uc"
trap 'rm -rf "$TMP_ROOT"; rm -f "$RUNNER"' EXIT HUP INT TERM

cat > "$TMP_ROOT/ubus.uc" <<'STUB'
export function connect() {
	return {
		call: function(object, method, args) {
			if (object == 'network.interface.wan' && method == 'status') {
				return {
					up: false,
					proto: 'dhcp',
					'ipv4-address': [],
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
export function stat(path) {
	return null;
};

export function mkdir(path) {
	return true;
};

export function rmdir(path) {
	return true;
};
STUB

cat > "$TMP_ROOT/uci.uc" <<'STUB'
export function cursor() {
	return {
		get_all: function(config, section) {
			if (config == 'network' && section == 'lan') {
				return {
					'.anonymous': false,
					'.type': 'interface',
					'.name': 'lan',
					device: 'br-lan',
					proto: 'static',
					ipaddr: [ '192.168.1.1/24' ],
					ip6assign: '60',
				};
			}
			if (config == 'dhcp' && section == 'lan') {
				return {
					'.anonymous': false,
					'.type': 'dhcp',
					'.name': 'lan',
					interface: 'lan',
					start: '100',
					limit: '150',
					leasetime: '12h',
					dhcpv4: 'server',
					dhcpv6: 'server',
					ra: 'server',
				};
			}

			return null;
		},
		get: function(config, section, option) {
			return null;
		},
		set: function(config, section, option, value) {
			return true;
		},
		delete: function(config, section, option) {
			return true;
		},
		commit: function(config) {
			return true;
		},
	};
};
STUB

cat > "$RUNNER" <<'EOF_UCODE'
import {
	read_lan_settings,
	update_lan_settings
} from './smartsafehub/network-management.uc';

const read_result = read_lan_settings();
const update_result = update_lan_settings({
	args: {
		confirm: 'apply',
		ip_address: '192.168.1.1',
		prefix_length: 24,
		dhcp_enabled: true,
		dhcp_start: '192.168.1.100',
		dhcp_end: '192.168.1.249',
		lease_time: '12h',
	},
});

printf('%J\n', {
	read: read_result,
	update: update_result,
});
EOF_UCODE

OUTPUT="$TMP_ROOT/result.json"
LOG="$TMP_ROOT/runtime.log"
if ! ucode -L "$TMP_ROOT" -L "$UCODE_ROOT" "$RUNNER" >"$OUTPUT" 2>"$LOG"; then
	cat "$LOG" >&2
	fail 'OpenWrt 25.12 list+CIDR LAN UCI fixture 실행에 실패했습니다.'
fi

[ ! -s "$LOG" ] || {
	cat "$LOG" >&2
	fail 'OpenWrt 25.12 LAN UCI fixture 실행 중 stderr가 발생했습니다.'
}

jq -e '
	.read.ok == true and
	.read.error == null and
	.read.data.lan.address == "192.168.1.1" and
	.read.data.lan.prefixLength == 24 and
	.read.data.lan.netmask == "255.255.255.0" and
	.read.data.lan.subnet == "192.168.1.0/24" and
	.read.data.dhcp.enabled == true and
	.read.data.dhcp.start == "192.168.1.100" and
	.read.data.dhcp.end == "192.168.1.249" and
	.read.data.dhcp.leaseTime == "12h" and
	.update.ok == true and
	.update.data.changed == false and
	.update.data.reloadScheduled == false
' "$OUTPUT" >/dev/null || {
	cat "$OUTPUT" >&2
	fail 'OpenWrt 25.12의 ipaddr 배열/CIDR 형식을 LAN 설정으로 정상 해석하지 못했습니다.'
}

printf '%s\n' 'PASS: OpenWrt 25.12 list+CIDR LAN UCI 형식을 읽고 동일 설정을 무변경으로 판정합니다.'
