<div align="center">

## 新增本仓库“架构重构”试验性产品luci-app-homeproxy-pro
(https://github.com/szwjp/luci-app-homeproxy-pro)

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

## 稳定性修复（r12）

修掉两个会让功能整体不可用的缺陷，均由 issue 复现确认。

| 领域 | 变更 |
| --- | --- |
| **订阅抓取**（#5） | 抓取前先探测 wget 实现：GNU wget 用 `-nv`（静音进度条但保留失败原因），uclient-fetch / busybox wget 用 `-q`；`--user-agent` / `--timeout` 一并换成三家通用的 `-U` / `-T`。r11 引入的 `-nv` 是 GNU 专有选项，而 OpenWrt / ImmortalWrt 的 `/usr/bin/wget` 默认由 uclient-fetch 提供，参数解析阶段即失败，导致所有订阅更新以 `no valid node found` 结束 |
| **自定义路由**（#3 #4） | 修复 `routing_mode='custom'` 完全无法生成配置：`direct_overrides` 的使用早于声明（ucode 不做变量提升，strict 模式下直接抛未声明变量）；本地规则集残留 legacy `download_detour` 字段，被 sing-box 判为 `unknown field` 而拒绝整个配置 |
| **预设规则集** | `geoip-cn` / `geosite-cn` / `geosite-noncn` 改用 SagerNet 上游 raw URL，并经 `main-out` 下载：直连受 DNS 污染时会超时并静默沿用缓存；每天约 250 KB 的代理开销可忽略，节点引导不受影响 |
| **依赖** | Makefile 补上 `+ip-full`、`+kmod-tun` |

> 回归保障：订阅抓取用 stub wget 覆盖 GNU / 非 GNU 两条分支，并在装有 `/bin/uclient-fetch` 的目标上直接执行生成的命令行；自定义路由新增 `custom.uci` fixture（本地规则集 + 直连节点覆盖 + 路由规则）。

## 安全与可用性修复（r13）

一轮以"资源/订阅链路真正生效"和"收敛暴露面"为目标的修复，全部结论都做了实机或本地复现。

| 领域 | 变更 |
| --- | --- |
| **资源更新生效** | `update_resources.sh` 的 `--header-file=` 改为 `--header=`——uclient-fetch 与 GNU wget 都不认 `--header-file`，填了 GitHub token 时四个清单的版本探测会全部失败；新增 `/etc/init.d/homeproxy refresh_lists`，清单下载后重建 fw4 集合与 dnsmasq 片段（此前 cron 只改磁盘文件，只有订阅更新"顺带"重启时才真正生效） |
| **规则集** | 删除无人引用的 `geosite-noncn`（sing-box 会初始化每一个声明的远程规则集，引用与否都会下载、失败即拒绝启动）；`geoip-cn` / `geosite-cn` 在本地 `.srs` 存在时生成为 `type: local`，否则回退远端——cron 经 jsdelivr 固定 commit 下载，冷启动不再依赖"经节点拉 CDN" |
| **订阅与导入** | 入库前按协议校验必需字段并跳过坏节点（此前一个坏节点会让整份配置生成失败、看似更新成功却一直跑旧配置）；`flow` 只保留 `xtls-rprx-vision`；SS userinfo 先做百分号解码（`%3D` 不再丢 method/password）；`simple-obfs` 归一化为 `obfs-local`；不支持的 transport（xhttp 等）直接跳过；订阅更新加 mkdir 锁；`update_via_proxy=1` 时配置变更也会重启；日志中的订阅 URL 脱敏 |
| **暴露面** | 生成的客户端/服务端配置权限改为 600（含全部节点凭据）；capabilities 去掉 `CAP_SYS_PTRACE` / `CAP_NET_RAW`；`dns-in` 只监听 `127.0.0.1`（此前 LAN 内可把它当解析器用）；custom 路由模式也进 ujail；core dump 关闭（`core=0`） |
| **DNS** | `dns.servers[].headers` 由界面列表转成 1.14 要求的 map（此前填 Headers 会让整份配置非法）；`action: route` 缺 server 的 DNS 规则跳过并告警；`tls_fragment_fallback_delay` 单位修正为毫秒（原先被当成秒，放大 1000 倍）；新增 `block_https_rr` 开关（默认仍拦截 HTTPS/SVCB，需要 ECH 时关闭） |
| **健壮性** | 大响应不再被单次 512 KiB 读取截断；防火墙模板对端口/mark/IP/MAC/接口名逐一校验（非法值不再让之后每次 `fw4 reload` 都失败）；`isValidCIDR` 严格校验前缀，堵住远程清单注入 nft 模板的路径；生成失败按退出码报错而不是沿用旧配置；`log()` 先建目录，首启诊断不再丢 |
| **验证** | 新增 client 表单快照、client 生成 golden 快照（逐字节锁定生成结果）、700 KiB 读取与 CIDR 注入用例；CI 增加 shell/JS 语法检查，i18n 覆盖率由 warn 改为 fail |

> 有意未改动的项：订阅抓取仍在 `update_via_proxy=0` 时先停服（这是该选项的定义，改抓取时序会改变抓取路径）；`tls_self_sign`、`hysteria_protocol` 与 `ssh_priv_key` 的 DynamicList 展示保持与 `-pro` 分支一致，留待两线一起收敛。

### 已知限制

- DNS 劫持只重定向 UDP/53，使用 DoT/DoH 的客户端绕过它（与 OpenWrt 原生 `dns_redirect` 行为一致）。
- `bypass_mainland_china` / `custom` / `global` 下 dnsmasq 被配成 `no-resolv` + 转发给 sing-box，此时选 `system-dns` 会绕回 sing-box 自身，建议使用 `default-dns`。
- 订阅更新在 `update_via_proxy=0` 期间服务处于停止状态，订阅多或源慢时停机时间会变长；需要零中断可开启 `update_via_proxy`。

## 运行要求

- ImmortalWrt / OpenWrt ≥ 24.10+（apk 或 opkg 均可安装）
- sing-box ≥ 1.14.0（ImmortalWrt 25.12 源对应 sing-box 1.14.0-r1）
- 低于 1.14 时服务会拒绝启动并记录明确日志




<div align="center">

[![License](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](LICENSE) 版权归 ImmortalWrt.org 与各贡献者

</div>
