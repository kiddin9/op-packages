# 遗留缺陷与已知限制汇总（待决定修复方案）

**决策时点**：P0 + P1 + P2 全部修复工作完成后统一决定。本文件只记录**不在 P2
范围内**、需要另行决策的项。

**当前进度**：

| 批次 | 范围 | 状态 |
|---|---|---|
| P0 | 14 项高危（输出整份不可用 / 数据永久丢失 / 安全） | ✅ 已完成（4 次推送，见 CHANGELOG `[2.6.0-r2]`～`[2.6.0-r5]`） |
| P1 | 13 项中危 + 审计中实测确认的 4 项新缺陷 | ✅ 已完成（`[2.6.1-r1]`） |
| P2 | 其余 M / L 项 | 🔄 进行中（批次一 `[2.6.3-r1]`、批次二 `[2.6.4-r1]`、批次三 `[2.6.5-r1]`、批次四 `[2.6.6-r1]`、批次五 `[2.6.7-r1]`、批次六 `[2.6.8-r1]`） |

**编写纪律**：只记录经**代码级审计或实测探针**确认的结论，不含推测。原始 70 项
审计表（高危 14 / 中危 30 / 低危 26）未落盘，本文件自本次起作为「未修复项」的
权威清单。已修复项见 [CHANGELOG.md](../CHANGELOG.md)。

---

# 一、本轮（P1 之后）确认的遗留项

## 1.1 H10 的「无锁」部分 —— `load()` → `save()` 丢更新

**已修的部分**：H10 的另一半（临时文件名固定为 `path..".tmp"` 被并发写者共用）
已在 P0 批次三修复，改为 `path..".tmp.<8 字节随机 hex>"`。

**未修的部分**：读-改-写全程仍无互斥。

**代码级依据**：

- `core.lua` 的 `local function load()` 读出整表，`local function save(seq, items)`
  整表写回，中间无锁；`M.add` / `M.add_local` / `M.add_combo` / `M.save_meta` /
  `M.save_combo` 均走这条路径。
- `util.lua` 中**不存在任何锁原语**（无 `flock`、无 `mkdir` 锁、无 `link()`）。
- `nixio` 只用于 `http.lua:208-210` 的 `getaddrinfo`（`util.try_require` 可选加载），
  `Makefile` 的 `LUCI_DEPENDS` 未声明 `+nixio`。

**并发来源**：LuCI 页面保存订阅、cron 定时更新、组合订阅自动重算，三者可能同时发生。

**影响**：后写者整表覆盖先写者 → 订阅丢失或新增丢失。与已修复的 H8 同属「数据被
抹除」，但触发条件是并发而非文件损坏，H8 的修复**不覆盖**本项。

**候选方案**：

| 方案 | 做法 | 代价 / 风险 |
|---|---|---|
| A. 记为已知限制 | 文档说明「同一时间只应有一个写操作」 | 零成本；用户无从感知，仍会丢数据 |
| B. 引入 `nixio` flock | `Makefile` 加 `+nixio`，写路径加文件锁 | 最可靠；新增运行时依赖，本机**无法验证** |
| C. `mkdir` 锁 + 陈旧锁回收 | 目录创建做互斥，带超时与持有者 PID 回收 | 纯 Lua 无依赖；需正确处理崩溃残留锁，否则死锁 |
| D. 写路径单点串行化 | 所有写入收敛到同一入口 | 跨进程串行仍需 OS 原语，实际仍要 B 或 C |

## 1.2 M28 / M29 —— CSRF `post_ok()` 与 ACL

**状态**：**已决定跳过验证**（用户 2026-09-30 指示）。

**原因**：二者依赖 LuCI 框架运行时行为（`test_post_security`、ACL 解析），本机没有
LuCI 运行环境，无法做代码级确认。按「不靠猜」的纪律，未做改动。

**审计结论（未做运行时验证，置信度有限）**：

- M28：`substore.lua:40-44` 的 `post_ok()` 只判 `formvalue("token") ~= nil`（空串也过），
  且 `entry` 均未声明 `post` → 框架的 `test_post_security` 从未执行。缓解因素是
  Cookie `SameSite=strict`。
