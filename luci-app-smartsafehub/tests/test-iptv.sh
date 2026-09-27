#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT_DIR/Makefile"
CONFIG="$ROOT_DIR/root/etc/config/smartsafehub"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub-network.uc"
MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/iptv-management.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
HOOK="$ROOT_DIR/frontend/src/hooks/useIptv.ts"
TYPE="$ROOT_DIR/frontend/src/types/iptv.ts"
PAGE="$ROOT_DIR/frontend/src/pages/IptvPage.tsx"
ROUTES="$ROOT_DIR/frontend/src/app/routes.ts"
HASH_ROUTE="$ROOT_DIR/frontend/src/hooks/useHashRoute.ts"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
ICONS="$ROOT_DIR/frontend/src/components/Icons.tsx"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
STYLES="$ROOT_DIR/frontend/src/styles/app.css"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for file in "$MAKEFILE" "$CONFIG" "$RPC_ENTRY" "$MODULE" "$ACL" "$API" "$HOOK" "$TYPE" "$PAGE" "$ROUTES" "$HASH_ROUTE" "$NAVIGATION" "$ICONS" "$APP" "$STYLES"; do
  [ -f "$file" ] || fail "IPTV 계약 파일이 없습니다: ${file#$ROOT_DIR/}"
done

# Package/runtime dependency and disabled-by-default policy.
grep -Eq '^LUCI_DEPENDS:=.*(^|[[:space:]])\+igmpproxy([[:space:]]|$)' "$MAKEFILE" || \
  fail 'IPTV Beta는 igmpproxy 패키지를 런타임 의존성으로 포함해야 합니다.'
grep -Fq "config iptv 'iptv'" "$CONFIG" || fail 'SmartSafeHub IPTV UCI section이 필요합니다.'
grep -A3 -F "config iptv 'iptv'" "$CONFIG" | grep -Fq "option enabled '0'" || \
  fail 'IPTV Beta는 기본 비활성화 상태여야 합니다.'
grep -A3 -F "config iptv 'iptv'" "$CONFIG" | grep -Fq "option provider 'skb'" || \
  fail 'IPTV 기본 provider는 skb여야 합니다.'
grep -Fq 'if [ "$$(uci -q get smartsafehub.iptv.enabled 2>/dev/null)" = "1" ]; then' "$MAKEFILE" || \
  fail 'postinst는 저장된 IPTV 상태에 따라 igmpproxy enable 여부를 결정해야 합니다.'
grep -Fq '/etc/init.d/igmpproxy stop' "$MAKEFILE" || \
  fail '비활성 IPTV 설치에서는 igmpproxy를 중지해야 합니다.'
grep -Fq '/etc/init.d/igmpproxy disable' "$MAKEFILE" || \
  fail '비활성 IPTV 설치에서는 igmpproxy 자동 시작을 비활성화해야 합니다.'

# RPC isolation and ACL.
grep -Fq "from './smartsafehub/iptv-management.uc';" "$RPC_ENTRY" || \
  fail 'smartsafehub_network entry가 IPTV 구현 모듈을 import해야 합니다.'
for method in iptv_settings iptv_update; do
  grep -Eq "^[[:space:]]*${method}:[[:space:]]*\{" "$RPC_ENTRY" || \
    fail "IPTV RPC 메서드가 등록되지 않았습니다: $method"
done
jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub_network | index("iptv_settings") != null' "$ACL" >/dev/null || \
  fail 'iptv_settings 읽기 ACL이 필요합니다.'
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub_network | index("iptv_update") != null' "$ACL" >/dev/null || \
  fail 'iptv_update 쓰기 ACL이 필요합니다.'

# Backend multicast configuration and safety.
grep -Fq "const SUPPORTED_PROVIDERS = [ 'skb', 'lgu' ];" "$MODULE" || \
  fail 'IPTV backend는 SKB/LG U+만 허용해야 합니다.'
grep -Fq "ctx.set('igmpproxy', upstream_section, 'network', 'wan')" "$MODULE" || \
  fail 'IGMP Proxy upstream은 wan이어야 합니다.'
grep -Fq "ctx.set('igmpproxy', downstream_section, 'network', 'lan')" "$MODULE" || \
  fail 'IGMP Proxy downstream은 lan이어야 합니다.'
