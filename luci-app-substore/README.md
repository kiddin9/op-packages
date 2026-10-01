# luci-app-substore

**简体中文** | [English](README.en.md)

原生 **OpenWrt / ImmortalWrt** LuCI 应用，用于管理机场 / 代理订阅：解析订阅节点、
筛选、去重、重命名与分组，再转换为客户端可用的配置格式输出。

参考 [Sub-Store](https://github.com/sub-store-org/Sub-Store) 的功能与用户体验，
独立设计与实现：不使用 Docker，不依赖外部云端服务，资源占用友好，适配低配置路由器。

![Screenshot](screenshot.png)

## 功能特性

**订阅管理**
- 新增 / 编辑 / 删除 / 更新多个订阅源
- 手动更新 + 按订阅的定时（cron）更新
- 状态总览：节点数、最近更新时间、错误信息
- 每个订阅的剩余流量 / 剩余时长，从 `subscription-userinfo` 响应头解析（仅在编辑页显示）
- **订阅代理**：通过 `http://` / `https://` / `socks4` / `socks5` / `socks5h` 代理下载订阅，
  用于订阅源直连失败时
- **组合订阅**：勾选任意子集的现有订阅（可叠加关键词包含 / 排除、去重规则）合并成一个组合，
  拥有独立名称、token 与订阅链接；源订阅更新后组合自动重算
- **本地订阅**：不填 URL，直接粘贴节点文本（YAML / URI / JSON / wg-quick `.conf`）导入，
  一次粘贴按**单一格式**识别（自动判定 YAML / URI / JSON / `.conf`，不支持多格式混排），
  或用「表单导入」按协议动态字段逐条录入节点
  （vmess / vless / ss / ssr / trojan / hysteria / hysteria2 / tuic / wireguard / socks）

**输入解析**
- 订阅格式：URI 列表、Base64、JSON、Clash YAML、sing-box JSON、V2Ray / Xray JSON、
  Surge / Surfboard / Loon / Quantumult X 配置、局域网订阅链接、wg-quick / AmneziaWG `.conf`
- 节点协议：`vmess` / `vless` / `trojan` / `shadowsocks` / `ssr` / `hysteria` / `hysteria2` /
  `tuic` / `wireguard` / `socks`（及 `http`，可由 Clash YAML / JSON 配置导入并导出，
  但不在表单导入的可选协议内 —— 它不作为代理节点对外提供订阅）
- **WireGuard / AmneziaWG**：导入并导出完整字段（`private-key` / `public-key` / `pre-shared-key` /
  `ip` / `ipv6` / `allowed-ips` / `reserved` / `persistent-keepalive` / `listen-port` / `mtu` / `dns`），
  以及 `amnezia-wg-option` 子块（Jc / Jmin / Jmax / S1–S4 / H1–H4 / I1–I5 / J1–J3 / Itime）；
  可直接粘贴 AmneziaWG 客户端导出的 `.conf` 文件内容
- **解析容错**：`ssr://` 外层同时接受标准 base64 与 base64url 字母表；缺 `server`
  或 `port` 不在 1–65535 的残缺节点在**解析阶段即丢弃**（否则会被写成 `server:` /
  `port: 0`，mihomo 与 sing-box 会拒绝加载整份配置 —— 一个坏节点废掉整个订阅）；
  含 `@` 的密码按**最后一个** `@` 切分；sing-box YAML 的嵌套 `tls:` 块
  （含 `alpn` 列表与 `utls.fingerprint`）完整展开；wg-quick `.conf` 支持行内
  `#` 注释（与 wg-quick 自身的切分语义一致），且单个坏 `[Peer]` 只跳过它自己、
  不作废整份文件；纯空白内容按「空订阅」处理，而非报「无法识别的订阅格式」

**节点处理**
- 浏览节点，按分组 / 协议筛选、关键词搜索、排序
- 节点分组：「分组」列单元格内直接修改单节点分组（XHR 无刷新保存），配合「分组:」下拉筛选
- 单节点编辑 / 删除（行尾「操作」列）；表头复选框全选、行复选框勾选后点「删除」批量删除；
  「刷新」按钮重载列表（保留当前筛选条件）
- 每次更新时生效的按订阅规则（订阅 / 组合 / 本地订阅三种表单均提供）：
  - 关键词包含 / 排除（逗号分隔，支持多关键词）
  - 协议筛选（勾选保留哪些协议，全不勾选 = 不筛选）
  - 去重（同一入口的多账号不会被误合并：去重键含各协议各自的凭据）
  - 重命名（每行一条：`旧名=新名` 精确匹配、`模式 -> 替换` 正则替换、
    `{server}_{port}_{proto}` 占位符模板）

**网络探测**（节点页）
- Ping（ICMP 延迟）、TCPing（连接延迟）、URL 测试（HTTP 延迟）
- 并行探测，显示成功数与平均延迟

**转换与输出**
- 协议转换：任意协议 → 任意协议
- SSR（`ssr://`）订阅源支持：仅能原样输出到支持它的客户端（Mihomo / Clash.Meta、Stash、
  Loon、Egern、Shadowrocket），对其余目标（sing-box、V2Ray/Xray、Surge 家族）丢弃；SSR
  不能与 vmess/vless 等其它协议互转（协议不兼容）
- 15 种输出格式（全部实现）：Plain JSON、Stash、Clash.Meta / Mihomo YAML、Clash 原版、
  Surfboard、Surge、Surge Mac、Loon、Egern、Shadowrocket、Quantumult X、sing-box、
  V2Ray / Xray、V2Ray URI、WireGuard / AmneziaWG `.conf`
  - **Clash.Meta / Mihomo**：完整输出传输参数（`ws-opts` / `grpc-opts` / `h2-opts`
    的 path、host、服务名）与 vless 的 `flow`（XTLS Vision）
  - **Clash 原版**：面向 Dreamacro Clash / ClashX / Clash for Windows，自动过滤原版不支持的
    协议（vless / hysteria2 / hysteria / tuic / wireguard）
  - **WireGuard / AmneziaWG `.conf`**：wg-quick 单接口配置，含 `[Interface]` / `[Peer]` 与
    AmneziaWG 混淆参数，可直接导入 AmneziaWG 客户端
  - **sing-box / V2Ray(Xray)**：输出**完整可用配置**（`outbounds` + 分流），而非仅有
    `outbounds` 的片段
    - sing-box：节点出站 + `selector`（手工切换）+ `urltest`（自动测速）+ `direct` / `block`，
      `route.final` 指向 `selector`，内置私网直连规则
    - V2Ray/Xray：节点出站 + `freedom`(direct) / `blackhole`(block) + `observatory` +
      `routing.balancers`（`leastPing` 自动选优），内置 `geoip:private` 直连与兜底分流
      - 仅输出 Xray 支持的协议（vmess / vless / trojan / shadowsocks / socks / http）；
        hysteria2 / hysteria / tuic / wireguard / ssr 没有对应的 outbound 类型，会被过滤
        （写成 Xray 不认识的 `protocol` 会让它拒绝加载整份配置）
    - 刻意**不含 `inbounds` / `dns`**：这两项会绑定本地监听端口、覆盖你既有的 DNS 设置，
      请在你自己的配置里维护；把本输出合并进已有配置即可
    - ⚠️ 与 2.3.x 不兼容：2.3.x 输出的是仅含 `outbounds` 的片段，需要粘进已有配置使用；
      2.4.0 起是完整配置，可直接作为单文件配置启动
- **输出合法性**：只输出目标客户端真正能加载的内容，而不是「看起来像那么回事」
  - WireGuard 的 `allowed-ips` / `reserved` / `dns` 无论来源是 YAML 列表还是逗号分隔
    字符串，一律输出为目标客户端要求的数组（mihomo 是 `[]string` / `[]uint8`，
    sing-box 是 `[]string` / `[]uint8`）；写成标量会让客户端**拒绝加载整份配置**
  - Surge 家族 / Quantumult X 的策略组成员列表会剔除**含逗号**的节点名：这些格式的
    成员列表没有引号或转义机制，名字里的逗号会被当成成员分隔符，产出两个都不存在的
    成员，客户端因「引用不存在的代理」拒绝加载整份配置；Quantumult X 的 `[policy]`
    同时只收录真正写出了 `[server_local]` 行的节点，不再产生悬空引用
  - hysteria / hysteria2 分享链接的 `insecure` 以权威字段 `skip-cert-verify` 为准，
    Clash YAML / sing-box JSON / 表单导入的节点不再丢掉「跳过证书校验」

**订阅链接**
- 每个订阅独立随机 token → 公开下载端点
  `/substore/download?token=<token>&target=<format>`，Passwall / OpenClash 等客户端可直接拉取

**LuCI 界面与国际化**
- 默认英文，运行时语言为 `zh-cn` 时自动显示简体中文

## 安装

> 包名中的版本号必须与 [Makefile](Makefile) 的 `PKG_VERSION` / `PKG_RELEASE` 保持一致
> （当前 `2.6.9-r1`）。

opkg（OpenWrt / ImmortalWrt 24.10 及更早）：

```bash
opkg install luci-app-substore-2.6.9-r1.ipk
```

apk（OpenWrt / ImmortalWrt 25.12+）：

```bash
apk add --allow-untrusted luci-app-substore-2.6.9-r1.apk
```

然后在 LuCI 菜单打开：**服务 → 订阅**。

## 使用方法

1. **添加订阅** —— 粘贴订阅 URL；可选的按订阅 cron 定时、规则或下载代理。
   无订阅源时可「添加本地订阅」：粘贴节点文本或表单逐条录入。
2. **更新** —— 下载、解析并过滤节点。
3. **浏览节点** —— 筛选（分组 / 协议 / 关键词）、排序、探测延迟；勾选复选框后「删除」
   可批量删除，行内可编辑 / 删除 / 改分组，「刷新」重载列表。
4. **导出** —— 任选 15 种格式之一，或复制订阅链接供下游客户端（Passwall / OpenClash / …）使用。

## 目录结构

```
.
├── Makefile                      # OpenWrt 包定义
├── LICENSE                       # GPL-2.0-or-later
├── root/                         # 安装内容
│   ├── etc/
│   │   ├── config/substore       # UCI 占位
│   │   └── uci-defaults/99-substore
│   ├── usr/
│   │   ├── bin/substore-cron.sh  # 按订阅 cron 执行脚本
│   │   ├── lib/lua/luci/
│   │   │   ├── controller/admin/substore.lua   # 路由 / 动作
│   │   │   └── view/substore/*.htm             # 模板
│   │   └── share/
│   │       ├── luci/menu.d/luci-app-substore.json
│   │       └── substore/*.lua    # 核心逻辑（不依赖 luci.*）
├── po/zh-cn/substore.po          # 简体中文翻译
├── docs/                         # 设计与指南
└── tests/                        # 自包含 Lua 5.1 单元测试
```

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构设计
- [docs/PLAN.md](docs/PLAN.md) — 分阶段开发计划
- [docs/BUILD.md](docs/BUILD.md) — 从 OpenWrt SDK / 源码树构建
- [docs/INSTALL.md](docs/INSTALL.md) — 安装
- [docs/SECURITY.md](docs/SECURITY.md) — 安全模型
- [docs/TESTING.md](docs/TESTING.md) — 测试
- [docs/UCODE_MIGRATION.md](docs/UCODE_MIGRATION.md) — `.htm` → `.ut`（ucode）迁移说明
- [CHANGELOG.md](CHANGELOG.md) — 更新日志
- [docs/LEGACY_ISSUES.md](docs/LEGACY_ISSUES.md) — 遗留缺陷汇总（待决定修复方案）

## 构建

将本包放入与目标固件版本匹配的 OpenWrt / ImmortalWrt SDK 或源码树：

```bash
cp -r luci-app-substore <openwrt-tree>/package/
make package/luci-app-substore/compile V=s
```

`.ipk`（或 apk 构建下的 `.apk`）生成于 `bin/packages/.../` 下。

## 开发与测试

核心逻辑为纯 Lua 5.1，不依赖 `luci.*`，无需设备即可单元测试。`tests/` 下每个测试文件自包含：

```bash
lua5.1 tests/run_tests.lua          # 或任意单个测试文件
for f in tests/*.lua; do lua5.1 "$f" || exit 1; done
```

LuCI 界面与 cron 行为仍需在目标设备上验证 —— 见 [docs/TESTING.md](docs/TESTING.md)。

## 安全

SSRF 防护（拒绝内网 / 保留 / 链路本地地址；**DNS 解析失败即拒绝**，不给
「解析不出来就放行」留绕过口）、协议白名单与端口范围校验（1–65535）、
响应体大小与超时限制、下载临时文件在每条退出路径上清理（`/tmp` 是 tmpfs）、
命令注入防护（白名单解析 + shell 引用 + 探测目标拒绝以 `-` 开头的主机名）、
公开下载端点基于 token 的访问控制、日志不含凭据。

数据落盘权限：`/etc/substore` 目录 `0700`，`subscriptions.json` 与 `nodes/*.json`
`0600`（前者含订阅 URL 与公开下载 token，后者含 uuid / 密码 / 私钥）——
`io.open` 按 umask 创建（通常 0644），同机任何用户都能读到，因此写入后显式收紧。

批量节点探测的并发上限为 16 个进程（`probe.MAX_PARALLEL`）：节点数由订阅内容决定，
不限并发会把路由器的 fd / 进程额度打满，之后 `io.popen` 静默失败。

详见 [docs/SECURITY.md](docs/SECURITY.md)。

## 许可证

[GPL-2.0-or-later](LICENSE) —— 见 [LICENSE](LICENSE) 文件。