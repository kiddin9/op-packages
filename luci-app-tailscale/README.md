# luci-app-tailscale

Tailscale is a zero config VPN for building secure networks.

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/Kingwong55/luci-app-tailscale?style=flat-square)](https://github.com/Kingwong55/luci-app-tailscale/releases)
[![GitHub stars](https://img.shields.io/github/stars/Kingwong55/luci-app-tailscale?style=flat-square)](https://github.com/Kingwong55/luci-app-tailscale/stargazers)
[![License](https://img.shields.io/github/license/Kingwong55/luci-app-tailscale?style=flat-square)](LICENSE)
[![GitHub All Releases](https://img.shields.io/github/downloads/Kingwong55/luci-app-tailscale/total?style=flat-square)](https://github.com/Kingwong55/luci-app-tailscale/releases)

> Fork from [asvow/luci-app-tailscale](https://github.com/asvow/luci-app-tailscale)，基于 v1.2.6 定制开发。

## ✨ 新增功能

- **一键更新 Tailscale 内核** — 在 LuCI 设置页面直接检查并更新 Tailscale 二进制文件
- **自动版本检测** — 页面加载时自动对比当前版本与最新版本
- **智能按钮状态** — 已是最新版本时按钮自动禁用

## 🐛 修复

- 修复接口信息页面 `ip` 命令权限错误（添加 `/usr/bin/ip` 兜底路径）
- 更新 rpcd ACL 权限配置

--------------

## How to build

- Only compatible with luci2 version

- Enter in your openwrt dir

  *1. replace the default startup script and configuration of Tailscale.*
  ```shell
  sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' feeds/packages/net/tailscale/Makefile
  ```

  *2. get luci-app-tailscale source & building*
  ```shell
  git clone https://github.com/Kingwong55/luci-app-tailscale package/luci-app-tailscale
  make menuconfig # choose LUCI -> Applications -> luci-app-tailscale
  make package/luci-app-tailscale/compile V=s # luci-app-tailscale
  ```

--------------

## How to install prebuilt packages

- Upload the prebuilt ipk package to the /tmp directory of OpenWrt
- Login OpenWrt terminal (SSH)

  ```shell
  opkg update
  opkg install --force-overwrite /tmp/luci-*-tailscale*.ipk
  ```

--------------

## Thanks
- [asvow/luci-app-tailscale](https://github.com/asvow/luci-app-tailscale) — 原版项目
- [Carseason/openwrt-tailscale](https://github.com/Carseason/openwrt-tailscale)
- [immortalwrt/luci-app-zerotier](https://github.com/immortalwrt/luci/blob/master/applications/luci-app-zerotier)
