<div align="center">

# luci-app-homeproxy-pro

**The modern ImmortalWrt proxy platform for ARM64 / AMD64**

基于 sing-box 1.14 内核的现代代理平台 — 简洁、高效、开箱即用。

</div>

## 项目定位

本项目是试验性产品，对 [homeproxy](https://github.com/szwjp/luci-app-homeproxy) 架构重构版：以 sing-box **1.14** 内核为唯一目标，
充分利用 1.14 引入的新特性，不再兼容 1.13 及更早内核。

## 运行要求

- ImmortalWrt / OpenWrt ≥ 24.10（`apk` 或 `opkg` 均可安装）；sing-box ≥ 1.14.0 是硬要求；低于 1.14 时服务拒绝启动并记录明确日志

## 按功能性对比

### 代码组织

| 维度 | upstream 形态 | pro 形态 | 证据 |
|---|---|---|---|
| 后端架构 | 单文件巨型（`generate_client.uc` 1217 行 / 40 KB；`parse_uri.uc` ~400 行 / 15 KB） | orchestrator + 5 子层（`parser` / `config` / `generator` / `subscription` / `runtime`）+ 公共库（`homeproxy.uc` / `firewall_utils.uc`）+ table-driven adapters | `root/etc/homeproxy/scripts/{config,parser,generator,subscription,runtime}/` |
| 前端架构 | 单一 66 KB `client.js` | `client.js` thin 入口 + 8 个 Tab 模块（`access` / `common` / `dns` / `nodes` / `routing` / `subscription` / `tun_dns` / `udp_nat`）+ 共享 helpers + 集中 `RPC.declare` | `htdocs/luci-static/resources/view/homeproxy/client/` |
| 协议建模 | 单 `parse_uri.uc` 内 13 个 scheme 分支 | `parser/{uri,flatten,normalize,mapping,protocols,validator}.uc` 6 个文件 + canonical Node 模型 + adapter table | `root/etc/homeproxy/scripts/parser/` + `config/{model,adapter}.uc` |
| Tab 模块化 | 1 个 `client.js` 含 12 个 Tab 渲染 | `homeproxy.js` (1153 行 helpers) + 4 顶层 view + 8 个 `client/*.js`；helpers 集中 RPC / MD5 / validators / statusPoller / renderSectionAdd / uploadCertificate | `view/homeproxy/client/{routing,nodes,dns,access,subscription,udp_nat,tun_dns,common}.js` |

### 稳定性

| 维度 | upstream 形态 | pro 形态 | 证据 |
|---|---|---|---|
| reload 事务 | 写完直接 restart | 生成 → `sing-box check` → 新实例 probe → 健康门（连续采样）→ 提为 known-good；不健康自动回滚 | `root/etc/init.d/homeproxy` + `runtime/{config,health}.sh` |
| 健康门 | `ubus` + `pgrep` 简单轮询 | `hp_wait_service` 连续 N 次采样（默认 3/30s）+ `netstat -p` 端口归属校验；不健康自动 rollback | `runtime/health.sh:hp_wait_service` |
| UCI 1.14 迁移 | r10/r11 自述较弱 | `migrate_config.uc` 36 checks 覆盖 1.14 DNS renames / `dns_server.address` 拆分 / `rcode://` → predefined rule / `rule_set_ipcidr_match_source` rename / `block-out`/`block-dns` → `action='reject'` / `auto_firewall` 重分发 / `block-dns` default-server | `scripts/migrate_config.uc` + `tests/ucode/test_migrate_config.sh` |
| sing-box 版本门 | 无 | `hp_require_singbox()` 在 start 时显式拒绝 `<1.14`，启动失败记录明确日志 | `runtime/service.sh:hp_require_singbox` |

### 安全

| 维度 | upstream 形态 | pro 形态 | 证据 |
|---|---|---|---|
| capabilities | `CAP_SYS_PTRACE` + `CAP_NET_RAW` + `CAP_NET_ADMIN` + `CAP_NET_BIND_SERVICE`（4 个） | 仅 `CAP_NET_ADMIN` + `CAP_NET_BIND_SERVICE`（2 个） | `root/etc/capabilities/homeproxy.json` + arch-guard guard 12 |
| 路径白名单（cert / rule） | 仅前端 UI 校验 | `validateHomeProxyPath()` 拒 traversal + relative，限 `/etc/homeproxy/` 与 `/tmp/homeproxy_*`；`validateCertificatePath()` 限 `/etc/homeproxy/certs/` `/etc/acme/` `/etc/ssl/`；前后端列表 arch-guard 29 锁同步 | `homeproxy.uc:48 / :99` + `homeproxy.js:HP_CERT_PATH_ROOTS` |
| 订阅 token 脱敏 | 调用点各自脱敏 | `wGETVerbose()` 内部脱敏（scheme/host/port 保留，userinfo / path / query 全脱；mock 与生产 `redactUrl` 由 arch-guard 35 锁一致） | `homeproxy.uc:226 (redactUrl)` + arch-guard 14 / 35 |
| crontab 权限 | `sed -i`（GNU-only）+ mv 后留给 0644 | `sed + mv` 跨 busybox / GNU / BSD + `chmod 600` 修 root crontab 0644 → 0600 | `runtime/service.sh:hp_crontab_drop` |
| procd jail mount | 默认未对所有模式 mount | tun/wireguard 自动 unjail（要 host netns），其他模式 mount HP_DIR + /etc/acme + /etc/ssl + /tmp/dhcp.leases + /etc/localtime + /etc/TZ | `runtime/service.sh:hp_procd_client_instance` |
| cert upload 并发 | 4 个按钮共用 `/tmp/homeproxy_certificate.tmp` | 4 个按钮各自 `/tmp/homeproxy_cert_<name>.tmp`，ACL 显式列 4 个写路径 | `homeproxy.js:uploadCertificate` + `acl.d/luci-app-homeproxy.json` |
| firewall 字段白名单 | 部分值校验 | `firewall_pre.uc` `tun_name` 严格 `^[A-Za-z0-9_.-]{1,15}$` 防 nft 注入；`firewall_post.ut` 每个 UCI 派生值走 `*_to_nftarr()` 校验器（guard 11 锁模板全覆盖） | `firewall_pre.uc:32` + `firewall_utils.uc` |

### 测试 / CI

| 维度 | upstream 形态 | pro 形态 | 证据 |
|---|---|---|---|
| 架构守卫 | 无 | `tests/arch-guard.sh` **36 个 guard / 131 个 check** 锁跨文件一致性（UCICONFIG_DIR / ACL / capabilities / conffiles / CERT_PATH_ROOTS / `redactUrl` mock / uCode 语法 / sing-box floor / adapter 共享表 / …） | `tests/arch-guard.sh` (guards 1-19, 21-37) |
| 测试规模 | 7 个脚本 / 约 27 个 check | `tests/` 下 78 个文件：ucode 套件 + 7 个 frontend 验证器 + golden snapshot + mocks + 离线 runtime 测试；arch-guard 单跑 131 个 check | `tests/print-stats.sh` 实测 |
| CI | `build` + `i18n` 两条平行 workflow | `build` 用 `workflow_call` 依赖 `arch-test`；`arch-test` 8 步（翻译 fast gate → toolchain cache → toolchain 校验 → `tests/run.sh` 唯一套件入口 → 模板检查）；`on-target` 手动 ssh + 不安装 | `.github/workflows/{arch-test,build,on-target}.yml` |
| uCode dialect pin | 跟随 upstream HEAD（已放宽） | pin `UCODE_REV=2026.01.16~85922056` + `test_ucode_grammar.sh` canary 锁 strict 语法（拒 `export function … }` 无 `;`、对象/数组解构） | `tests/toolchain/build-ucode-linux.sh:UCODE_REV` + `tests/ucode/test_ucode_grammar.sh` |
| MD5 实现 | 388 行 minified snippet；vmess 分支漏 `vmess_global_padding` | RFC 1321 完整实现 + `tests/frontend-md5.js` 锁 RFC 向量 + 与 Node `crypto.createHash('md5')` 双向 cross-check（44 / 44 PASS） | `homeproxy.js:calcStringMD5` + `tests/frontend-md5.js` |

### UX / Ops

| 维度 | upstream 形态 | pro 形态 | 证据 |
|---|---|---|---|
| Status 语义 | 2 态（RUNNING / NOT RUNNING） | 3 态（+ **STATUS UNKNOWN** 黄），区分 "rpc 没回" vs "service 死了" | `homeproxy.js:statusLabel` + `client.js:renderStatus` |
| 前端特异性 bug 修复 | `stubValidator` 缺 `factory` 致 ip6addr TypeError；`L.bind(hp.renderSectionAdd, …)` 把 factory 塞 `extra_class` 槽致 `InvalidCharacterError` | 已修：`stubValidator` 持 `factory: validation`；`renderSectionAdd` 改薄 wrap（arch-guard 22 / 23 锁 binding 形态） | `view/homeproxy/client.js:73` + `homeproxy.js:999` |
| 协议增改成本 | 改 110 行 ternary（README 旧行） | 改 5 个表行：`model.uc CREDENTIALS` + `loader.uc PROTOCOL_OPTIONS` + `adapter.uc OPTION_FIELDS` + `fixtures/` + golden snapshot；arch-guard 5 强制 fixtures 同步 | `config/{model,loader,adapter}.uc` + `tests/fixtures/generators/` |
| 资源更新 | jsdelivr 单一镜像 | 4 镜像 fallback（`fastly.jsdelivr.net` / `gcore.jsdelivr.net` / `cdn.jsdelivr.net` / `raw.githubusercontent.com`）+ UI「上次成功时间」（arch-guard 17 / 18 锁） | `runtime/dns.sh` + arch-guard 17 / 18 |
| ECH 上传 | 后端 case 缺失 | 补齐 `client_ech_conf` 标签 + `isValidECHConfig()` PEM 校验；ACL 显式列 4 个 tmp 路径 | `homeproxy.uc:isValidECHConfig` + `luci.homeproxy:certificate_write` |
| 默认测试主机 | 硬编码作者内网 IP | `HP_TEST_HOST` 注入，未设时 fail-fast；`on-target.yml` ；ssh 前 `ssh -o ConnectTimeout=5` 先确认可达（不要从记忆里写地址） | `tests/run.sh` + `.github/workflows/on-target.yml` |
| 文档 | 标准（README + CONTRIBUTING + SECURITY） | 精简（README only），`docs/` 自 2026-09-16 起只留本地（untrack + `.gitignore`），远端公开仓库不再发布 | `README.md` + `docs/`（本地） |
| 路由 ops | — | 替换文件只动 JS / menu / acl / rpcd ucode（reload 不影响网络）；更深层改动前 `cp /etc/config/homeproxy /tmp/hp-r<NN>-preflight-<DATE>/`，保留上一发版 .apk 24h；`killall -HUP rpcd` 由 apk scripts 自动做 | `runtime/{config,service}.sh` |

**一句话总结**：pro 的核心价值是**把"单文件能跑"变成"orchestrator + table-driven adapter + 可独立测试的模块"**，并把约束、质量、回滚三件事从靠人盯变成靠代码执行（arch-guard 131 checks 静态锁住跨文件不变量）。

## 与七尺宇 demo 的对照

> 教程《sing-box 1.14 配置文件精讲》(BV `B6zcuUo2bJ0`) 在 B 站放出了一份配套 `linux.json` + 9 张示意图，演示 sing-box 1.14 的新特性和底层分流逻辑。pro 在那之上做了更多工程化的工作，本节把两者的边界划清，方便后来人评估"该不该跟 demo 走"。

### pro 已经做到的（demo 的全部主线字段 + 实战打磨）

| demo 的字段/能力 | pro 是否实现 | 证据 / 说明 |
|---|---|---|
| `$schema` 顶层 | ✅ 已实现 | `attachSchema()` in `generator/common.uc` |
| `http_clients` + `http_client` | ✅ 已实现 | `generator/ruleset.uc:build_http_clients()` 1.14 规范改写 |
| `dns.servers` 8 类（local / https / tls / fakeip / hosts / udp / tcp / ...） | ✅ 已实现 | `generator/dns.uc` 自研 parser 覆盖全部 UCI 类型 |
| `dns.rules` D① 拒 HTTPS/SVCB | ✅ proxy mode line 102 / ✅ custom mode 新前置 | arch-guard 38 锁顺序 |
| `dns.rules` D② clash_mode 切换 | ⚠️ 故意没做（见下表） | — |
| `dns.rules` D⑥ evaluate + D⑦ match_response | ✅ **v28.9.1.16 默认 '1'** (新装);存量用户由 `migrate_config.uc` 写 '0' 锁住 | `generator/dns.uc:142-154` + `migrate_config.uc` |
| `dns.rules` reject + `no_drop` | ✅ 已完整 | `route.uc:279` |
| `dns.servers` hosts + predefined（DoH 兜底） | ✅ auto-detect + auto-emit | `generator/dns.uc:KNOWN_ENCRYPTED_DNS_HOSTS` |
| `route.rules` action: bypass 复合规则 | ⚠️ 故意走 `resolve + geoip-cn`（v2 路线图阶段 3 候选） | pro 注释：geosite 误判 gvt2.com 等 |
| `route.rules` action: route-options (override_address/port) | ✅ 已完整 | `route.uc:114-118, 284-292` |
| `route.rules` rule_set 数组化 + `{tag}` 占位符 | ✅ 已完整 | `ruleset.uc:38-87` |
| `route.rules` sniff sniffer list + 100ms | ✅ opt-in UCI `sniffer_advanced_mode`（默认 '0' = 300ms / 默认列表）| `generator/route.uc:46-60` |
| `route.rules` clash_mode Global → GLOBAL | ⚠️ 故意没做 | 见下表 |
| `experimental.cache_file` + `store_dns` | ✅ UCI Flag | `dns.js:43` |
| `experimental.reverse_mapping` | ✅ **v28.9.1.15 起显式 emit** | `common.uc:198`,arch-guard 39 |
| **v28.9.1.16 迁移安全**:cn_ip_fallback 默认 '1' + migrate 写 '0' 锁存量 | ✅ 默认开 + 升级不感知 | `context.uc:184` + `migrate_config.uc` log_level 旁 |
| `default_domain_resolver` | ✅ 已完整 | `route.uc:65-67, 188-190` |
| `ntp` 顶层块 | ⚠️ 故意没做（路由器已有 chrony） | — |

### pro 故意没做的（demo 有，pro 不要）

| 项 | 排除理由 |
|---|---|
| **22 个 selector 的"业务向"策略组（默认代理 / YouTube / Telegram / Netflix / Wallet / ...）** | LuCI 用户不需要这么细，pro 把"分流策略"和"具体规则"解耦（4 模式 + 用户自配 routing_rule），v2 路线图已表态 |
| **`clash_mode` 联动 DNS rules / final** | pro 范式是"面板模式与 DNS 行为解耦"，v2 路线图批次 2 候选 |
| **bridge outbound**（windows.json） | Windows 专属，路由器用不上 |
| **momo 6 入站网关模式** | 路由器不当网关客户端 |
| **sub-store 集成**（xream/template.js + URL 参数） | 外依赖风险 + 跟 pro 自研范式冲突 |
| **providers 拉取模式**（reF1nd 风格的 use_all_providers + regex） | UCI subscription 已覆盖 90% 用户 |
| **`services.api` + dashboard UI** | LuCI 已是 UI，不需要再加一层 |
| **FakeIP 模式** | v2 路线图阶段 4 候选（feature flag + 隔离大议题），默认不开 |
| **`strategy: ipv4_only` for `default_domain_resolver`** | pro 用 `prefer_ipv4` —— sing-box 默认就降级到 IPv6，对国内多数场景更友好 |

### pro 超出 demo 的工程化（demo 没有，pro 必须有）

| 维度 | pro 实际状态 | 证据 |
|---|---|---|
| 重新加载事务 + 健康门 + 自动回滚 | 生成 → check → probe → 健康门 → known-good；不健康自动 rollback | `runtime/{config,health}.sh` |
| UCI 1.14 迁移 | 36 checks | `migrate_config.uc` |
| sing-box 版本门 | `hp_require_singbox()` 启动显式拒绝 `<1.14` | `runtime/service.sh` |
| arch-guard 静态锁 | **131+ checks** 锁跨文件不变量 | `tests/arch-guard.sh` |
| 测试规模 | 78 测试文件 / 131 check | `tests/print-stats.sh` 实测 |
| Capabilities 收紧 | 仅 NET_ADMIN + NET_BIND_SERVICE（去 PTRACE / NET_RAW） | `homeproxy.json` + arch-guard 12 |
| 路径白名单 | traversal/relative 拒绝 + 限 3 个根 | `homeproxy.uc:48/99` + `homeproxy.js:HP_CERT_PATH_ROOTS` |
| Status 语义 | 3 态（RUNNING / **STATUS UNKNOWN 黄** / NOT RUNNING） | `homeproxy.js:statusLabel` |
| 路由 ops 流程 | 替换文件不重启服务；`killall -HUP rpcd` 由 apk scripts 自动 | `runtime/{config,service}.sh` |

## 推荐 rule_set 源

如果你想自己跑 binary `.srs` 格式的规则集（而不是 pro 内置的 `china_list.txt` / `gfw_list.txt` 文本），下面三个仓库是 sing-box 官方维护的（教程 demo 也用这套）：

| 类型 | 来源 | 格式 | 适用 |
|---|---|---|---|
| **geosite-cn** | `https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs`（通过 gh-proxy.com 加速） | binary | 国内域名（直连） |
| **geosite-geolocation-!cn** | `.../sing-geosite/rule-set/geosite-geolocation-!cn.srs` | binary | 海外域名（代理） |
| **fakeip-filter-cn** | `https://raw.githubusercontent.com/qichiyuhub/rule/main/rules/fakeip-filter-cn.json` | source | FakeIP 模式的国内例外清单 |
| **geoip-cn** | `https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs` | binary | 国内 IP（evaluate fallback） |

> **教程明确反对 Mihomo 规则库**：Mihomo 的 `cn.srs` 文件名会与 sing-box 同名冲突，导致标签解析失败。
> pro 的默认 `china_list.txt` 仍是文本格式（教程 demo 没暴露这种兼容路径），但你随时可在 LuCI 添加 binary `.srs` 规则集替换。

## 已知限制

- **试验性**：不承诺 API/配置稳定，重大变更可能在 minor 版本里发生。
- **真机实测单平台**：本仓库只在 x86-64 软路由上做过端到端验证。
- 本包不会编译 sing-box。系统固件必须自带 sing-box 1.14+;否则依赖解析直接失败。

## 贡献

欢迎 issue / PR。架构边界规则是可执行的，固化在 `tests/arch-guard.sh`（PR 必跑，
每条规则都注明对应的 guard）；架构层面的变更请先开 issue 讨论，避免在
PR review 里来回拉扯。

## License

[GPL-2.0-only](LICENSE) — 版权归 ImmortalWrt.org 与各贡献者。