- M29：`menu.d/luci-app-substore.json` 无 `depends.acl`、`entry` 无 `acl_depends`、
  仓库内无 rpcd ACL 文件 → 任意已登录 LuCI 用户可读写全部订阅（含凭据 URL）。

**建议**：在目标设备上以真实 LuCI 环境复核后再决定。

## 1.3 sing-box 读取侧：transport 整层丢失（实测确认）

**现象**：sing-box 配置中 ws / grpc / h2 的传输参数在导入后**完全丢失**，节点退化
为 tcp 直连。

**实测探针**（`parser.parse`，vmess + `transport: {type: ws, path: /ws, headers.Host}`）：

```
JSON -> proto=vmess net=tcp sni=a.com fp=nil    path=nil host=nil
YAML -> proto=vmess net=tcp sni=a.com fp=chrome path=nil host=nil
```

**代码级依据**：

- `parser_json_config.lua`（`parse_singbox_json`，314 行）全文**不含**
  `transport` / `path` / `host` / `utls` 任何一处。它读的是 `outbound.network`，
  而 sing-box 表达传输方式用的是 `transport.type` —— 该字段在 sing-box 出站里
  并不存在，因此 `net` 恒为默认值 `tcp`。
- 简易 YAML 解析器（`parser.lua`）只展开 `tls:` 子块，同样不处理 `transport`。

**影响**：ws / grpc / h2 节点在机场导出的 sing-box 配置里占相当比例，导入后全部按
tcp 直连，握手必然失败，且**不报错**。比原记录（「不读 path/host」）更严重：连传输
类型本身都没读进来。

**附带不一致**：`tls.utls.fingerprint` 在 YAML 侧**已读**（`fp=chrome`，P1 修复），
JSON 侧**不读**（`fp=nil`）。

**候选方案**：在 `parse_singbox_json` 中补 `transport.type` → `net`、
`transport.path` → `path`、`transport.headers.Host` → `host`、
`tls.utls.fingerprint` → `fp`；并让简易 YAML 侧同样处理 `transport`。
**需先核实 sing-box 各 transport 的权威字段名（ws / grpc / http），不凭记忆。**

## 1.4 `converter.lua` / `node_converter.lua` 为死代码，README 声明与实现不符

（即审计表 L2）

**代码级依据**：

- `root/` 下**没有任何文件** `require` 这两个模块 —— 唯一的引用是
  `converter.lua:7` 引用 `node_converter.lua`，以及 `tests/` 下的单元测试。
- LuCI controller 与前端 JS 中**不存在**「转换」相关的路由或 UI。
- 模块实现本身也有问题：禁止 shadowsocks 转换；`hysteria2/tuic/wireguard →
  "sing-box"/"clash"` 产出**非法 proto**；`node_converter.convert` 因 `network` /
  `fingerprint` 字段名不匹配丢 `net`/`path`/`host`/`fp`；`core.generate_link` 不传
  opts → `options.proto` 永不被设置。

**README 声明**：`README.md:59`「协议转换：任意协议 → 任意协议」、
`README.en.md:68`「Protocol conversion: any node type → any other type」；
紧接其后的 `README.md:60-62` 又说明「SSR 不能与 vmess/vless 等其它协议互转」，
与上一行自相矛盾。

**候选方案**：A. 接入 UI（需先定义「哪些协议可互转」的权威矩阵并审计现有映射表）；
B. 删除两个模块与测试，修正 README 两处声明。

---

## 1.5 Quantumult X：节点名含逗号时 `tag=` 字段本身被写坏（**待核实**）

**发现于**：P2 批次三修复 L21 时顺带发现。L21 只处理了**成员列表**（Surge 家族
`[Proxy Group]` 与 QX `[policy]`），已修复；本条是同一根因在 QX **定义行**上的
另一处表现。

