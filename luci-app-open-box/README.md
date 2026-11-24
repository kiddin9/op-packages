# luci-app-open-box

面向 OpenWrt（兼容 `opkg` 与 OpenWrt 24.10+ / 25.12 `apk`）的 [Open-Box](https://github.com/liandu2024/Open-Box) 一体化透明代理构建包。仓库仅维护构建规则，LuCI 视图、菜单、`rpcd` ACL、`procd` 服务脚本及二进制组件均在编译阶段通过 `Makefile` 直接从上游 [Open-Box Releases](https://github.com/liandu2024/Open-Box/releases) 自动拉取铺装。

## 特性说明

- **纯上游动态拉取**：编译时直接从上游带版本号的发布包（`open-box-v$(PKG_VERSION)-linux-<arch>*.tar.gz`）提取 `openwrt/luci/`、`openwrt/initd/`、`openwrt/bin/` 与纯静态 Go 面板，避免本地固化静态文件滞后或 `dl/` 同名缓存污染。
- **双架构无污染打包**：支持 `x86_64` 与 `aarch64`，清理旧版 Node 兼容层跨架构 `.so` 与非 OpenWrt 文件，无需伪造 `libc.musl-x86_64.so.1` 依赖。
- **可选组件裁剪（`menuconfig`）**：
  - 默认（`OPENBOX_CUSTOM_COMPONENTS=n`）：单次拉取完整包（含 LuCI、Go 面板、`sing-box`、`mihomo` 与 `GeoSite/GeoIP` 数据）。
  - 开启自定义裁剪后：以轻量 `-app.tar.gz`（面板 + LuCI + 服务脚本）为基础，可独立勾选是否预置 `sing-box`、`mihomo`（未预置时支持在面板内按需下载）与 `GeoSite/GeoIP` 数据库，并支持自定义首次安装的默认面板端口（默认 `3036`）。
- **固件预编译与在线安装双兼容**：内置 `/etc/uci-defaults/99-luci-app-open-box` 与 `/lib/upgrade/keep.d/luci-app-open-box`，覆盖固件集成首次开机、`sysupgrade` 保配置升级、在线安装/升级及彻底卸载（自动清理 `nftables` 表与防火墙规则并保留 `/opt/open-box/data`）。

## 编译方式

```sh
git clone https://github.com/kiddin9/luci-app-open-box package/luci-app-open-box
make menuconfig # LuCI -> 3. Applications -> luci-app-open-box
make package/luci-app-open-box/compile V=s
```

## 上游项目与许可

- 上游仓库：<https://github.com/liandu2024/Open-Box>
- 许可说明：遵循上游 [LICENSE](https://github.com/liandu2024/Open-Box/blob/main/LICENSE) 与 [COPYRIGHT.md](https://github.com/liandu2024/Open-Box/blob/main/COPYRIGHT.md)（自有程序为闭源专有许可，第三方开源组件遵循各自原许可）。
