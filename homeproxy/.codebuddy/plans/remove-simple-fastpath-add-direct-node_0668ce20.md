---
name: remove-simple-fastpath-add-direct-node
overview: 移除简洁模式的中国大陆防火墙 fast path（保留 custom 模式同名开关），新增一个内置 type=direct 的 UCI 节点供各模式/简洁模式规则选择，让简洁模式全部流量进入 sing-box 后由 route rules 决定去向；不内置任何默认 CN 规则，默认出站仍为 Direct。
todos:
  - id: add-builtin-direct-node
    content: 在 config/homeproxy 与 migrate_config.uc 新增幂等内置直连节点
    status: completed
  - id: refactor-generator
    content: 重构 generate_client.uc：删 fast path 并适配直连节点出站、DNS 与默认出站
    status: completed
    dependencies:
      - add-builtin-direct-node
  - id: remove-firewall-fastpath
    content: 清理 firewall_post.ut 与 init.d 的状态文件读取及残留引用
    status: completed
  - id: cleanup-ui-i18n-docs
    content: 删除简洁模式 UI 开关，清理 i18n 词条与文档描述
    status: completed
  - id: verify-consistency
    content: 用 [subagent:code-explorer] 全量核查残留并做语法与生成配置校验
    status: completed
    dependencies:
      - add-builtin-direct-node
      - refactor-generator
      - remove-firewall-fastpath
      - cleanup-ui-i18n-docs
---

## 产品概述

对现有代理工具的「简洁模式 / Simple Routing」做一次行为收敛：移除「绕过中国流量」的防火墙快速通道，改为所有流量统一进入核心程序、按用户配置的分流规则决定去向；同时新增一个可选的「直连」节点，供用户自行把指定域名、规则集或 IP 指向直连。

## 核心 Features

- 简洁模式不再提供「绕过中国流量」开关；界面、默认配置、升级迁移、状态文件与相关提示全部清理。
- 简洁模式不再在防火墙层对中国大陆 IP 提前放行，所有被接管的流量都按分流规则处理，未命中任何规则时仍走默认直连。
- 新增一个内置的「直连」节点：节点页面可见，各路由模式的节点选择中均可选用，简洁模式的规则主节点与备用节点也可引用它。
- 不预置任何「中国大陆流量走直连」的默认规则；分流策略完全由用户自行配置。
- 「自定义 / Custom」模式中同名的「绕过中国流量」选项及其行为保持不变。
- 视觉上仅表现为简洁模式设置页少一个开关、节点列表与各节点下拉多一项「直连」，其余界面与交互不变。

## 技术栈选择

沿用现有 OpenWrt / LuCI 包技术栈，不引入新依赖、新架构：UCI 配置、ucode 生成器（`generate_client.uc`、`migrate_config.uc`）、utpl 防火墙模板（`firewall_post.ut`）、`/etc/rc.common` 启动脚本（`init.d/homeproxy`）、LuCI 原生 `form` 视图 JS、gettext 词条（`.pot` / `.po`）。`/etc/config/homeproxy` 已在 `Makefile` 的 `conffiles` 中登记，升级时保留用户配置，因此内置节点必须同时由 `migrate_config.uc`（由 `root/etc/uci-defaults/luci-homeproxy-migration` 调用）幂等补建。

## 实现思路

**策略**：把「直连」表达能力下沉到数据层（一个真实 UCI `node` 段），并把简洁模式的中国流量分流决策统一收敛到 `sing-box-c.json` 的 `route.rules` / `route.final`；删除 nft 层的 `simple-bypass-cn` 状态文件这条跨进程旁路。

**为什么这样做**（权衡已确认）：

