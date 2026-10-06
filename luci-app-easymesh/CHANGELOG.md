# EasyMesh 2.4.1-r1

LuCI interface for Batman-adv 802.11s mesh on OpenWrt / ImmortalWrt.

## Changes since upstream

- De-integration of DAWN for Usteer pre-installed devices (conflict-free install, better performance)
- Optional cron fallback for priority reapplication (UI checkbox, default off)
- Live latency monitoring for wireless peers (smoothed over 3 pings)
- Live RX/TX bandwidth rates for wireless and wired links
- Neighbor MAC + last-seen for wired backhaul (from batman originator table)
- Robust priority read (tries multiple batctl syntaxes)
- Hotplug integration for priority reapplication on interface up
- 90-second priority retry loop + second-pass catchup in init script
- Removed `+wpad-mesh` dependency (fixed kconfig recursive dependency)
- Meta packages for `wpad-openssl` / `wpad-wolfssl` / `wpad-mbedtls` variants
- WPS handler `/etc/rc.wps/easymesh-pair` (no conflict with wifi-scripts)
- বাংলা (Bengali) Language → now supports full Bengali UI 

**Mesh features**

- Editable link priority weights in UI — wired, 6 GHz, 5 GHz, 2.4 GHz
- Priority Weight column for wireless peers (previously wired-only)
- Mesh VLANs — extend guest / IoT / hotspot networks over the mesh via 802.1Q
- Comma-separated VLAN IDs in UI (e.g. `10,20,30`)
- Auto-attach to `br-<vid>` / `br-guest<vid>` / `br-iot<vid>` bridges
- Safe re-apply (removes previous 802.1Q devices first)

**Documentation**

- English README with screenshots
- Bengali (বাংলা) README — `docs/bn`
- Bengali glossary — 80+ networking terms
- Language switcher on both READMEs

## Bundle

`easymesh-pkg-2.4.1-r1.zip` (1.6 MB): 6 IPK + 6 APK + full source + Bengali docs (README, glossary, 7 screenshots) + Bengali/Chinese `.po`.

## Notes

- GitHub replaces `~` with `.` in **asset names on this page** (`…37259.7cad107…`). Files inside the bundle keep the original `~`. Package metadata is unchanged — `opkg` / `apk` read the version from inside the package.
- Tag `2.4.1-r1` was force-moved. Re-download if you pulled an earlier build.
- SAE mesh encryption is driver-limited on ath10k / MT7915E — mesh runs unencrypted.

## Credits

- **Original authors:**
  - dz <dingzhong110@gmail.com>
  - torguardvpn — [torguardvpn/luci-app-easymesh](https://github.com/torguardvpn/luci-app-easymesh)
- **Upstream forks:**
  - [ntlf9t/luci-app-easymesh](https://github.com/ntlf9t/luci-app-easymesh)
  - [kenzok78/luci-app-easymesh](https://github.com/kenzok78/luci-app-easymesh)
  - [torguardvpn/luci-app-easymesh](https://github.com/torguardvpn/luci-app-easymesh)
- **Bugfix branch:** [mobing8/luci-app-easymesh-dawn](https://github.com/mobing8/luci-app-easymesh-dawn)
- **Current maintainer:** Arafat Rahman Zami Mondol — [@arafatrahmanzami](https://github.com/arafatrahmanzami) · [open an issue](https://github.com/arafatrahmanzami/luci-app-easymesh/issues/new)


*Preview (screenshots)*
<img width="1484" height="828" alt="01-dashboard" src="https://github.com/user-attachments/assets/8206e3b0-6a32-417a-a03e-76472b07b636" />




<img width="1784" height="666" alt="07-priority-vlans" src="https://github.com/user-attachments/assets/c573dad7-2f46-422e-94b4-7021327ec061" />




<img width="1423" height="820" alt="02-quick-setup-1-9" src="https://github.com/user-attachments/assets/641072db-b72f-439d-90e4-3ba14a599877" />





<img width="1356" height="867" alt="03-quick-setup-10-19" src="https://github.com/user-attachments/assets/f665db1c-0c42-4367-b3eb-587de7a49b01" />




<img width="1430" height="874" alt="04-mesh-settings" src="https://github.com/user-attachments/assets/abfc5ee7-108e-4e9d-9625-5dcb1fc03321" />




<img width="489" height="1012" alt="05-client-wifi-ap-mode" src="https://github.com/user-attachments/assets/7dd6097f-b4f4-4021-9c56-41ed5c8628b9" />



<img width="1355" height="504" alt="06-wired-backhaul-safety" src="https://github.com/user-attachments/assets/84543c6b-f5a2-4aed-9d97-f35c3a8bc4f7" />



## Installation example

Pick the wpad meta package matching your TLS backend, then the app, then i18n.

**OpenWrt ≤ 24.10 (opkg, openssl)**
```sh
cd /tmp
opkg install luci-app-easymesh-wpad-openssl_2.4.1-r1_all.ipk
opkg install luci-app-easymesh_2.4.1-r1_all.ipk
# optional
opkg install luci-i18n-easymesh-bn_26.184.37259.7cad107_all.ipk
/etc/init.d/uhttpd restart
```

**OpenWrt ≥ 25.12 (apk,wolfssl)**

```sh
cd /tmp
apk --allow-untrusted add /tmp/luci-app-easymesh-wpad-wolfssl-2.4.1-r1.apk
apk --allow-untrusted add /tmp/luci-app-easymesh-2.4.1-r1.apk
# optional
apk --allow-untrusted add /tmp/luci-i18n-easymesh-bn-26.184.37259.7cad107.apk
/etc/init.d/uhttpd restart
```

> The meta depends on `wpad-mesh-*` (not `wpad-*`). `apk verify` reports `UNTRUSTED signature` — expected, harmless; that's why `--allow-untrusted` is required.

**Bengali UI:** System → System → Language and Style → Language → **বাংলা (Bengali)**

> All packages are `PKG_ARCH=all` — universal across every router CPU.

