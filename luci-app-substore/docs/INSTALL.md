# Installation — luci-app-substore

> NOTE: stage-0 skeleton has not yet been installed/verified on a target device.
> This document will be updated once installation is validated.
>
> 包名中的版本号需与 Makefile 的 `PKG_VERSION` / `PKG_RELEASE` 保持同步（当前 2.5.0-r1）。

## Install (opkg — OpenWrt / ImmortalWrt 24.10 及更早)

```bash
opkg install luci-app-substore-2.5.0-r1.ipk
```

## Install (apk — OpenWrt / ImmortalWrt 25.12+)

```bash
apk add --allow-untrusted luci-app-substore-2.5.0-r1.apk
```

Refresh LuCI:

```bash
rm -f /tmp/luci-indexcache
/etc/init.d/luci reload
```

Then open LuCI menu: **Services → Subscriptions** (or **System → Subscriptions** depending on firmware).