- 现有 `client.js` 的 `proxy_nodes` 遍历所有 `node` section，`simple_track_node()` 只校验 `node.type`；`node.js` 的 `type` 下拉已支持 `direct`，`generate_outbound()` 已支持 `direct` 的 `override_*` / `proxy_protocol`。因此新增一个 `config node 'builtin_direct'`（`option type 'direct'`、`option label 'Direct'`）即可让节点页、legacy、`custom`、`simple` 三套链路全部自动可用，**无需改动 `node.js` 和 `client.js` 的下拉构造逻辑**，最符合 KISS 与 DRY。
- 不为它在生成器里造特殊枚举值：作为普通节点走既有 `simple_node_tag()` → `simple_add_group()` → `config.outbounds` / `config.route.rules` 链路，避免新增第二套出站命名规则。已有的内置 `direct-out` 继续只承担「默认出站」与系统 DNS/NTP detour 角色，两者职责分明，不重复也不互相替代。
- `update_subscriptions.uc` 遍历节点时 `if (!cfg.grouphash) return null;`，`node.js` 的订阅过滤也只排除有 `grouphash` 的 section；内置节点不带 `grouphash`，不会被订阅更新删除。section 名用保留前缀 `builtin_direct`，避开订阅节点 `md5(label)` 命名与用户手工命名冲突。
- 不做 UI 强制锁定（不覆写 `renderSectionRemove` 等未核实 API）：内置节点按普通节点可编辑/可删除，升级时由迁移脚本幂等补建；这是刻意的低复杂度取舍。
- 用户已明确「只清简洁模式」：`firewall_post.ut` 中 `bypass_cn_traffic === '1'` 的 nft 集合与 4 处分支同时服务 `custom` 模式，必须保留；只需让 simple 分支不再把该变量置为 `'1'`。

**关键正确性处理**（避免「规则直连但 DNS 走代理」）：

1. 在 `simple` 上下文增加 `direct_outbounds` 映射，由 `simple_track_node()` 在 `node.type === 'direct'` 时登记 `simple_node_tag(name)`；新增一个小 helper 判定「纯直连组」（单节点且 tag 在该映射中，不含 `urltest` 组）。
2. 规则组装阶段（约 707–717 行）：纯直连组不生成 `dns_conditions`、不计入 `dns_rule_count`，使这些域名落回 `default-dns` 及现有国内 DNS 分流规则（`geosite/geolocation-cn` + `geoip/cn`），而不是新建 `simple-dns-N` 用 `8.8.8.8` 直连解析。混合 fallback 组仍按代理组处理。
3. 默认出站阶段（约 721–735 行）：若 `final` 解析为直连节点出站，令 `default_proxy = false`，使 `config.dns.final` 保持 `default-dns`；`config.route.final` 仍指向该节点出站。
4. 出站生成阶段（约 1247–1281 行）：对 `type === 'direct'` 的节点出站跳过无条件附加的 `domain_resolver`（legacy / custom 分支本就不加），避免 `sing-box check` 因 direct 出站不支持该字段而失败；其余节点保持原样。
5. URLTest：单节点直连规则直接引用出站、不产生健康检查；直连节点被当作 fallback 与代理节点混组时仍按现有 `simple_add_group()` 生成 `urltest`，属既有语义，文档说明「推荐直连作主节点且不与代理混用」，不为此新增特例。

**性能与可靠性**：删除 fast path 后，简洁模式不再为 simple 读取/展开 `china_ip4.txt` / `china_ip6.txt` 生成 `homeproxy_mainland_addr_v4/v6` 大集合，fw4 规则规模与 reload 开销下降；代价是中国流量多一次用户态转发，这是用户明确接受的语义优先取舍。生成阶段时间复杂度仍为 O(规则数 × 条件数)，但少了每条规则的 `fast_path_safe` 判定与状态文件 I/O；DNS server 按 detour 去重（`dns_server_tags` 既有机制），纯直连组不再新增 server，避免配置膨胀。

## 实现说明（执行要点）

