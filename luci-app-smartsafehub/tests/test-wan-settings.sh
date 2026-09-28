#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
NETWORK_RPC="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub-network.uc"
NETWORK_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/network-management.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
HOOK="$ROOT_DIR/frontend/src/hooks/useWan.ts"
PAGE="$ROOT_DIR/frontend/src/pages/WanPage.tsx"
IPV4_INPUT="$ROOT_DIR/frontend/src/components/Ipv4OctetInput.tsx"
LAN_PAGE="$ROOT_DIR/frontend/src/pages/LanPage.tsx"
TYPES="$ROOT_DIR/frontend/src/types/wan.ts"
ROUTES="$ROOT_DIR/frontend/src/app/routes.ts"
HASH_ROUTE="$ROOT_DIR/frontend/src/hooks/useHashRoute.ts"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
ACTIVITY="$ROOT_DIR/frontend/src/components/ActivityTimeline.tsx"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$NETWORK_RPC" "$NETWORK_MODULE" "$ACL" "$API" "$HOOK" "$PAGE" "$IPV4_INPUT" "$LAN_PAGE" "$TYPES" "$ROUTES" "$HASH_ROUTE" "$NAVIGATION" "$APP" "$ACTIVITY"; do
	[ -f "$file" ] || fail "WAN 설정 계약 파일이 없습니다: ${file#$ROOT_DIR/}"
done

for method in wan_settings wan_update wan_reconnect; do
	grep -Eq "^[[:space:]]*${method}:[[:space:]]*\\{" "$NETWORK_RPC" || \
		fail "smartsafehub_network.$method RPC 메서드가 필요합니다."
done

jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub_network | index("wan_settings") != null' "$ACL" >/dev/null || \
	fail 'smartsafehub_network.wan_settings 읽기 ACL이 필요합니다.'
for method in wan_update wan_reconnect; do
	jq -e --arg method "$method" '."luci-app-smartsafehub".write.ubus.smartsafehub_network | index($method) != null' "$ACL" >/dev/null || \
		fail "smartsafehub_network.$method 쓰기 ACL이 필요합니다."
done

grep -Fq "protocol == 'dhcp' || protocol == 'pppoe' || protocol == 'static'" "$NETWORK_MODULE" || \
	fail 'WAN은 DHCP, PPPoE, 고정 IPv4 연결 방식을 지원해야 합니다.'
grep -Fq "ctx?.get_all('network', 'wan')" "$NETWORK_MODULE" || \
	fail 'WAN 설정은 기존 network.wan UCI 인터페이스를 기준으로 읽어야 합니다.'
grep -Fq "safe_call('network.interface.wan', 'status', {})" "$NETWORK_MODULE" || \
	fail 'WAN 화면은 netifd runtime 상태를 읽어야 합니다.'
grep -Fq 'passwordConfigured: config.pppoePasswordConfigured' "$NETWORK_MODULE" || \
	fail 'PPPoE 비밀번호는 값 대신 설정 여부만 응답해야 합니다.'
if grep -Fq 'password: config.' "$NETWORK_MODULE"; then
	fail 'WAN 읽기 응답에 PPPoE 비밀번호 원문을 포함하면 안 됩니다.'
fi
grep -Fq "current.protocol != 'pppoe' || !current.pppoePasswordConfigured" "$NETWORK_MODULE" || \
	fail '새 PPPoE 연결에는 실제 비밀번호 입력을 요구해야 합니다.'
grep -Fq "ctx.set('network', 'wan', 'proto', validated.protocol)" "$NETWORK_MODULE" || \
	fail 'WAN 프로토콜은 network.wan.proto에 저장해야 합니다.'
grep -Fq "ctx.set('network', 'wan', 'username', validated.pppoeUsername)" "$NETWORK_MODULE" || \
	fail 'PPPoE 사용자명 저장이 필요합니다.'
grep -Fq "ctx.set('network', 'wan', 'password', validated.pppoePassword)" "$NETWORK_MODULE" || \
	fail '사용자가 새 비밀번호를 입력한 경우에만 PPPoE 비밀번호를 저장해야 합니다.'
grep -Fq "ctx.set('network', 'wan', 'ipaddr', validated.staticAddress.address)" "$NETWORK_MODULE" || \
	fail '고정 IPv4 주소 저장이 필요합니다.'
grep -Fq "ctx.set('network', 'wan', 'netmask', validated.staticNetmask)" "$NETWORK_MODULE" || \
	fail '고정 IPv4 netmask 저장이 필요합니다.'
grep -Fq "ctx.set('network', 'wan', 'gateway', validated.staticGateway.address)" "$NETWORK_MODULE" || \
	fail '고정 IPv4 gateway 저장이 필요합니다.'
grep -Fq "ctx.set('network', 'wan', 'dns', validated.staticDns)" "$NETWORK_MODULE" || \
	fail '고정 IPv4 DNS 저장이 필요합니다.'
grep -Fq "'( sleep 2; /sbin/ifdown wan; /sbin/ifup wan ) >/dev/null 2>&1 </dev/null &'" "$NETWORK_MODULE" || \
	fail 'WAN 변경은 LAN을 건드리지 않고 WAN 인터페이스만 지연 재연결해야 합니다.'
