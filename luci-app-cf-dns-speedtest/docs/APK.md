# OpenWrt APK 安装包

面向 OpenWrt 25.12.5 / APK v3；MU300 / U30 Air 目标架构为 `aarch64_generic`。这不是安卓应用。保留原有 IPK 供 opkg 系统使用。

```sh
apk update
apk add --allow-untrusted ./mosdns-5.3.4-r14.apk ./luci-app-cf-dns-speedtest-*.apk
```

本包未签名，仅在核对本发布页 SHA256SUMS 后安装。保留 `/etc/config` 中已有配置。

构建：Linux 上设置 `APK` 为 OpenWrt 25.12.5 SDK 中的 `staging_dir/host/bin/apk`，运行 `sudo --preserve-env=APK python3 tools/build_apk.py`。也可手动运行 GitHub Actions 的 Build OpenWrt APK。源文件只从 Git 跟踪清单读取，排除截图、缓存和历史安装包；源码包不含 Git 历史或本机路径。

验证覆盖原生 APK v3 打包与解包、逐文件内容校验及已有自动测试；未声称已在实体 U30 Air 上完成安装或联网验证。

APK 使用上游 XIU2/CloudflareSpeedTest v2.3.5 的 ARM64 程序，下载校验值固定在构建脚本中，并验证 ELF 架构。Git 中的 amd64 程序继续用于原有 x86_64 IPK，APK 不会使用它。程序遵循 GPL-3.0-only，源码：https://github.com/XIU2/CloudflareSpeedTest/tree/v2.3.5 。

官方 OpenWrt 软件源不含 mosdns，因此发布同时附带 sbwml/luci-app-mosdns v5.3.4-r14 的 aarch64_generic / OpenWrt 25.12 运行程序包。上游压缩包 SHA-256 在构建脚本中固定；只提取 mosdns APK，不安装上游 LuCI 插件、DNS 配置或地理数据库。依赖包保留上游原始文件及签名，遵循 GPL-3.0；对应构建配方与补丁：https://github.com/sbwml/luci-app-mosdns/tree/v5.3.4-r14/mosdns ，上游源码：https://github.com/IrineSistiana/mosdns/tree/v5.3.4 。
