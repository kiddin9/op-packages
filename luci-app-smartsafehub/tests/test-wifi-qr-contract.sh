#!/bin/sh
# Wi-Fi QR authentication and sensitive-data regression contract.
set -eu
cd "$(dirname "$0")/.."
grep -q 'wifi_qr: {' root/usr/share/rpcd/ucode/smartsafehub.uc
grep -q 'return read_wifi_qr(request)' root/usr/share/rpcd/ucode/smartsafehub.uc
grep -q 'require_root_password(function(request)' root/usr/share/rpcd/ucode/smartsafehub.uc
grep -q 'wifi_is_managed_section(ctx, section_name, device)' root/usr/share/rpcd/ucode/smartsafehub/wifi-management.uc
grep -q 'passwordConfigured: length(key) > 0' root/usr/share/rpcd/ucode/smartsafehub/wifi.uc
if grep -q 'password: key' root/usr/share/rpcd/ucode/smartsafehub/wifi.uc; then echo 'FAIL: wifi summary leaks password'; exit 1; fi
grep -q 'wifi_qr' root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json
grep -q 'QR 코드 보기' frontend/src/pages/WifiPage.tsx
grep -q 'TextEncoder' frontend/src/utils/qrMatrix.ts
# The PNG is generated in-browser from the same QR matrix; no new RPC endpoint.
grep -q 'drawWifiQrPng(qr.matrix, context, moduleSize)' frontend/src/components/WifiQrDialog.tsx
grep -q "canvas.toDataURL('image/png')" frontend/src/components/WifiQrDialog.tsx
grep -q 'link.download = wifiQrFilename(qr.ssid)' frontend/src/components/WifiQrDialog.tsx
grep -q 'QR 코드 다운로드' frontend/src/components/WifiQrDialog.tsx
grep -q '카메라로 스캔해 Wi-Fi에 연결하세요' frontend/src/components/WifiQrDialog.tsx
grep -q 'QR 코드에는 비밀번호가 포함됩니다' frontend/src/components/WifiQrDialog.tsx
[ "$(grep -c 'span class="block"' frontend/src/components/WifiQrDialog.tsx)" -ge 2 ]
printf 'wifi QR contract: PASS\n'
