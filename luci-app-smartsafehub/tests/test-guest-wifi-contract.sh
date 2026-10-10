#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Guard the isolation boundaries even when no OpenWrt runtime is available.
set -eu
cd "$(dirname "$0")/.."
API=root/usr/share/rpcd/ucode/smartsafehub.uc
GUEST_API=root/usr/share/rpcd/ucode/smartsafehub-guest.uc
BACKEND=root/usr/share/rpcd/ucode/smartsafehub/guest-wifi.uc
WIFI=root/usr/share/rpcd/ucode/smartsafehub/wifi.uc
ACL=root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json
PAGE=frontend/src/components/GuestWifiCard.tsx

# Guest actions require the same administrator authentication and lock as primary Wi-Fi.
# Guest code must not be loaded by the main RPC entry (login/security API).
if grep -q 'guest-wifi.uc\|guest_wifi_summary\|update_guest_wifi\|wifi_guest_update:' "$API"; then
  echo 'FAIL: guest module must not be eagerly imported into the main RPC object' >&2
  exit 1
fi
if grep -q 'guest-wifi.uc\|guest_wifi_summary' root/usr/share/rpcd/ucode/smartsafehub/wifi-management.uc; then
  echo 'FAIL: basic Wi-Fi management must not import guest module' >&2
  exit 1
fi
grep -q 'wifi_guest_update: {' "$GUEST_API"
grep -q 'wifi_guest_summary: {' "$GUEST_API"
grep -q 'wifi_guest_qr: {' "$GUEST_API"
grep -q 'return read_guest_wifi_qr();' "$GUEST_API"
grep -q 'return update_guest_wifi(request);' "$GUEST_API"
grep -q 'require_root_password(function(request)' "$GUEST_API"
grep -q 'return { smartsafehub_guest: methods };' "$GUEST_API"
jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub_guest | index("wifi_guest_summary") != null' "$ACL" > /dev/null
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub_guest | index("wifi_guest_update") != null' "$ACL" > /dev/null
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub_guest | index("wifi_guest_qr") != null' "$ACL" > /dev/null
if jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub_guest | index("wifi_guest_qr") != null' "$ACL" > /dev/null; then
  echo 'FAIL: guest QR credentials must require write ACL' >&2
  exit 1
fi
if jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub | index("wifi_guest_update") != null' "$ACL" > /dev/null; then
  echo 'FAIL: guest write method must only exist in the isolated guest RPC object' >&2
  exit 1
fi
grep -q "GUEST_API_OBJECT = 'smartsafehub_guest'" frontend/src/api/smartsafehub.ts
grep -q "guestError: true" frontend/src/api/smartsafehub.ts
grep -q "const LOCK = '/tmp/smartsafehub/wifi-update.lock'" "$BACKEND"
# ucode requires a semicolon after each exported function body. A missing
# terminator prevents rpcd from registering the entire guest RPC object.
if ! awk '
  /^export function / { declared++; in_export = 1; next }
  in_export && /^}/ {
    if ($0 != "};") exit 1;
    checked++; in_export = 0;
  }
  END { if (declared != 3 || checked != declared || in_export) exit 1 }
' "$BACKEND"; then
  echo 'FAIL: guest ucode exports must terminate with };' >&2
  exit 1
fi

# Cannot take over or change existing LAN AP; 2.4 GHz radio is discovered.
grep -q "section?.\['.name'\] == 'ssh_guest'" "$WIFI"
grep -q "network.band == '2g'" "$BACKEND"
grep -Fq -- '-Guest' "$BACKEND"
grep -q "guest_default_ssid" "$BACKEND"
grep -q "'bridge'" "$BACKEND"
grep -q "bridge_empty: '1'" "$BACKEND"
grep -q "device: two_g.device" "$BACKEND"

# Enforce an actual L3 separation and prevent guest connections to the router,
# internal LAN, upstream private networks, or other guest clients.
grep -q "input: 'REJECT', output: 'ACCEPT', forward: 'REJECT'" "$BACKEND"
grep -q "src: ZONE, dest: 'wan'" "$BACKEND"
grep -q "proto: \[ 'tcp', 'udp' \], dest_port: '53'" "$BACKEND"
grep -q "proto: 'udp', dest_port: '67'" "$BACKEND"
grep -q "isolate: '1'" "$BACKEND"
grep -q "dhcpv6: 'disabled', ra: 'disabled', ndp: 'disabled'" "$BACKEND"
grep -q "family: 'ipv6'" "$BACKEND"
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
  grep -q "$net" "$BACKEND"
done

# Only enable guest AP after network, dnsmasq, firewall setup and commit succeed.
grep -q "disabled: '1'" "$BACKEND"
grep -q "\[ '/etc/init.d/firewall', 'restart' \]" "$BACKEND"
grep -q "ctx.set('wireless', GUEST, 'disabled', '0')" "$BACKEND"
grep -q 'restore_files(snapshot)' "$BACKEND"
grep -q 'GUEST_WIFI_SUBNET_CONFLICT' "$BACKEND"
grep -q 'GUEST_WIFI_CONFLICT' "$BACKEND"
grep -q "passwordConfigured:" "$BACKEND"
if ! awk '
  /^export function guest_wifi_summary\(/ { in_summary = 1; next }
  in_summary && /^};/ { in_summary = 0; verified++; next }
  in_summary && /password:|key:/ { exit 1 }
  END { if (verified != 1 || in_summary) exit 1 }
' "$BACKEND"; then
  echo 'FAIL: guest summary exposes credentials' >&2
  exit 1
fi
grep -q 'export function read_guest_wifi_qr()' "$BACKEND"
grep -q 'if (!managed(ctx))' "$BACKEND"
grep -q "guest?.disabled == '1'" "$BACKEND"
grep -q "guest?.network != GUEST || guest?.encryption != 'sae-mixed'" "$BACKEND"
grep -q "success({ ssid: ssid, security: 'sae-mixed', password: key })" "$BACKEND"

grep -q '게스트 Wi-Fi 사용' "$PAGE"
grep -q '게스트 전용 비밀번호를 입력' "$PAGE"
grep -Fq 'useState(false)' "$PAGE"
grep -q 'aria-expanded={expanded}' "$PAGE"
grep -q 'aria-controls="ssh-guest-settings"' "$PAGE"
grep -q "expanded ? '' : 'hidden'" "$PAGE"
grep -q 'busy || dirty || !guest.enabled || !guest.passwordConfigured' "$PAGE"
grep -q '게스트 Wi-Fi QR 코드 보기' "$PAGE"
grep -q 'WifiQrDialog guest section="ssh_guest"' "$PAGE"
grep -q "fetchGuestWifiQr() : fetchWifiQr(section)" frontend/src/components/WifiQrDialog.tsx
grep -q "callApi(GUEST_API_OBJECT, 'wifi_guest_qr'" frontend/src/api/smartsafehub.ts
# The guest card is separated from the primary Wi-Fi cards, with a full-width
# line only when guest settings are available. Reuse the theme-aware border token.
grep -Fq '{data.guest && (' frontend/src/pages/WifiPage.tsx
grep -Fq 'role="separator" aria-label="기본 Wi-Fi와 게스트 Wi-Fi 구분" class="mt-5 w-full border-t border-slate-200"' frontend/src/pages/WifiPage.tsx
grep -q 'onUpdateGuest={wifi.updateGuest}' frontend/src/app/App.tsx
grep -q 'updateGuestWifi' frontend/src/hooks/useWifi.ts
grep -Fq 'guestError: resource.data?.guestError ?? false' frontend/src/hooks/useWifi.ts

echo 'guest Wi-Fi security and UI contract: PASS'
