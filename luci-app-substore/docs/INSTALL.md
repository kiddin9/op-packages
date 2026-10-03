# Installation — luci-app-substore

> NOTE: stage-0 skeleton has not yet been installed/verified on a target device.
> This document will be updated once installation is validated.
>
> 包名中的版本号需与 Makefile 的 `PKG_VERSION` / `PKG_RELEASE` 保持同步（当前 2.7.1-r3）。

**最低支持 OpenWrt / ImmortalWrt 23.05**（更早的版本不在支持范围内 —— 23.05 起
LuCI 使用 ucode dispatcher，ACL 的入口级校验依赖它，见
[SECURITY.md](SECURITY.md)「访问控制」）。

## Install (opkg — OpenWrt / ImmortalWrt 24.10 及更早)

```bash
opkg install luci-app-substore-2.7.1-r3.ipk
```

## Install (apk — OpenWrt / ImmortalWrt 25.12+)

```bash
apk add --allow-untrusted luci-app-substore-2.7.1-r3.apk
```

Refresh LuCI:

```bash
rm -f /tmp/luci-indexcache
/etc/init.d/luci reload
```

Then open LuCI menu: **Services → Subscriptions** (or **System → Subscriptions** depending on firmware).
