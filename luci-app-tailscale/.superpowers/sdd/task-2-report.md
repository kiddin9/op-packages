# Task 2 Report: Menu and ACL

Status: completed

Date (UTC): 2026-07-13 18:45:31 UTC

## Implemented
- Added menu route entry assertions in `tests/package_release_test.sh`:
  - `admin/vpn/tailscale/peers`
  - `"title": "Peers"`
  - `"path": "tailscale/peers"`
  - order assertions before interface and log routes.
- Added ACL assertion in `tests/package_release_test.sh` for:
  - `"/usr/sbin/tailscale_peer_probe": [ "exec" ]`
- Updated `root/usr/share/luci/menu.d/luci-app-tailscale.json`:
  - inserted `admin/vpn/tailscale/peers` with title `Peers`, order `25`, and view path `tailscale/peers`.
- Updated `root/usr/share/rpcd/acl.d/luci-app-tailscale.json`:
  - added `"/usr/sbin/tailscale_peer_probe": [ "exec" ]` under `"read" -> "file"`.

## Verification
- `sh tests/package_release_test.sh`
  - before implementation: failed at missing `admin/vpn/tailscale/peers` assertion
  - after implementation: `package release tests passed`

## Follow-up Fix (Task 2.i)
- Added localization entry for menu title `Peers` to `po/templates/tailscale.pot` with references to `root/usr/share/luci/menu.d/luci-app-tailscale.json:30`.
- Added `msgstr "对端列表"` for Simplified Chinese in `po/zh_Hans/tailscale.po`.
- Added `msgstr "對端列表"` for Traditional Chinese in `po/zh_Hant/tailscale.po`.
- Added focused assertions in `tests/package_release_test.sh` for:
  - `msgid "Peers"` in `po/templates/tailscale.pot`, `po/zh_Hans/tailscale.po`, `po/zh_Hant/tailscale.po`
  - `msgstr "对端列表"` in `po/zh_Hans/tailscale.po`
  - `msgstr "對端列表"` in `po/zh_Hant/tailscale.po`
- Ran:
  - `sh tests/package_release_test.sh`
  - Result: `package release tests passed`
