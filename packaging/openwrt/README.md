# OpenWrt package layer

## 25.12+ / main

主线使用 OpenWrt SDK 的标准 package Makefile，让 OpenWrt 自己决定：

- `.apk` / `.ipk` 后缀
- 包架构
- `PKG_VERSION` / `PKG_RELEASE`
- 包元数据
- `packages.adb` / package index
- 签名

核心二进制则从 `UPSTREAM.json` 指定的 upstream commit 编译得到。

## 24.10

24.10 原生是 OPKG，因此应使用同一套 package Makefile 在 24.10 SDK 中构建 `.ipk`，而不是向 24.10 提供 `.apk`。

## feed 与源码分离

源码分支：`main`

纯上游过滤分支：`upstream`

滚动安装源：`packages`

这样源码历史不会因为频繁更新二进制而膨胀。