grep -Fq "ctx.set('igmpproxy', upstream_section, 'altnet', [ '0.0.0.0/0' ])" "$MODULE" || \
  fail 'IPTV upstream은 multicast source 허용용 0.0.0.0/0 altnet을 사용해야 합니다.'
grep -Fq "ctx.set('igmpproxy', main_section, 'quickleave', '1')" "$MODULE" || \
  fail '채널 전환을 위해 IGMP Proxy quickleave를 활성화해야 합니다.'
grep -Fq "ctx.set('network', bridge.section, 'igmp_snooping', '1')" "$MODULE" || \
  fail 'LAN bridge에 IGMP snooping을 활성화해야 합니다.'
grep -Fq "previous_igmp_snooping" "$MODULE" || \
  fail 'IPTV 비활성화 시 기존 IGMP snooping 값을 복원할 수 있어야 합니다.'
grep -Fq "const IPTV_UPDATE_LOCK = '/tmp/smartsafehub/iptv-update.lock';" "$MODULE" || \
  fail '동시 IPTV 설정 변경을 직렬화해야 합니다.'
grep -Fq "'IPTV_IGMPPROXY_CONFLICT'" "$MODULE" || \
  fail '기존 custom igmpproxy upstream 충돌을 거부해야 합니다.'
grep -Fq "restore_runtime(snapshot)" "$MODULE" || \
  fail 'runtime 적용 실패 시 이전 IPTV/network/igmpproxy 설정으로 rollback해야 합니다.'
grep -Fq "const written = fs.writefile(path, content);" "$MODULE" || \
  fail 'rollback은 fs.writefile()의 기록 바이트 수를 확인해야 합니다.'
grep -Fq "type(written) == 'int' && written == length(content)" "$MODULE" || \
  fail 'fs.writefile() 반환형을 boolean으로 오인하면 rollback 성공 여부를 잘못 판단합니다.'
for path in smartsafehub network igmpproxy; do
  grep -Fq "snapshot.$path" "$MODULE" || fail "rollback snapshot에 $path 설정이 필요합니다."
done
grep -Fq "run_command([ IGMPPROXY_INIT, 'enable' ]" "$MODULE" || fail 'IPTV 활성화 시 igmpproxy enable이 필요합니다.'
grep -Fq "run_command([ IGMPPROXY_INIT, 'restart' ]" "$MODULE" || fail 'IPTV 활성화 시 igmpproxy restart가 필요합니다.'
grep -Fq "run_command([ IGMPPROXY_INIT, 'disable' ]" "$MODULE" || fail 'IPTV 비활성화 시 igmpproxy disable이 필요합니다.'
if grep -Eq "ctx\.(set|add)\('firewall'" "$MODULE"; then
  fail '현재 OpenWrt igmpproxy가 runtime firewall 연동을 하므로 SmartSafeHub가 중복 firewall rule을 만들면 안 됩니다.'
fi

# Frontend Beta route and provider limitations.
grep -Fq "route: 'iptv'" "$ROUTES" || fail 'IPTV route가 필요합니다.'
grep -Fq "hash: '#iptv'" "$ROUTES" || fail 'IPTV route는 #iptv hash를 사용해야 합니다.'
grep -Fq "'#iptv': 'iptv'" "$HASH_ROUTE" || fail '#iptv hash router 연결이 필요합니다.'
grep -Fq "{ label: 'Network', routes: ['lan', 'wifi', 'iptv', 'devices'] }" "$NAVIGATION" || \
  fail 'IPTV 메뉴는 Network 그룹에서 Wi-Fi 다음에 표시되어야 합니다.'
grep -Fq "routeName === 'iptv'" "$NAVIGATION" || fail 'IPTV 메뉴에 Beta badge 조건이 필요합니다.'
grep -Fq 'Beta' "$NAVIGATION" || fail 'IPTV 메뉴에 Beta 표시가 필요합니다.'
grep -Fq 'class="absolute right-0.5 top-0.5 inline-flex size-5' "$NAVIGATION" || \
  fail '접힌 사이드바의 IPTV Beta badge는 20x20px 원형 크기를 유지해야 합니다.'
grep -Fq 'text-[13px] font-extrabold' "$NAVIGATION" || \
  fail '접힌 사이드바의 IPTV β 문자는 충분한 글꼴 크기와 굵기를 유지해야 합니다.'
