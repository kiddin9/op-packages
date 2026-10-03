# luci-app-cf-dns-speedtest — Cloudflare DNS IP 优选插件

适用于 OpenWrt / iStoreOS 的 Cloudflare DNS 优选插件。它调用
[XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 测出较优的
Cloudflare Anycast IPv4 地址，再通过独立 mosdns 旁路实例仅回答用户指定的域名。

## 设计边界

- 不替换 dnsmasq 的默认上游。
- 不关闭或绕过 AdGuardHome、SmartDNS 等现有 DNS 服务。
- 只有配置列表内的域名会转发到本插件的 mosdns 端口。
- 测速失败时保留上一次成功的 IP 和 DNS 配置。

## v1.1.0 改进

- 修复定时任务未写入 crontab。
- 精确记录并清理本插件拥有的 dnsmasq 分流规则，端口变更不再残留旧规则。
- 日志和诊断输出设置硬上限，避免长期运行占用闪存。
- 增加停止测速、上次测速时间和定时任务状态。
- 增加参数范围、测速 URL 和 IPv4 结果校验。
- 测速失败不覆盖上次结果，并尝试恢复上次可用 DNS 配置。
- 修复 LuCI 中文乱码，优化窄屏状态卡和结果表格。

## 兼容性

- 已测试：iStoreOS 24.10.8，x86_64，Linux 6.6.144。
- Release 中的 IPK 内含 x86_64 `cfst`，不可安装到 ARM/MIPS 设备。
- 依赖：`luci-base`、`mosdns`。

## 安装

```sh
opkg install ./luci-app-cf-dns-speedtest_1.1.0-1_x86_64.ipk
```

升级会保留 `/etc/config/cf_dns_speedtest`。安装完成后进入
“服务 → Cloudflare DNS 优选”，保存设置并点击“应用 DNS 配置”。

## 文件与服务

- `/etc/config/cf_dns_speedtest`：UCI 配置。
- `/usr/bin/cf-dns-speedtest`：`start|run|stop|apply|status|ui`。
- `/var/lib/cf-dns-speedtest/`：测速结果和生成的旁路 mosdns 配置。
- `/etc/init.d/cf-dns-speedtest`：独立 mosdns 实例。

## 第三方组件与许可

本项目整体以 GPL-3.0-only 发布。内置的 `cfst` 来自
[XIU2/CloudflareSpeedTest v2.3.5](https://github.com/XIU2/CloudflareSpeedTest/releases/tag/v2.3.5)，
该项目同样采用 GPL-3.0。Cloudflare、OpenWrt、iStoreOS、mosdns 和
CloudflareSpeedTest 均为其各自权利人的项目或商标，本项目与其不存在官方隶属关系。