grep -Fq 'restore_wan_snapshot(snapshot)' "$NETWORK_MODULE" || \
	fail 'WAN 적용 예약 실패 시 이전 UCI 설정으로 복구해야 합니다.'
grep -Fq "emit_activity_event('network', 'settings.wan.updated'" "$NETWORK_MODULE" || \
	fail 'WAN 설정 변경은 최근 활동 이벤트를 남겨야 합니다.'

for api_method in wan_settings wan_update wan_reconnect; do
	grep -Fq "'$api_method'" "$API" || fail "프론트엔드 API가 $api_method RPC를 호출해야 합니다."
done
grep -Fq "confirm: 'apply'" "$API" || fail 'WAN 설정 저장은 명시적 apply 확인 값을 보내야 합니다.'
grep -Fq "{ confirm: 'reconnect' }" "$API" || fail 'WAN 수동 재연결은 명시적 reconnect 확인 값을 보내야 합니다.'
grep -Fq 'pppoePasswordChanged: form.pppoePassword.length > 0' "$PAGE" || \
	fail 'PPPoE 비밀번호 입력을 건드리지 않으면 기존 비밀번호를 보존해야 합니다.'
grep -Fq '저장되지 않음' "$PAGE" || fail 'WAN 화면은 미저장 설정 표시를 제공해야 합니다.'
grep -Fq 'id="wan-protocol"' "$PAGE" || fail 'WAN 연결 방식은 공통 CustomSelect를 사용해야 합니다.'
grep -Fq 'id="wan-static-prefix-length"' "$PAGE" || fail 'WAN 정적 prefix도 공통 CustomSelect를 사용해야 합니다.'
[ "$(grep -Fc '<Ipv4OctetInput' "$PAGE")" -eq 4 ] || fail 'WAN 고정 IPv4 주소, gateway, 기본/보조 DNS는 4개의 공용 octet 입력을 사용해야 합니다.'
grep -Fq 'label="IPv4 주소"' "$PAGE" || fail 'WAN 고정 IPv4 주소 octet 입력이 필요합니다.'
grep -Fq 'label="기본 게이트웨이"' "$PAGE" || fail 'WAN gateway octet 입력이 필요합니다.'
grep -Fq 'label="기본 DNS"' "$PAGE" || fail 'WAN 기본 DNS octet 입력이 필요합니다.'
grep -Fq 'label="보조 DNS"' "$PAGE" || fail 'WAN 보조 DNS octet 입력이 필요합니다.'
grep -Fq "const DEFAULT_STATIC_SECONDARY_DNS = '1.1.1.1';" "$PAGE" || fail '새 고정 IPv4 설정의 보조 DNS 기본값은 1.1.1.1이어야 합니다.'
grep -Fq "value === 'static' && !normalized(form.dnsSecondary)" "$PAGE" || fail '고정 IPv4로 전환할 때 보조 DNS가 비어 있으면 기본 DNS를 채워야 합니다.'
grep -Fq 'inputMode="numeric"' "$IPV4_INPUT" || fail '공용 IPv4 octet 입력은 모바일 숫자 키패드를 사용해야 합니다.'
grep -Fq "octets.every((octet) => octet === '') ? '' : octets.join('.')" "$IPV4_INPUT" || fail '선택 IPv4 입력은 모든 octet을 지우면 빈 값으로 복원되어야 합니다.'
grep -Fq "from '../components/Ipv4OctetInput'" "$LAN_PAGE" || fail 'LAN도 WAN과 동일한 공용 IPv4 octet 입력을 재사용해야 합니다.'
grep -Fq 'onReconnect={reconnect}' "$PAGE" || fail 'WAN 화면에 수동 재연결 기능이 있어야 합니다.'
grep -Fq "route: 'network'" "$ROUTES" || fail 'WAN과 LAN을 통합한 네트워크 설정 route가 필요합니다.'
grep -Fq "hash: '#network'" "$ROUTES" || fail '네트워크 설정 route는 #network hash를 사용해야 합니다.'
grep -Fq "'#wan': 'network'" "$HASH_ROUTE" || fail '기존 #wan hash는 통합 네트워크 설정으로 연결되어야 합니다.'
grep -Fq "{ label: 'Network', routes: ['network', 'wifi', 'iptv', 'devices'] }" "$NAVIGATION" || \
	fail 'Network 메뉴는 통합 네트워크 설정을 Wi-Fi보다 먼저 노출해야 합니다.'
grep -Fq "case 'network':" "$APP" || fail 'App이 통합 네트워크 설정 화면을 렌더링해야 합니다.'
grep -Fq '<WanPage' "$APP" || fail '통합 네트워크 설정 화면에 WAN 영역이 포함되어야 합니다.'
grep -Fq "case 'settings.wan.updated':" "$ACTIVITY" || fail '최근 활동이 WAN 설정 변경 이벤트를 설명해야 합니다.'

printf '%s\n' 'PASS: WAN DHCP/PPPoE/static IPv4 configuration, safe PPPoE secret handling and reconnect UI contracts are present'