- **精确删除清单**：`generate_client.uc` 的 `simple_bypass_cn_reason()`（543–558）、`simple` 上下文的 `bypass_cn_traffic` / `bypass_cn_effective`（581–582）、598 行读取、614–616 注释、630–679 全部 `fast_path_safe` / `fast_path_reason` 计算、712–713 字段、777–783 判定与日志、1533–1534 状态文件写入。
- **日志**：仅删掉 `Simple routing: CN firewall fast path ...` 一行；其余 `simple_log()`（规则集排队、DNS final、缓存容量、节点/组数量）保持不变，不在数据路径加新日志。
- **易漏点**：`firewall_post.ut` 第 6 行 `import { isEmpty, RUN_DIR }` 中 `RUN_DIR` 只被状态文件读取使用，删除读取后必须一并去掉；`readfile` 仍被 `china_ip4.txt` / `china_ip6.txt` 使用，不能删。simple 分支保留 `default_outbound` 与 `china_dns_server` 两项读取。
- `init.d/homeproxy` 共 5 处 `rm -f "$RUN_DIR/simple-bypass-cn"`（54、59、65、69、343 行）全部删除；保留 `mkdir -p "$RUN_DIR"` 与生成/校验失败时的错误处理。
- **i18n**：只删 `po/templates/homeproxy.pot` 3112–3114 与 `po/zh_Hans/homeproxy.po` 3182–3184 的 fast path 描述 msgid 块（含注释行）；`msgid "Bypass CN traffic"` / 「绕过中国流量」仍被 custom 模式使用，`msgid "Direct"` / 「直连」已存在，两者均不得删除，本次无需新增词条。
- **兼容与影响面**：不改 `client.js` 的 `default_outbound`、`ruleset_download_detour`、`remote_dns_detour` 下拉及 `node.js`；不改 `update_subscriptions.uc`；不改 `docs/code-review-2026-11-06.md` 历史审查快照；`docs/simple-routing-latency-analysis.md` 第 7/8 节关于 fast path「已完成」的描述改为「已移除，改由 sing-box 规则 + 内置直连节点表达」，仅此一处最小同步。
- **验证方式**（项目无测试框架）：`node --check` 校验 `client.js`（及未改动文件回归）、`sh -n` 校验 `init.d/homeproxy`（shebang 为 `#!/bin/sh /etc/rc.common`）；ucode / utpl 靠语法审阅，并在设备上用生成后的 `sing-box-c.json` 执行 `sing-box check --config`；重点核对 direct 出站无 `domain_resolver`、纯直连规则不产生 `simple-dns-*` server、`config.dns.final` 为 `default-dns`、simple 模式 fw4 不再出现 `homeproxy_mainland_addr_*`。

## 架构设计

数据流（改动后，结构未变，仅移除一条旁路）：

```text
UCI: config homeproxy 'simple' + 'builtin_direct' node + simple_rule 行
  ↓
generate_client.uc → sing-box-c.json
  ├─ dns.servers / dns.rules（纯直连组不新增代理 DNS server）
  ├─ outbounds: direct-out(默认出站) / block-out / 各节点出站 / urltest 组
  └─ route.rules(按行顺序) + route.final(默认 direct-out 或用户所选节点)
  ↓
firewall_post.ut → fw4_post.nft（仅 redirect / tproxy / tun 接管，无中国 IP 提前 return）
  ↓
全部流量进入 sing-box → 命中规则走对应节点组（可含内置直连节点）→ 未命中走 final
```

`simple-bypass-cn` 状态文件、`simple.bypass_cn_effective`、`fast_path_safe` 三个跨文件耦合点整体消失，生成器与防火墙之间不再有隐式运行时状态依赖；`custom` 模式的 `routing.bypass_cn_traffic` → `bypass_cn_traffic === '1'` → nft 集合/分支链路完整保留。

## 目录结构

本次为既有项目改造，改动集中在 8 个文件，无新增源文件：