**实测（已验证的部分）**：`output_formats.lua` 的 `to_qx` 用
`string.format("trojan=%s, password=%s, over-tls=true, tag=%s", …)` 拼行，
`tag` 直接取自 `n.name`。节点名 `A,B` 经 `util.one_line` 后仍含逗号，
输出为：

```
trojan=1.2.3.4:443, password=p, over-tls=true, tag=A,B
```

`[server_local]` 行内是逗号分隔的 `key=value` 字段序列，名字里的逗号落在
`tag=` 的值里，按该语法会被读成字段分隔符。

**未验证的部分（不猜）**：QX 对这种「最后一个字段值里多出逗号」的行究竟是
报错、忽略多余片段，还是原样接受，**本机没有 Quantumult X 可供实测**。
因此本条按「待核实」记录，未作修改。

**候选方案**（三选一，需先核实 QX 实际行为再定）：

- **A. 改名**：输出时把名字里的 `,` 替换为安全字符。节点不丢失，但导出名与
  LuCI 中显示的名字不一致；且 `A,B` 与 `A_B` 两个节点会撞名（Surge / QX 对
  重名代理的处理需另行核实）。
- **B. 丢弃**：把含逗号名字的节点从 QX 输出中整体剔除（连定义行一起）。
  与「Surge 家族丢弃 wireguard / ssr、Clash 原版丢弃不支持的协议」的既有约定
  一致，产出必定合法；代价是节点静默消失。
- **C. 维持现状**：仅在文档中说明「QX 输出请勿使用含逗号的节点名」。

**注**：Surge 家族的 `[Proxy]` 定义行是 `NAME = type, host, port, …`，
名字在 `=` **左侧**，逗号大概率不影响解析（未实测），故本条**只针对 QX**。

---

# 二、P0 时代的遗留项（2.6.0 审计时记录）

来源：CHANGELOG `[2.6.0-r1]` 的「已知限制（本轮不修，均有明确原因）」。以下逐条
复核过当前代码，均**仍然成立**。

## 2.1 M11 混合格式文本导入不支持

**依据**：`parse_local → parse → detect` 只识别**一种**格式，其余部分被静默丢弃
（实测：「URI + WG conf」只剩 WG 节点；「URI + JSON」只剩 URI 节点）。

**性质**：**功能缺失**而非小缺陷，需要重新设计 parser 的分段架构（规格 §22 明确
警告不要直接采用未经验证的逐行算法）。

**候选方案**：A. 设计分段架构后实现（工作量大，属 minor 版本特性）；
B. 在 README / UI 明确「一次只支持一种格式」（README 已如实说明，但 UI 未提示）。

## 2.2 sing-box 的 hysteria(v1) 出站还要求 `up` / `down`（带宽）

**依据**：`output_singbox.lua:127` 有明确注释说明；本项目的节点模型不承载该字段，
凭空填默认值属于猜测，故不输出。

**影响**：导出到 sing-box 的 hysteria v1 节点需用户自行补 `up`/`down`。

**候选方案**：A. 保持现状（文档说明）；B. 在节点模型中增加 `up`/`down` 字段并贯通
解析 / 表单 / 输出（属新功能）。

## 2.3 hysteria(v1) 的上游 URI 规范未能核实

**依据**：上游文档站点持续 404，无法取得权威定义。`parse_hysteria` 只保证解析本
项目 `output_uri` 自身生成的链接形态（回环已验证），认不出的查询参数一律忽略而不
报错，不臆造参数语义。

**候选方案**：待上游文档可访问后核实并补全；或维持「回环保证」的现状。

## 2.4 `http` 不加入任何 UI 协议列表

**依据**：规格 §25 的权威协议表恰好是 10 个协议、不含 `http`。`node.lua` 的
`M.PROTOS` 实测为 10 项（vmess / vless / trojan / shadowsocks / ssr / hysteria2 /
tuic / hysteria / wireguard / socks），确实不含 `http`。它可由 Clash YAML / JSON
配置导入并正常导出（凭据已修），但不作为表单可选项。

