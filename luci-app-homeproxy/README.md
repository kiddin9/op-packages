<div align="center">

# luci-app-homeproxy

**The modern ImmortalWrt proxy platform for ARM64 / AMD64**

基于 sing-box 1.14 内核的现代代理平台 — 简洁、高效、开箱即用。

---

</div>

## 项目定位

本项目是 [luci-app-homeproxy](https://github.com/szwjp/homeproxy) 的**分拆版本线**：以 sing-box **1.14** 内核为唯一目标，充分结合 1.14 引入的新特性进行升级，不再兼容 1.13 及更早内核。

| 版本线 | 内核要求 | 演进方式 |
| --- | --- | --- |
| **homeproxy1.14**（本项目） | sing-box ≥ 1.14 | 1.14 特性驱动，配置生成直接使用 1.14 新格式 |

## 已融入的 sing-box 1.14 特性

| 领域 | 特性 |
| --- | --- |
| DNS | `evaluate` / `match_response` / `race` 响应匹配，乐观缓存与 `store_dns`，统一 `dns.timeout` |
| 规则集 | `initial_path`、多 tag、`http_clients` 下载客户端 |
| 连接 | TUN `dns_mode` / `dns_address`，UDP NAT 参数（`udp_mapping` / `udp_filtering` / `udp_nat_max`） |
| 证书 | `tls.acme` → `certificate_provider`（`key_type` / `profile` / `account_key`） |
| 工程化 | 生成配置内置 `$schema`；运行要求 sing-box ≥ 1.14 |

## 已修复：国内域名走代理问题（r4 / r6 / r7）

**背景**

`bypass_mainland_china` 的数据路由原本只用 `geoip-cn`（按 IP 匹配国内目标）。sing-box 不会把「域名连接」的域名解析成 IP 再去匹配 IP 规则集，因此按域名访问的国内站（如字节、百度等）落到 `main-out` 走了代理，只有「裸 IP 访问国内 IP」才直连。

**修复方式**

数据路由改用 `action: resolve (prefer_ipv4)` + `geoip-cn → direct-out`——先解析域名再做 IP 匹配，由真实 IP 决定国内 / 国外（国内 IP → 直连，其余 → 代理）；数据判定不再依赖 `geosite-cn` / `geosite-noncn` 域名规则（`geosite-cn` 仍用于 DNS 路由）。

对字节、百度等国内域名，以及苹果等全球跨国企业站点更稳更友好；默认使用公共 DNS（223.5.5.5）作为国内 DNS 以降低污染概率。

**可选增强 `cn_ip_fallback`**

启用后使用 1.14 原生 `evaluate` / `match_response`：对非 `geosite-cn` 域名，若 `main-dns` 返回国内 IP，再回退到 `china-dns` 解析。

> 这版块确实很难两全，改来改去也都存在缺憾，就这样不改了，照顾大多数为准。

## 新增：规则集自动更新（r5）

为 `bypass_mainland_china` 的三个远程规则集（`geoip-cn` / `geosite-cn` / `geosite-noncn`）增加 `update_interval: '24h'`，sing-box 每 24 小时自动重新拉取 `.srs`：

- 热替换，不中断既有连接；
- 下载失败时保留旧规则集，不影响分流。

## 新增：Snell 协议与 Hysteria2 增强（r9）

面向 sing-box 1.14 的一轮收敛：补齐新协议、暴露传输层新参数，并修复 1.14 DNS 迁移的一个行为缺陷。

| 领域 | 变更 |
| --- | --- |
| **Snell（1.14 新协议）** | 客户端出站 + 自建服务端 inbound 全支持（v4 / v6、psk、多用户 `userkey`、HTTP 混淆、v6 流量整形）；订阅导入 `snell://` |
| **Hysteria2** | 新增 `disable_chrome_parrot`（Ed25519 证书服务器兼容开关）、`bbr_profile`、`hop_interval_max`（跳变间隔随机化）、`gecko` 混淆与 min/max 包长；服务端同步支持 gecko |
| **Hysteria v1** | 移除上游已废弃的 QUIC 流控调参（上游 1.16 将删除），回归 sing-box 默认 |
| **DNS** | 修正 1.14 自动迁移：legacy `ip_cidr` / `ip_is_private` 包装 `evaluate` 时继承原规则查询条件，不再对全部查询预解析 |
| **连接与交互** | TLS `handshake_timeout`；TUN `dns_mode` 缺省（hijack）与平台 DNS 劫持叠加的界面指引；规则集 merged / OR 匹配语义与 `query_type` 兼容性提示 |

> 设计取舍：Chrome QUIC 指纹（1.14 默认开启）仅在服务器证书为 Ed25519 等握手失败时才需关闭；Snell 采用 sing-box 官方实现（v5 无线协议视同 v4，不支持 v5 QUIC 代理模式）。

## 新增：规则分流与 TLS 能力补全（r10）

补齐 sing-box 1.14 在路由规则与规则集加载侧的剩余能力，并加固一处规则集配置的校验提示。

| 领域 | 变更 |
| --- | --- |
| **route `resolve`** | 新增 `disable_optimistic_cache`、`timeout`两个控件,乐观缓存增至四个选项 |
| **route / route-options** | 新增 `tls_spoof` / `tls_spoof_method`（注入伪造 ClientHello 干扰按 SNI 过滤的中间盒，需特权），LuCI 提供 SNI 与方式选择（默认 wrong-sequence） |
| **规则集加载** | 多 tag 时若 `path`/`url`/`initial_path` 缺少 `{tag}` 占位，生成器给出 `warn` 提示，配合 LuCI 表单校验与 sing-box 的硬拒绝（`missing {tag} placeholder`），三层防护避免误配 |
| **i18n** | 补齐新增文案的 zh_Hans 译文 |

## 工程化加固（r11）

一轮以可维护性与可验证性为目标的加固：重构不改变行为，测试锁住结果，经实机验证。

| 轮次 | 做了什么 | 结果 |
| --- | --- | --- |
| 重构和修复错误 | 重构：前端 TLS/传输表单收敛、generator 共享 TLS/transport 构建、`parse_uri` 拆为 13 个协议函数<br>测试：协议单测 153 条、generator 回归、LuCI 表单快照<br>修复：`executeCommand` 清理、dnsmasq 路径告警、fw4 清单单源、启动日志、PEM 校验、`wGET` 失败原因<br>工程：提高中文翻译率 CI、架构核实 | <br>parse_uri 对比零差异、generator JSON 逐字节一致、表单快照逐字段一致<br>顺带修复 3 个既有缺陷：证书上传、fw4 清理回滚、dnsmasq 路径 |

## 运行要求

- ImmortalWrt / OpenWrt ≥ 24.10+（apk 或 opkg 均可安装）
- sing-box ≥ 1.14.0（ImmortalWrt 25.12 源对应 sing-box 1.14.0-r1）
- 低于 1.14 时服务会拒绝启动并记录明确日志




<div align="center">

[![License](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](LICENSE) 版权归 ImmortalWrt.org 与各贡献者

</div>