```
homeproxy/
├── root/etc/config/homeproxy                                  # [MODIFY] 删除 simple 段第 69 行 option bypass_cn_traffic '0'；新增 config node 'builtin_direct'（option type 'direct'、option label 'Direct'）。该文件已在 Makefile conffiles 登记，作为新装默认值；label 用已有 "Direct"/「直连」msgid 对应的固定文本。
├── root/etc/homeproxy/scripts/migrate_config.uc                # [MODIFY] 从 simple_defaults 删除 bypass_cn_traffic: '0'；在末尾 uci.commit 之前新增幂等补建：uci.get(uciconfig,'builtin_direct') 为空时以 uci.set(...,'node') 建段并写入 type/label，绝不覆盖同名用户段；沿用文件既有 ucinode 常量与 3 参数 uci.set 写法。
├── root/etc/homeproxy/scripts/generate_client.uc               # [MODIFY] 删除 simple_bypass_cn_reason()、bypass_cn_* 字段/判定/日志/状态文件写入；新增 direct_outbounds 登记与纯直连组判定；规则组装跳过直连组代理 DNS 条件与计数；默认出站为直连节点时 default_proxy=false；节点出站对 type=direct 跳过 domain_resolver。保留 direct-out、route.rules、国内 DNS 分流等全部既有逻辑。
├── root/etc/homeproxy/scripts/firewall_post.ut                 # [MODIFY] 修改 60–62 行注释；simple 分支删除 readfile(RUN_DIR + '/simple-bypass-cn') 与赋值，仅保留 default_outbound / china_dns_server；第 6 行 import 去掉不再使用的 RUN_DIR（readfile、trim 保留）。190–213、359–363、481–488、532–536、642–649 的 bypass_cn_traffic 条件与集合定义因 custom 模式保留，不得改动。
├── root/etc/init.d/homeproxy                                  # [MODIFY] 删除 54、59、65、69、343 行共 5 处 rm -f "$RUN_DIR/simple-bypass-cn"；保留 mkdir -p 与配置生成/校验失败分支。
├── htdocs/luci-static/resources/view/homeproxy/client.js       # [MODIFY] 仅删除 453–456 行简洁模式 form.Flag 'bypass_cn_traffic'；643–645 行 custom 模式同名 Flag 保留；proxy_nodes、default_outbound、规则 node/fallback_nodes 下拉均不改，内置节点会自动出现。
├── po/templates/homeproxy.pot                                  # [MODIFY] 删除 3112–3114 行 fast path 描述 msgid 块；保留 "Bypass CN traffic" 与 "Direct" 词条。
├── po/zh_Hans/homeproxy.po                                     # [MODIFY] 删除 3182–3184 行对应中文译文块；保留「绕过中国流量」与「直连」词条。
└── docs/simple-routing-latency-analysis.md                     # [MODIFY] 第 7/8 节将 4.5「大陆 IP 快速路径 已完成（默认关闭）」及相关实现约束说明改为已移除、由内置直连节点与 sing-box 规则承担；不改历史分析正文与 code-review 快照。
```

未修改但已核验受影响：`htdocs/luci-static/resources/view/homeproxy/node.js`（`type` 已有 `direct`、Nodes 页 `GridSection.filter` 只排除订阅节点，内置节点自动可见）、`root/etc/homeproxy/scripts/update_subscriptions.uc`（563–566 行跳过无 `grouphash` 节点）、`root/etc/uci-defaults/luci-homeproxy-migration`（迁移脚本调用入口）、`Makefile`（conffiles 已登记配置文件）。

## Agent Extensions

### SubAgent

- **code-explorer**
- Purpose: 以「very thorough」级别跨目录扫描 `bypass_cn`、`bypass_cn_effective`、`simple-bypass-cn`、`fast_path` 的全部残留引用，并反向核对新增 `builtin_direct` 节点在 `simple` / legacy / `custom` 三条生成链路与所有节点下拉中的可达性。
- Expected outcome: 输出一份精确残留清单，证明除 `custom` 模式的 `routing.bypass_cn_traffic` 及其 nft 集合/分支外无任何 fast path 遗留，且内置直连节点在配置生成器与 LuCI 视图中均被正确识别、无悬空引用。