**候选方案**：A. 维持现状（`http` 属「可导入可导出但不可手录」）；B. 加入 UI 列表
（需先确认规格 §25 是否有意排除）。

## 2.5 `parser_yaml.lua` 为死代码

**依据**：`parser.lua:6` `require` 了它，但全文对 `parser_yaml.` 的调用次数实测为
**0**。其中留有同样未归一的 `socks5` 映射。

**影响**：不影响运行，属清理项。

**候选方案**：A. 删除文件与 `require`；B. 保留（无害）。

## 2.6 AmneziaWG 3.0 / 3.1 新增的 9 个字段不被 `.conf` 解析器接受

**字段**：`HeaderProtectionKey`、`ContentPaddingAddition`、`RekeyAfterTime`、
`RekeyTimeout`、`RejectAfterTime`、`KeepaliveTimeout`、`MaxHandshakeAttempts`、
`RandomTrailers`、`DisableCookies`。

**依据**：实测这 9 个名字在 `parser.lua` 中**一处都不出现** —— 即 `.conf` 解析器
按已知键白名单映射，这 9 个键落在白名单外，**导入即丢弃**；但它们会从 Clash / JSON /
`wireguard://` 导入路径原样透传。

**影响**：同一节点经 `.conf` 导入与经 JSON 导入，得到的字段集**不一致**。

**候选方案**：A. 核实 AmneziaWG 上游对这 9 个键的权威语义后补入白名单（不猜语义）；
B. 保持白名单策略，在文档说明差异。

---

# 三、更早的遗留项（2.5.x 记录，一并归档）

来源：CHANGELOG `[2.5.1-r1]` / `[2.5.0-r1]` 的「已知限制」。均为**已确认、未修复**。

## 3.1 LuCI 里 `amnezia-wg-option` 仍是单个 JSON 文本框

**依据**：`node.lua` 的 `PROTO_FIELDS.wireguard` 中 `amnezia-wg-option` 是**单个**
字段（实测该数组共 13 项，`amnezia-wg-option` 占其一），因此前端渲染成一个文本框，
需用户手写 JSON。数据本身能正确往返，但录入体验不佳。

**候选方案**：逐字段化（属新功能，按版本约定应进入 minor 版本）。

## 3.2 wget 后端的下载体积上限是**下载后**判断

**依据**：busybox wget 没有「下载前限流」的选项。响应体虽被丢弃，但请求已经发出。

**候选方案**：改用 curl（若有）或维持现状并在文档说明。

## 3.3 改名规则不支持括号内的「或」`(a|b)`

**依据**：Lua 模式无 alternation 语义，按字面处理。

**候选方案**：A. 维持现状并文档说明；B. 实现一个简单的 alternation 展开。

## 3.4 `check_public` 在无 DNS 解析能力时放行（fail-open）

**依据**：`http.lua` 实测代码为：

```lua
local ips = resolve(host)
if not ips then
    -- 无 DNS 解析能力：放行，交由下载工具处理（尽力而为）
    return true
end
```

即无 `nixio` 时任意主机名放行。另存在解析与下载之间的 TOCTOU 窗口。

**候选方案**：A. 改为 fail-closed（可能误伤无 DNS 环境）；B. 维持现状并文档说明；
C. 引入 `nixio` 作为必需依赖（与 1.1 的锁方案可一并考虑）。

## 3.5 wget 路径的重定向校验是**事后**的

**依据**：busybox wget 无 `--max-redirect`；响应体虽被丢弃但请求已经发出，且无法
限制下载体积。

**候选方案**：与 3.2 一并处理（改用 curl 或自实现 HTTP 客户端）。

---

# 附：P2 修复范围（不含本文件所列项）

P2 为审计表中**其余中危 / 低危**项中性质明确、无需另行决策的缺陷，例如
M6 / M9 / M13 / M14 / M16 / M17 / M18 / M19 / M23 / M24 / M25 / M26 / M27 / M30
与 L1 / L3～L6 / L8～L26 等。逐项修复并补回归测试，完成后在 CHANGELOG 中记录。
本文件所列各项**不在** P2 范围内。
