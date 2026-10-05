# Installation — luci-app-substore

> NOTE: stage-0 skeleton has not yet been installed/verified on a target device.
> This document will be updated once installation is validated.
>
> 包名中的版本号需与 Makefile 的 `PKG_VERSION` / `PKG_RELEASE` 保持同步（当前 2.7.2-r1）。

**最低支持 OpenWrt / ImmortalWrt 23.05**（更早的版本不在支持范围内 —— 23.05 起
LuCI 使用 ucode dispatcher，ACL 的入口级校验依赖它，见
[SECURITY.md](SECURITY.md)「访问控制」）。

## Install (opkg — OpenWrt / ImmortalWrt 24.10 及更早)

```bash
opkg install luci-app-substore-2.7.2-r1.ipk
```

## Install (apk — OpenWrt / ImmortalWrt 25.12+)

```bash
apk add --allow-untrusted luci-app-substore-2.7.2-r1.apk
```

## Install the Simplified Chinese translation (optional, separate package)

主包**不含**译文：界面文本是英文 msgid，简体中文由独立的翻译包提供，
不装时界面为英文。

```bash
opkg install luci-i18n-substore-zh-cn_*.ipk                 # 24.10 及更早
apk add --allow-untrusted luci-i18n-substore-zh-cn_*.apk    # 25.12+
```

该包的版本号由 `po/` 目录的提交时间推导（LuCI 的 `PKG_PO_VERSION`），
与主包的 `2.7.2-r1` 不同名，按文件名通配安装即可。它会安装
`/usr/lib/lua/luci/i18n/substore.zh-cn.lmo`，并通过 uci-defaults 把
`zh_cn` 加进 `luci.languages`；把 LuCI 语言切到「简体中文」即生效。

Refresh LuCI:

```bash
rm -f /tmp/luci-indexcache
/etc/init.d/luci reload
```

Then open LuCI menu: **Services → Subscriptions** (or **System → Subscriptions** depending on firmware).
