# Building — luci-app-substore

## Prerequisites

An OpenWrt / ImmortalWrt SDK or full source tree matching the target firmware version.

## Build

Place this package under the OpenWrt tree:

```bash
cd <openwrt-sdk-or-source>
# copy or symlink the package
cp -r <path>/luci-app-substore package/
make package/luci-app-substore/compile V=s
```

The `.ipk` (or `.apk` on apk-based builds) is produced under
`bin/packages/.../luci-app-substore_*.ipk`.

简体中文翻译是**独立包**，由 `feeds/luci/luci.mk` 按 `po/<lang>/` 目录自动生成，
主包的 install 步骤**不再**打包 `.lmo`（见 Makefile 末尾的说明）：

**不需要**（也**不能**）单独编译翻译包 —— 它和主包同属
`package/luci-app-substore` 目录，由上面那条命令一并编出来：

```bash
make package/luci-app-substore/compile V=s
```

> ⚠️ `make package/luci-i18n-substore-zh-cn/compile` 是**不存在的目标**：make 的
> 目标按**目录**生成（`package/<目录名>/compile`），不是按包名。写成包名会直接
> `No rule to make target ...`（CI 曾因此整条腿失败）。
>
> 但翻译包是 HIDDEN 包（`HIDDEN:=1`），luci.mk 给它的唯一默认值是
> `LUCI_LANG_zh_Hans||(ALL&&m)`，而 SDK 的默认配置里 `ALL=n` —— 不显式打开语言
> 符号时它**不会被选中**，目录目标也就不会产出它。因此编译前要：

```bash
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
make defconfig
```

产物为 `bin/packages/.../luci-i18n-substore-zh-cn_*.ipk`，内含
`/usr/lib/lua/luci/i18n/substore.zh-cn.lmo`。目录名必须是 `po/zh_Hans/`
（`LUCI_LANG` 的键）—— 写成 `po/zh-cn/` 时 luci.mk 会静默跳过，不生成任何包。

> NOTE: stage-0 skeleton has not yet been built/verified on a target device.
> This document will be updated once the build chain is validated (see docs/PLAN.md stage 0).