grep -Fq '                      β' "$NAVIGATION" || \
  fail '접힌 사이드바의 IPTV Beta badge는 단일 β 문자를 사용해야 합니다.'
if grep -Fq 'text-[8px]' "$NAVIGATION"; then
  fail '접힌 사이드바의 IPTV Beta badge는 다시 너무 작은 8px 문자 스타일로 돌아가면 안 됩니다.'
fi
grep -Fq 'export function TvIcon' "$ICONS" || fail 'IPTV 전용 TV 아이콘이 필요합니다.'
grep -Fq "const iptv = useIptv(route === 'iptv');" "$APP" || fail 'IPTV route에서 전용 hook을 활성화해야 합니다.'
grep -Fq "case 'iptv':" "$APP" || fail 'App이 IPTV 페이지를 렌더링해야 합니다.'
grep -Fq "return callApi(LAN_API_OBJECT, 'iptv_settings');" "$API" || fail 'IPTV 조회 API가 필요합니다.'
grep -Fq "'iptv_update'" "$API" || fail 'IPTV 저장 API가 필요합니다.'
grep -Fq "export type IptvProvider = 'skb' | 'lgu';" "$TYPE" || fail 'frontend provider 타입은 SKB/LG U+만 허용해야 합니다.'
grep -Fq "value: 'skb', label: 'SK Broadband'" "$PAGE" || fail 'SK Broadband 선택 항목이 필요합니다.'
grep -Fq "value: 'lgu', label: 'LG U+'" "$PAGE" || fail 'LG U+ 선택 항목이 필요합니다.'
grep -Fq 'IPTV 실험 기능' "$PAGE" || fail 'Beta 실험 기능 안내가 필요합니다.'
grep -Fq 'Beta' "$PAGE" || fail 'IPTV 페이지에 Beta badge가 필요합니다.'
grep -Fq '<CustomSelect' "$PAGE" || fail '통신사 선택은 공통 CustomSelect를 사용해야 합니다.'
if grep -Fq '<select' "$PAGE"; then
  fail 'IPTV 페이지에 native select를 사용하면 안 됩니다.'
fi
grep -Fq "const dirty = enabled !== data.enabled || provider !== data.provider;" "$PAGE" || \
  fail 'IPTV dirty state는 사용 여부와 provider 변경을 모두 감지해야 합니다.'
grep -Fq '저장되지 않음' "$PAGE" || \
  fail 'IPTV 설정이 저장 상태와 다르면 저장되지 않음 경고를 표시해야 합니다.'
grep -Fq '<AlertIcon aria-hidden="true" class="size-3.5 shrink-0" />' "$PAGE" || \
  fail 'IPTV 저장되지 않음 상태는 다른 설정 화면과 같은 경고 아이콘을 사용해야 합니다.'
grep -Fq 'role="status"' "$PAGE" || \
  fail 'IPTV 저장되지 않음 경고는 접근 가능한 status로 노출해야 합니다.'
grep -Fq '아래 동작 상태는 마지막으로 적용된 설정 기준입니다.' "$PAGE" || \
  fail '저장 전 runtime 상태가 마지막 적용 설정 기준임을 안내해야 합니다.'
grep -Fq 'SK Broadband/LG U+ 공통 IGMP Proxy 프로파일' "$PAGE" || \
  fail 'SKB/LG U+가 현재 공통 IPTV 프로파일을 사용한다는 설명이 필요합니다.'
grep -Fq 'KT IPTV는 별도 네트워크 방식이 필요해 아직 지원하지 않습니다.' "$PAGE" || \
  fail 'Beta 안내에서 KT가 현재 미지원임을 명확히 표시해야 합니다.'
grep -Fq 'role="switch"' "$PAGE" || fail 'IPTV 활성화는 접근 가능한 switch control을 사용해야 합니다.'
grep -Fq 'IGMP Proxy' "$PAGE" || fail 'IPTV runtime에서 IGMP Proxy 상태를 보여줘야 합니다.'
grep -Fq 'IGMP Snooping' "$PAGE" || fail 'IPTV runtime에서 IGMP Snooping 상태를 보여줘야 합니다.'
grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-amber-50']" "$STYLES" || \
  fail 'IPTV Beta amber surface를 위한 dark-mode 대비 규칙이 필요합니다.'

printf '%s\n' 'PASS: SKB/LG U+ IPTV Beta backend, rollback, service lifecycle, navigation and UI contracts are present'
