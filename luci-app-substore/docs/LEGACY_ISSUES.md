# 遗留缺陷与已知限制汇总

**决策状态**：本文件所列各项**均已决策并处置完毕**（`[2.6.16-r1]` 为最后一批，
见下文「六」）。仍留在这里是因为它们记录了「为什么是这个处置」—— 其中一部分是
**有意保留的已知限制**，不是待办；另有几项写明「待上游规范可核实后再定」。
本文件只记录**不在 P2 范围内**、需要另行决策的项。

**当前进度**：

| 批次 | 范围 | 状态 |
|---|---|---|
| P0 | 14 项高危（输出整份不可用 / 数据永久丢失 / 安全） | ✅ 已完成（4 次推送，见 CHANGELOG `[2.6.0-r2]`～`[2.6.0-r5]`） |
| P1 | 13 项中危 + 审计中实测确认的 4 项新缺陷 | ✅ 已完成（`[2.6.1-r1]`） |
| P2 | 其余 M / L 项 | ✅ 已完成（批次一 `[2.6.3-r1]`、批次二 `[2.6.4-r1]`、批次三 `[2.6.5-r1]`、批次四 `[2.6.6-r1]`、批次五 `[2.6.7-r1]`、批次六 `[2.6.8-r1]`、批次七 `[2.6.9-r1]`「P2 最后一批」） |
| P3 | 输出层代码级复审（10 项）+ shadowsocks SIP003 插件全链路（1 项） | ✅ 已完成（`[2.6.10-r1]`，见下文「四」） |
| P4 | 遗留项决策后实施（1.1 / 1.3 / 1.4 / 1.5 / 2.5 五项，3.3 补文档） | ✅ 已完成（`[2.6.11-r1]`，见下文「五」） |
| P5 | 决策项实施（wget 路径 SSRF、删除部分失败漏写 cron、混合格式静默丢弃、写入失败被忽略、M28 token、M29 ACL；wget 体积/重定向记文档） | ✅ 已完成（`[2.6.16-r1]`，见下文「六」） |

**编写纪律**：只记录经**代码级审计或实测探针**确认的结论，不含推测。原始 70 项
审计表（高危 14 / 中危 30 / 低危 26）未落盘，本文件自本次起作为「未修复项」的
权威清单。已修复项见 [CHANGELOG.md](../CHANGELOG.md)。

---

# 一、本轮（P1 之后）确认的遗留项

## 1.1 H10 的「无锁」部分 —— `load()` → `save()` 丢更新（**已修复 `[2.6.11-r1]`**）

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

**状态**：**已修复（`[2.6.16-r1]`）**。原「跳过验证」的处置已作废 —— 两项依赖的
LuCI 框架行为本轮**已从上游源码逐条核实**（依据见下），不再是猜测，故按核实结果实施。

**M28（`post_ok()` 空 token 放行）—— 已修复**

原缺陷：`substore.lua` 的 `post_ok()` 只判 `formvalue("token") ~= nil`，**空串也通过**；
且所有 `entry` 均未声明 `post`，框架的 `test_post_security` 从未执行。

**框架行为核实**（上游 `luci/luci-base`，非推测）：

- `luci/dispatcher.lua` 的 `test_post_security()` 只在 `entry.post` 为真时才被调用；
  本控制器未声明 `post`，因此该函数**确实从未执行** —— 原判断成立。
- `luci/template.lua` 中 viewns 元表的 `token` 键返回 `disp.context.authtoken`，
  即模板里的 `token` **就是** `luci.dispatcher.context.authtoken`。因此「把提交的 token
  与 `context.authtoken` 比对」正是框架自身的判据，**不会误拒任何合法表单**。

**修复内容**：`post_ok()` 现在要求 token **存在且非空**，并在能取到 `authtoken` 时
要求两者**相等**；取不到 `authtoken`（非标准运行环境）时退回「非空即通过」，
不因取不到值而拒绝全部请求。失败时通过 `post_fail_msg` 把原因回显到列表页，
不再静默失败。同时补齐了原先 9 处**忽略返回值**的调用点（7 处 `back_to_list()`、
2 处 `back_to_nodes()`），使校验失败**必然**被用户看到。

**回归测试**：`tests/controller_robustness_test.lua` 的 M28 段（6 条断言），
覆盖「合法 token 通过 / 空 token 拒绝 / 不匹配拒绝 / create / update / node_save
四类写操作均受检 / 取不到 authtoken 时的回退」。反向验证：修复前 7 条断言失败。

**M29（无 ACL）—— 已修复**

原缺陷：`menu.d` 无 `depends.acl`、仓库内无 rpcd ACL 文件 → 任意已登录 LuCI 用户
可读写全部订阅（含凭据 URL）。

**ACL 结构核实**（上游 `luci-base` 与 `luci-app-commands`，非推测）：acl.d 的顶层是
`{ "<组名>": { "description": …, "read": { "uci": [...] }, "write": { "uci": [...] } } }`；
menu.d 用 `"depends": { "acl": [ "<组名>" ] }` 引用。

**修复内容**：新增 `root/usr/share/rpcd/acl.d/luci-app-substore.json` 定义
`luci-app-substore` 组（读写 `uci: substore`），`menu.d` 两个条目均声明
`depends.acl` 引用它，`Makefile` 增加对应的安装规则。

**执行范围（已从上游源码核实，非推测）**：

`menu.d` 的 `depends.acl` 是**入口级**门禁，不只是「菜单里看不见」。核实过程：

- **ucode dispatcher（23.05+，现代目标机上实际运行的那套）**：
  `modules/luci-base/ucode/dispatcher.uc` 的 `build_pagetree()` 把
  `/usr/share/luci/menu.d/*.json` **与** Lua 控制器
  （`/usr/lib/lua/luci/controller/*/*.lua`）glob 进**同一棵树**；
  `dispatch()` 逐段走这棵树并调用 `ctx_append(ctx, name, node)`，而
  `ctx_append` 里是 `push(ctx.acls, ...(node?.depends?.acl || []))` ——
  **路径上每个节点**的 `depends.acl` 都会被累积。随后：
  ```js
  if (length(resolved.ctx.acls)) {
      let perm = check_acl_depends(resolved.ctx.acls, resolved.ctx.authacl?.['access-group']);
      if (perm == null) { http.status(403, 'Forbidden'); return; }
  }
  ```
  即：缺少该组的用户**直接访问 URL 会拿到 403**。
- **ACL 沿路径累积**这一点还带来一个有用的推论：把 ACL 挂在父节点
  `admin/services/substore` 上，就已覆盖它的**全部子路由**
  （`form` / `nodes` / `delete` / `save` / `node_save` / `update` / `probe` …）。
  本应用的所有动作都在该节点之下，因此这 18 个 `entry` 一并受保护。
- **旧版 Lua dispatcher（≤ 22.03）行为不同，但不在支持范围内**：`luasrc/dispatcher.lua`
  里 `menu_json()` 把控制器树与 menu.d 树 merge 后 `apply_tree_acls`，那只影响
  **菜单渲染**；`dispatch()` 用的是控制器树，其 `depends.acl` 只来自
  `entry.acl_depends`。也就是说在 22.03 上仅靠 menu.d 只有「菜单看不见」。
  **本项目最低支持 23.05**（用户 2026-10-02 确认），23.05 起用的是 ucode dispatcher，
  即上面那套入口级 403 语义。因此**无需**为旧版补 `entry.acl_depends` —— 记录在此
  只为说明「为什么 22.03 不在支持范围内时这个缺口可以不管」，不是待办。

**设备实测（已完成并通过，2026-10-02）**：以上结论最初来自**读上游源码**（本机无
LuCI 运行环境），随后按 `docs/TESTING.md` 第 9 项在目标设备复核，**三项断言全部通过**：

- 非 root 且不在 `luci-app-substore` 组内的 LuCI 用户：**看不到**本应用菜单入口
- 把该用户加入组后：入口**出现**
- 该用户**直接访问** `/cgi-bin/luci/admin/services/substore/list`：返回 **403 Forbidden**

即：入口级 403 的语义在真实设备上成立，与上文读源码得出的推断一致。

**回滚方式**：删除 `root/usr/share/rpcd/acl.d/luci-app-substore.json`（及 Makefile 中
对应的两行安装规则），并移除 `menu.d` 两个条目里的 `depends` 块。

**回归测试**：`tests/acl_menu_test.lua`（19 条断言）固化跨文件接线 —— ACL 组定义、
菜单引用**同一个组名**、菜单路径在控制器中确实注册、Makefile 确实安装这两个文件。
这条链路上任何一环写错都**不会报错**，只会静默失效（ACL 形同虚设），故必须由测试
锁住。反向验证：修复前 13 条断言失败。

## 1.3 sing-box 读取侧：transport 整层丢失（**已修复 `[2.6.11-r1]`**）

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

**权威字段名已核实（`[2.6.10-r1]`，取自上游
`sing-box.sagernet.org/configuration/shared/v2ray-transport/`，可直接照此实现，
无需再猜）**：

| `transport.type` | 本项目的 `net` | 字段映射 |
|---|---|---|
| `ws` | `ws` | `path` → `path`；`headers.Host` → `host` |
| `grpc` | `grpc` | `service_name` → `path` |
| `http` | `http` | `path` → `path`；`host` 是**数组**，取首个 → `host` |
| `httpupgrade` | `http` | `path` → `path`；`host` 是**单个字符串** → `host` |
| `quic` | 无对应 | 本项目模型没有 quic，按未知传输处理（回落 tcp 或丢弃） |

另：`tls.utls.fingerprint` → `fp`（YAML 侧已读，JSON 侧未读，需对齐）；
`tls.enabled` 为 `false` 时不得置 `security`。

**修复建议：本轮修复**（`[2.6.10-r1]` 未实施，留待下一轮）。它与 F5 / F6 / F11
同属「静默丢传输层 → 节点连不上且不报错」，而 ws / grpc 节点在机场的 sing-box
配置里占比很高，影响面比 F5/F6 更大。实施时两侧（JSON 与简易 YAML）必须一起改，
否则同一条订阅走两条导入路径会得到不同的节点。

## 1.4 `converter.lua` / `node_converter.lua` 为死代码（**已删除 `[2.6.11-r1]`**）

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

## 1.5 Quantumult X：节点名含逗号时 `tag=` 字段本身被写坏（**已按方案 B 修复 `[2.6.11-r1]`**）

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

**补充（`[2.6.10-r1]`）**：同一条行语法在**参数值**上的同类问题已修复 —— `to_qx`
现在先把具名字段攒成列表、逐字段判定值里是否含逗号，含逗号的整条丢弃（连同
`[policy]` 成员），不再出现 `password=pa,ss` 被静默截断成 `password=pa`。
本条讨论的 `tag=` **名字**部分已于 `[2.6.11-r1]` 按下面的方案 B 一并处理：
`to_qx` 现在对「one_line 之后仍含逗号」的节点整条丢弃（定义行与 `[policy]` 成员
一起），判定条件与 `names_of` 完全一致，两边不会再对不上。

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

**推荐方案：B（丢弃）**。理由：

- A（改名）会引入新的重名风险，而「重名代理」在 Surge / QX 上的行为同样未核实 ——
  等于用一个未核实的问题换掉另一个，不划算。
- C（维持现状）会让用户拿到一份静默损坏的配置，与本项目「宁可丢节点也不输出
  损坏行」的既有约定（Surge 家族丢 wireguard / ssr、Clash 原版丢不支持的协议）相悖。
- B 与 F7 已落地的处置完全一致，实现上只是把 `names_of` 的排除条件也用到定义行上，
  改动小、行为可预期。

实施前仍建议先核实 QX 对多余逗号片段是报错还是忽略 —— 若确认是「忽略多余片段、
`tag` 取第一段」，则 C 也可接受，届时再定。

---

# 二、P0 时代的遗留项（2.6.0 审计时记录）

来源：CHANGELOG `[2.6.0-r1]` 的「已知限制（本轮不修，均有明确原因）」。以下逐条
复核过当前代码，均**仍然成立**。

## 2.1 M11 混合格式文本导入不支持（**已按方案 B+ 修复 `[2.6.16-r1]`**）

**依据**：`parse_local → parse → detect` 只识别**一种**格式，其余部分被静默丢弃
（实测：「URI + WG conf」只剩 WG 节点；「URI + JSON」只剩 URI 节点）。

**性质**：**功能缺失**而非小缺陷，需要重新设计 parser 的分段架构（规格 §22 明确
警告不要直接采用未经验证的逐行算法）。

**候选方案**：A. 设计分段架构后实现（工作量大，属 minor 版本特性）；
B. 在 README / UI 明确「一次只支持一种格式」（README 已如实说明，但 UI 未提示）。

**已实施方案 B+（拒绝而非静默丢弃）**：新增 `M.detect_all(content)` 收集文本中
**全部**出现的格式，本地文本导入（`parse_local` 文本模式）在多于一种时**明确报错**
并列出两种格式名，而不是交给 `detect()` 挑一种、悄悄丢掉其余。这比 B 更进一步：
B 只是提示，用户仍会拿到一份少了一半节点的配置；现在是**导入直接失败**，不存在
「以为成功」的中间态。

**实施中修正的两处误判**（若不修，会把合法配置拒之门外，属新 bug）：

- Surge / Clash 的 INI 段头 `[Proxy]` 等会被朴素的 `^%s*%[` 规则误判为 JSON 数组，
  于是一份合法 Surge 配置被判成 `surge + json` 而拒绝。已加 `is_ini_section_head()`
  排除段头（段头内是标识符，不是引号字符串）。
- 「URI + JSON」这个方向起初漏检（原判据只看首个非空字符）。已补
  `has_json_object_line()`（`^%s*{%s*$` 或 `^%s*{%s*"`）做行级判定，两个方向都能识别。

**刻意限定范围（如实记录）**：守卫**只作用于本地文本导入**。远程订阅走
`M.detect` / `M.parse`，**未改动** —— 改动它会让既有远程订阅的解析行为变化，
风险大于收益。因此**远程订阅内容若混用格式，仍然是静默丢弃**，与修复前一致。

**回归测试**：`tests/parser_mixed_format_test.lua`（70 条断言）—— A 组确认单一格式
（含带 `proxy-provider` 的 Clash YAML、带 `url` 规则的 sing-box JSON、YAML 流式映射、
`[Interface]` / `[Proxy]`）**不会被误判**；B 组确认 7 种混用组合都明确报错且错误信息
含两种格式名；C 组确认远程路径 `M.parse` 行为未变。反向验证：修复前探针显示
「URI + WG conf」得到 `nodes=1, err=nil`（静默丢弃）。

## 2.2 sing-box 的 hysteria(v1) 出站还要求 `up` / `down`（带宽）

**状态：确认为已知限制（`[2.6.16-r1]` 决策，方案 A）** —— 不改代码，写入用户文档
（README「已知限制」）。

**依据**：`output_singbox.lua:127` 有明确注释说明；本项目的节点模型不承载该字段，
凭空填默认值属于猜测，故不输出。

**影响**：导出到 sing-box 的 hysteria v1 节点需用户自行补 `up`/`down`。

**候选方案**：A. 保持现状（文档说明）；B. 在节点模型中增加 `up`/`down` 字段并贯通
解析 / 表单 / 输出（属新功能）。

**决策理由**：选 A。B 需要先定字段名与单位（bps 还是 Mbps、是否成对、缺省值取多少），
这些都是**未经核实的规格问题**，按「不猜」纪律不能凭推测落码；且它属于新功能，
按版本约定应进 minor 版本，不适合混在本轮的缺陷修复里。

## 2.3 hysteria(v1) 的上游 URI 规范未能核实

**状态：确认为已知限制（`[2.6.16-r1]` 决策，方案 A）** —— 不改代码，写入用户文档
（README「已知限制」）。

**依据**：上游文档站点持续 404，无法取得权威定义。`parse_hysteria` 只保证解析本
项目 `output_uri` 自身生成的链接形态（回环已验证），认不出的查询参数一律忽略而不
报错，不臆造参数语义。

**候选方案**：待上游文档可访问后核实并补全；或维持「回环保证」的现状。

**决策理由**：选「维持现状」。规范拿不到就是拿不到 —— 此时任何「补全」都是编造
参数语义，正是「不猜」纪律要禁止的。已实测的回环保证（本包导出 → 本包导入不失真）
是本项目唯一能负责的边界，如实写进文档即可。

## 2.4 `http` 不加入任何 UI 协议列表

**状态：确认为已知限制（`[2.6.16-r1]` 决策，方案 A）** —— 不改代码，写入用户文档
（README「已知限制」）。

**依据**：规格 §25 的权威协议表恰好是 10 个协议、不含 `http`。`node.lua` 的
`M.PROTOS` 实测为 10 项（vmess / vless / trojan / shadowsocks / ssr / hysteria2 /
tuic / hysteria / wireguard / socks），确实不含 `http`。它可由 Clash YAML / JSON
配置导入并正常导出（凭据已修），但不作为表单可选项。

**候选方案**：A. 维持现状（`http` 属「可导入可导出但不可手录」）；B. 加入 UI 列表
（需先确认规格 §25 是否有意排除）。

**决策理由**：选 A。规格 §25 是否有意排除 `http` **未核实**，在核实之前把它加进
UI 就是替规格做决定；而现状并无功能损失（能导入、能导出），只是不能手工新建，
写进文档说明即可。

## 2.5 `parser_yaml.lua` 为死代码（**已删除 `[2.6.11-r1]`**）

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

**状态：已修复（`[2.6.10-r1]` 复核）**。`parser.lua` 的 `.conf` 键映射表已收录全部
9 个 v3.0 / 3.1 键（`headerprotectionkey` → `header-protection-key` …
`disablecookies` → `disable-cookies`），并补入了 v1.5 的 `s3/s4/i1..i5/j1..j3/itime`。
其中 `random-trailers` / `disable-cookies` 是布尔字段，按 amneziawg-tools 的
`parse_bool`（只认 `on`/`off` 或十进制数）解析，非法值丢弃而不是原样透传 ——
留着会让 mihomo 解析该字段时报错。**本条无需再决策。**

---

# 三、更早的遗留项（2.5.x 记录，一并归档）

来源：CHANGELOG `[2.5.1-r1]` / `[2.5.0-r1]` 的「已知限制」。均为**已确认、未修复**。

## 3.1 LuCI 里 `amnezia-wg-option` 仍是单个 JSON 文本框

**状态：确认为已知限制（`[2.6.16-r1]` 决策）** —— 不改代码，写入用户文档
（README「已知限制」）。

**依据**：`node.lua` 的 `PROTO_FIELDS.wireguard` 中 `amnezia-wg-option` 是**单个**
字段（实测该数组共 13 项，`amnezia-wg-option` 占其一），因此前端渲染成一个文本框，
需用户手写 JSON。数据本身能正确往返，但录入体验不佳。

**候选方案**：逐字段化（属新功能，按版本约定应进入 minor 版本）。

**决策理由**：数据往返正确、无功能损失，仅是录入体验；逐字段化属新功能，
不适合混在缺陷修复批次里。写进文档说明录入方式即可。

## 3.2 wget 后端的下载体积上限是**下载后**判断

**状态：确认为工具限制（`[2.6.16-r1]` 决策）** —— 无法在代码层消除，写入用户文档
（README「已知限制」）与本文。

**依据**：busybox wget 没有「下载前限流」的选项（已核对 busybox 1.37 `--help`，
不存在 `--max-filesize` 之类的等价物）。响应体虽被丢弃，但请求已经发出。

**实际影响有限的原因**：`fetch_wget` 在体积超限时会**丢弃响应体并报错**
（`http.lua`：`size > max` → `os.remove(tmp)` + 返回错误），因此超限内容不会进入
解析流程，也不会落盘留存。剩下的差异只是「流量已经消耗」——这属于工具能力问题。

**候选方案**：改用 curl（若有，curl 路径有 `--max-filesize`，是**下载中**截断）或
维持现状并在文档说明。

**决策理由**：不改代码。curl 后端本就已经用 `--max-filesize` 做了下载中限制；
wget 后端受 busybox 能力所限做不到，自实现 HTTP 客户端属大改动、收益与风险不成
比例。如实写进文档。

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

**状态：已修复（`[2.6.8-r1]`），但该修复本身引入了回归，已于 `[2.6.12-r1]` 重做。**

`[2.6.8-r1]` 把「解析不出 IP」一律改成 fail-closed，前提是「本包依赖
luci-lua-runtime → 硬依赖 luci-lib-nixio → 解析失败只意味着真的解析不了」。
**这个前提在用户设备上不成立**：`resolve()` 当时只有 `nixio` 一条路，
nixio 取不到时恒返回 `nil`，于是所有域名订阅都被拒，报「无法解析目标主机名」
（用户实测 2.6.7-r1 正常，2.6.8-r1 起四个订阅全部失效）。根因是把
「本机没有解析手段」与「这个域名解析不出来」合并成了同一个 `nil`。

`[2.6.12-r1]` 的做法：
- `resolve()` 多级回退 `nixio` → busybox `nslookup`，并返回 `ips, have_resolver`；
- 有解析手段却解析不出来 → 仍 fail-closed（本条要堵的绕过口继续堵死）；
- 完全没有解析手段 → 放行，但返回 `unverified = true`；
- 下载层用 curl 的 `%{remote_ip}` 在**连接建立后**复核实际对端地址，
  并把 `unverified` 且拿不到对端 IP 视为拒绝。

TOCTOU 窗口（解析与下载之间）也由此关闭：`%{remote_ip}` 就是真正连上的那个 IP，
免疫「预检时解析到公网、连接时解析到内网」的 DNS rebinding。

**`[2.6.16-r1]` 补完：wget 后端此前仍是 fail-open。**

`[2.6.12-r1]` 的「连接后复核」只对 **curl** 后端成立 —— 它靠 `%{remote_ip}` 拿到
真实对端地址。**wget 后端没有任何等价物**：busybox wget 拿不到对端 IP，
`-S` 日志里的重定向链也只能**事后**看（拦不住已经发出去的请求）。于是在
「本机没有解析手段」这种设备上，wget 路径的「预检放行」之后**不存在任何一处校验**
—— 等于完全没有 SSRF 防护，而这条路径此前是**静默**的。

现已按与 `verify_peer_ip` 相同的处置收敛：**校验不了就拒绝**。
`fetch_wget` 在 `opts.unverified` 为真时直接返回错误
（"本机无 DNS 解析能力，wget 后端无法校验目标地址，已拒绝下载（安装 curl 后重试）"），
不再尝试下载。

**影响面（如实记录）**：仅影响「本机无任何 DNS 解析手段（nixio 不可用且无 nslookup）
**且** 目标为域名 **且** 下载后端为 wget」的设备 —— 这类设备上的域名订阅会失败，
提示安装 curl。字面 IP 目标不受影响（`check_public` 对 IP 提前返回，不产生
`unverified`）；有解析手段的设备也不受影响。**这是有意的取舍**：本包依赖
`luci-lua-runtime`，正常安装的设备上 `nslookup` 可用，属于罕见组合；而放行的代价是
一个**完全无防护**的 SSRF 入口。

**回归测试**：`tests/dns_fallback_test.lua` 用例 H（无解析器 + wget → 拒绝；桩会写入
`evilbody`，确保断言不是因「内容为空」而误过）与 H2（对照组：有解析器 → wget 正常
下载）。反向验证：修复前 H 有 3 条断言失败。

**本条已了结，无需再决策。**

## 3.5 wget 路径的重定向校验是**事后**的

**状态：确认为工具限制（`[2.6.16-r1]` 决策）** —— 无法在代码层消除，写入用户文档
（README「已知限制」）与本文。

**依据**：busybox wget 无 `--max-redirect`（已核对 busybox 1.37 `--help`）；响应体虽
被丢弃但请求已经发出，且无法限制下载体积。

**已在代码层做到的部分（`[2.6.16-r1]` 复核）**：`M.validate_redirect_chain(url, log)`
会从 `-S` 日志里按出现顺序提取整条重定向链的 `Location`，对**每一跳**重新做
`check_public`，任一跳指向内网/保留地址即整体拒绝并丢弃响应体。因此
「重定向到内网」**不会**被放行 —— 缺的只是「在发出下一跳请求**之前**拦住它」。

**与 3.4 的区别**：3.4 是「根本没有校验」（已修，改为拒绝）；本条是「校验存在但
发生在请求之后」。后者不会让内网内容进入解析流程，只是多发出了一跳请求。

**候选方案**：与 3.2 一并处理（改用 curl 或自实现 HTTP 客户端）。curl 路径用
`--max-redirs 0` 自行逐跳跟随，每跳都在**发出前**校验，不受此限制。

**决策理由**：不改代码。curl 后端已是「发出前校验」；wget 后端受 busybox 能力所限，
自实现 HTTP 客户端属大改动。如实写进文档。

---

# 四、P3：输出层代码级复审（`[2.6.10-r1]` 已修复）

对 8 个输出模块与 `output.lua` 做了逐行复审，按「生成的配置能否被目标客户端加载」
这一条标准筛出 11 项缺陷。**全部已修复、已补回归测试、并已对 `HEAD` 反向验证**
（`tests/output_layer_fixes_test.lua` 30 条断言、`tests/ss_plugin_test.lua` 25 条
断言在修复前失败，修复后全绿）。逐项记录如下。

| 编号 | 位置 | 缺陷 | 后果 |
|---|---|---|---|
| F1 | `output_clash_meta` | `ws-opts:` 写在 `if node.path` 内，只有 host 的 ws 节点输出悬空的 `headers:` | YAML 非法 / Host 被忽略，ws 握手被拒 |
| F2 | `output_v2ray` | 空传输层编码成 `[]` 而非 `{}` | Xray `UnmarshalTypeError`，拒绝启动 |
| F3 | `output_clash_meta` | 节点名与其它节点 / 策略组名 / 保留名冲突时不消解 | mihomo `proxies` 重名，拒绝加载整份配置 |
| F4 | `output_clash_meta` | `esc_yaml` 未引用以 `%` `!` `-` 开头的标量 | 非法 YAML，mihomo 解析失败 |
| F5 | `output_formats` | QX 的 vless 分支不输出 obfs / tls 参数 | 客户端按明文 tcp 连 ws 端口，必然失败且不报错 |
| F6 | `output_formats` | Surge 家族的 vless 分支不输出 ws 传输层 | 同上 |
| F7 | `output_formats` | 参数值里的逗号把凭据静默截断（`password=pa,ss` → `password=pa`） | 静默发错凭据 |
| F8 | `output_uri` | IPv6 字面量地址未加方括号 | authority 无法解析 |
| F9 | `output_clash_meta` | `amnezia-wg-option` 子键未转义 | 键名里的 `:` / 引号写坏 YAML 映射 |
| F10 | `output.lua` | `content_type_for` / `extension_for` 对空 target 落空（`""` 在 Lua 里是真值） | 正文与响应头 / 文件名后缀不一致 |
| F11 | 全链路 | shadowsocks 的 SIP003 `plugin` 被三个输出模块静默丢弃；表单保存时被清空 | 带 obfs / v2ray-plugin 的节点导出后连不上；界面上编辑一次即永久丢失插件配置 |

**F11 的处置依据**（均核对上游源码 / 文档，非推测）：

- **SIP002**：`SS-URI = "ss://" userinfo "@" host ":" port [ "/" ] [ "?" plugin ] [ "#" tag ]`，
  插件参数整体做百分号编码。
- **sing-box**：`shadowsocks` 出站只有 `plugin`（字符串，官方文档明确
  *"Only two are supported: obfs-local and v2ray-plugin"*）与 `plugin_opts`
  （SIP003 原始参数串，原样透传）。其余插件名会被拒绝，故按白名单过滤。
- **mihomo**：`plugin-opts` 是**映射**而非字符串，且名称与参数名都要翻译
  （`obfs-local`/`simple-obfs` → `obfs`，参数 `obfs` → `mode`、`obfs-host` → `host`）。
  `adapter/outbound/shadowsocks.go` 对这两类插件是**强校验**的：obfs 的 mode 不在
  `{tls,http}` 里报 `"ss %s obfs mode error"`，v2ray-plugin 的 mode 不是 `websocket`
  同样报错 —— 都会让整个 outbound 构造失败，进而**拒绝加载整份配置**。因此参数
  不全时宁可整个不输出插件，也不能输出一个必然被拒绝的组合。

**顺带修正的既有测试**：`tests/output_formats_test.lua` 原断言
`tuic alpn array joined` 期望 `alpn=h3,h2`。多值 alpn 在 Surge 家族的行语法里
表达不了（逗号分隔的 `key=value`，无转义），F7 的通用逗号检查会因此丢掉整个节点。
处置：alpn 是**协商提示**而非凭据，缺省时客户端用服务端给出的列表 —— 所以只省略
该参数、保留节点。断言已按此契约更新。

---

# 五、其余遗留项的修复建议（按推荐优先级排序）

**实施记录（`[2.6.11-r1]`）**：下表中 1.1 / 1.3 / 1.4 / 1.5 / 2.5 五项已按推荐方案
实施完毕，3.3 按方案 A 补了用户文档说明。每项都补了自包含回归测试，并对 `HEAD`
做了反向验证（新断言在修复前失败、修复后全绿）：

| 项 | 回归测试 | HEAD 上失败断言数 |
|---|---|---|
| 1.1 `mkdir` 锁 | `tests/list_lock_test.lua`（39 条） | 18 |
| 1.3 sing-box `transport` | `tests/singbox_transport_test.lua`（28 条） | 18 |
| 1.5 QX `tag=` 逗号 | `tests/qx_tag_comma_test.lua`（24 条） | 9 |

1.4 / 2.5 是删除死代码，无新增断言；1.4 顺带修复了 `tests/p2_batch7_test.lua`
中对已删模块的依赖（改为直接验证 `util.uuid`）。

实施中修正了两处**推荐方案本身**的疏漏，记录如下：

- **1.1**：`with_list_lock` 最初把锁目录写成常量 `M.LOCK_DIR`。测试普遍在
  `require` 之后改写 `core.DATA_DIR`，常量不会跟着变 —— 于是测试会去锁真实的
  `/etc/substore`。改为由 `M.DATA_DIR` 现算。另一处：全新安装时 `DATA_DIR` 尚不存在，
  `mkdir <DATA_DIR>/.lock` 失败，而失败在 `lock_acquire` 眼里等同于「他人持锁」，
  症状是第一次保存订阅就报「正被另一个进程修改」；已在取锁前先 `ensure_dirs()`。
- **1.1**：`M.merge` 是**只读**的（只读各订阅节点、过滤排序后返回数组），
  包进锁后一旦取锁失败会返回 `nil` 顶掉原本的数组，把「拿不到锁」变成调用方眼里的
  「没有数据」—— 比不加锁更糟。已移出包装列表。

| 项 | 推荐方案 | 理由 | 前置条件 |
|---|---|---|---|
| 1.1 H10 无锁 | ✅ **C**：`mkdir` 原子锁 + 陈旧锁回收 | 纯 Lua、无新依赖，本机**可测**（桩掉 `os.execute` / `os.time`）；崩溃残留锁由锁目录 mtime 自愈 | 已定阈值 `util.LOCK_STALE = 60` 秒 |
| 1.3 sing-box 读取侧 transport 丢失 | ✅ **已修复**（补 `transport` 解析） | 与 F5/F6/F11 同类：静默丢传输层 → 节点连不上；影响面更大 | 字段映射**已核实**（见 1.3 正文） |
| 1.4 死代码 + README 声明不符 | ✅ **已删除**死代码（并已随 `[2.6.10-r1]` 精简 README 声明） | 删去了「协议转换：任意协议 → 任意协议」的过度声明 | 已确认无任何 `require` |
| 1.5 QX `tag=` 逗号 | ✅ **B**：整体丢弃 | 见上文 | 已实施；QX 实际行为仍未实测（无 QX 环境），按「宁可丢节点也不输出损坏行」处理 |
| 2.1 混合格式文本导入 | ✅ **B+**：本地导入时明确报错（`[2.6.16-r1]`） | 见 2.1 正文；远程订阅路径刻意不动 | 无 |
| 2.2 hysteria v1 `up`/`down` | ✅ **A**：确认为已知限制 + 文档（`[2.6.16-r1]`） | 补字段属新功能，且单位/缺省值规格未核实 | 无 |
| 2.3 hysteria v1 URI 规范 | ✅ **维持现状** + 文档（`[2.6.16-r1]`） | 上游规范无法核实，按「不猜」原则不动 | 找到权威规范后再定 |
| 2.4 `http` 不进 UI | ✅ **A**：确认为已知限制 + 文档（`[2.6.16-r1]`） | 规格 §25 是否有意排除未核实，现状无功能损失 | 无 |
| 2.5 `parser_yaml.lua` 死代码 | ✅ **已删除** | 死代码会被后续审计反复重新评估，成本高于收益 | 已确认只被 `parser.lua` 一行 `require` 引用、且从未使用 |
| 3.1 AWG 逐字段化 UI | ✅ **确认为已知限制** + 文档（`[2.6.16-r1]`） | 数据往返已正确，仅录入体验 | 无 |
| 3.2 / 3.5 wget 体积与重定向 | ✅ **确认为工具限制** + 文档（`[2.6.16-r1]`） | busybox wget 无对应选项；curl 路径已无此问题 | 无 |
| 3.3 改名规则 `(a\|b)` | ✅ **A**：维持现状 + 文档说明 | Lua 模式无 alternation；自实现展开要处理嵌套与字符类，收益低 | 已在 README.md / README.en.md 的「使用方法」补说明（顶层 `\|` 才是「或」，`(...)` 内按字面） |

---

# 六、本轮实施记录（`[2.6.16-r1]`）

本轮按「处置优先级 1–8」实施，逐项记录如下。**每项都补了自包含回归测试，并对
`HEAD` 做了反向验证**（新断言在修复前失败、修复后全绿）—— 反向验证是必须的：
只证明「修复后测试通过」无法排除「这条断言本来就不会失败」。

| 优先级 | 项 | 位置 | 回归测试 | HEAD 上失败断言数 |
|---|---|---|---|---|
| 1 | wget 后端 SSRF 缺口（见 3.4） | `http.lua` `fetch_wget` | `tests/dns_fallback_test.lua` 用例 H / H2 | 3 |
| 2 | 删除部分失败时漏写 cron | `controller/admin/substore.lua` `action_delete` | `tests/controller_robustness_test.lua` | 1 |
| 3 | 混合格式静默丢弃（见 2.1） | `parser.lua` `detect_all` + `parse_local` | `tests/parser_mixed_format_test.lua`（70 条） | 探针：`nodes=1, err=nil` |
| 4 | 写入失败被忽略 | `core.lua` `M.remove` / `M.ensure_token` | `tests/data_integrity_test.lua` | 5 |
| 5 | `post_ok()` 空 token 放行（见 1.2 M28） | `controller/admin/substore.lua` | `tests/controller_robustness_test.lua` M28 段 | 7 |
| 6 | 无 ACL（见 1.2 M29） | `rpcd/acl.d` + `menu.d` + `Makefile` | `tests/acl_menu_test.lua`（19 条） | 13 |
| 7 | A4–A7 记文档（2.2 / 2.3 / 2.4 / 3.1） | README / 本文件 | —（无代码改动） | — |
| 8 | wget 体积与重定向记文档（3.2 / 3.5） | README / 本文件 | —（无代码改动） | — |

**优先级 2 的详细依据**（该缺陷不在本文件原有清单内，是实施前代码级审计新发现的）：

`action_delete` 原先只在**全部删除成功**时调用 `core.write_cron()`，部分失败时
直接 `return back_to_list(...)` 跳过了它。后果：被删掉的订阅的 cron 行仍留在
crontab 里，`substore-cron.sh` 会拿着已不存在的 id 反复执行，每次都以非 0 退出
（脚本末尾有 FAILED 判断），在日志里刷失败、并让监控误报。现改为
**只要有订阅真的被删掉（`removed > 0`）就重写 cron**，与成功/失败分支无关。

**优先级 4 的详细依据**（同样是本轮审计新发现）：

`core.lua` 的 `save()` 返回 `util.atomic_write(...)` 的结果 —— 失败时是
`false, err`，而 `M.remove` / `M.ensure_token` 此前**丢弃了返回值**：写盘失败时
`M.remove` 仍报成功（订阅文件已删、索引没更新 → 索引指向不存在的订阅），
`M.ensure_token` 会把一个**没有落盘**的 token 返回给调用方（页面显示 token，
实际不存在）。现改为透传失败与原因。回归测试用 `util.atomic_write` 猴补丁注入
写失败，断言：`remove` 报失败**且保留** nodes 文件、`ensure_token` 返回 `nil, err`、
失败恢复后能正常写入。

---

# 七、2.7.2 审计新发现

本节是给 AnyTLS + Reality 支持做代码级审计时**顺带确认**的问题。
每条都给出**实测探针或上游文档依据**，无推测项。

**状态**（决策已定，按轮次实施）：

| # | 决策 | 状态 |
|---|---|---|
| 7.1 | A：引入 `FAMILY_CAPS` 按客户端能力表过滤 | 待实施（第二轮） |
| 7.2 | A：真正实现 Egern YAML 生成器 | 待实施（第三轮） |
| 7.3 | C：只对带 `public-key` 的 vmess / vless 分叉 `qx_tls` | 待实施（第二轮） |
| 7.4 | A：Loon 位置参数化（并给 `public-key` 加双引号） | 待实施（第二轮） |
| 7.5 | 修复 | **已修复**（第一轮，见下） |
| 7.6 | 修复 | **已修复**（第一轮，见下） |
| 7.7 | A：后端错误串 msgid 化 | 待实施（第四轮） |
| 7.8 | A：删除 `age.lua` / `age_test.lua` | **已删除**（第一轮） |

7.5 / 7.6 的修复见本节末尾「7.5 / 7.6 修复记录」。

| # | 问题 | 位置 | 依据 | 影响 |
|---|---|---|---|---|
| 7.1 | Surge 格式会为 VLESS 节点生成代理行，而 Surge 的协议清单里没有 VLESS | `output_formats.surge_config` | Surge 手册（`manual.nssurge.com`）协议清单无 VLESS；探针见下 | 节点必然不可用（Surge 对「不认识的代理行」的处置**未获官方证实** —— 官方只说明过无法识别的 *section* 会原样保留且不报错；此处按「不输出客户端读不懂的东西」处理，与丢弃 wireguard / ssr 同一约定） |
| 7.2 | Egern 格式输出的是 Surge 逗号行，而 Egern 的配置是 YAML | `output_formats.to_egern` | `egernapp.com/docs/configuration/proxies/`；探针见下 | 选 Egern 格式导出的内容 Egern 读不了 |
| 7.3 | QX 的 vmess / vless 用 `tls-host=` + `tls-verification=true` 表示 TLS，官方 `sample.conf` 用 `obfs=over-tls` / `obfs=wss` + `obfs-host` | `output_formats.qx_tls` | `crossutility/Quantumult-X` 的 `sample.conf`；探针见下 | 见 7.3 的详细说明 —— **会让新加的 QX vmess/vless Reality 公钥不生效** |
| 7.4 | Loon / Surfboard 的 trojan / vmess / vless 凭据在官方文档里是**位置参数**，本生成器一律写具名参数（只有 anytls 按 flavor 分对了） | `output_formats.surge_line` | `nsloon.app/docs/Node/` 的示例行 | Loon 是否同时接受具名写法**无文档依据**，待核实；若不接受则这几类节点导出到 Loon 后连不上 |
| 7.5 | ~~`parser_surge` 的行拆分不是引号感知的（`rest:gmatch("[^,]+")`）~~ **已修复** | `parser_surge.lua` 的 `split_fields` | 代码级：位置参数里含逗号的值会被切断 | 别人给的 Loon / QX 配置里带逗号的密码被**静默截断**（生成端已有「含逗号就整条丢弃」的防护，解析端没有对应防护） |
| 7.6 | ~~Loon 的 `transport=ws` 未映射到 `net`~~ **已修复** | `parser_surge.parse_surge_line` 的 `transport=` 分支 | 只认 `ws=true`（Surge 旧写法）与 `obfs=ws`（QX）；`nsloon.app/docs/Node/` 用 `transport=ws` + `path=` + `host=` | Loon 的 ws 节点导入后 `net=tcp`，`path` / `host` 全丢 → 导出到任何格式都按 tcp 连，握手失败**且不报错** |
| 7.7 | 后端模块仍有 **113 处**硬编码中文字符串字面量（注释外） | `core.lua` 47 / `http.lua` 47 / `parser.lua` 9 / `util.lua` 5 / `output_wireguard_conf.lua` 3 / `node.lua` 2 | 扫描脚本（去注释后提取含 CJK / 全角的字符串字面量），见下 | 控制器文案已接入 i18n，但这些来自后端的失败原因经 `?err=` **原样**显示，英文界面下仍是中文 |
| 7.8 | ~~`root/usr/share/substore/age.lua` 与 `tests/age_test.lua` 未被 git 跟踪，且 `age.lua` 未被任何模块 `require`~~ **已删除** | 仓库根 | `grep -rn require` 无引用 | 未随包发布；留在工作区会被后续审计反复重新评估 |

### 7.7 的统计口径与例外（修复前必读）

本节原先写的「约 103 处（`grep -c 'return nil, ".*[^ -~]'`）」**口径有误**：
那条 grep 按行匹配，既会把中文注释算进去，又会漏掉「只含全角标点」的字面量
（如 `"，"` 这类），逐文件数字也对不上。下面是重新核对的口径。

**统计方法**：先去掉注释（`--` 行注释与 `--[[ ]]` 块注释），再提取字符串字面量
（`"` 与 `'`），保留其中含 CJK / 全角字符的（UTF-8 首字节 `E3`–`E9` 或 `EF`）。
结果 **113 处**：`core.lua` 47 / `http.lua` 47 / `parser.lua` 9 / `util.lua` 5 /
`output_wireguard_conf.lua` 3 / `node.lua` 2。

其中 **76 处**是直接的 `return nil, "…"` / `return false, "…"` 形式；另外 37 处是
同一类文案经别的路径到达用户，例如：

* `core.lua` 的 `M.save_meta(id, { error = "…" })` —— 同一个串既写进 meta
  （列表页用 `it.error` 显示）又被 `return` 出去，**两处必须用同一个 msgid**；
* `:format()` / `..` 拼接出来的串（如 `"HTTP 错误 "`、`"响应超过大小限制 ("`）；
* 表项（`FORMAT_LABELS`）与视图直接渲染的标签（`human_duration`）。

**三处不能照搬 msgid 化**：

| 位置 | 内容 | 为什么特殊 |
|---|---|---|
| `node.lua:377` | `"[^,%s，]+"` | 这是**正则字符类**，全角逗号是模式的一部分，翻译会直接破坏关键词拆分 |
| `util.lua:658` `M.human_duration` | `"已过期"` / `"%d天"` / `"%d小时"` / `"%d分钟"` / `"不足1分钟"` | 由**视图** `view/substore/form.htm:39` 直接渲染，不走 `?err=`；应在视图侧翻译（或 msgid 化后在视图 `_()`） |
| `parser.lua:103` `FORMAT_LABELS` | `"URI 链接"` / `"Surge/Loon 配置"` | 是**格式显示名**，被插进「混用多种格式」的错误文案里 |

**关键设计点**：`meta.error` 会被 `it.error` 原样显示，所以 msgid 必须**语言中立**
（英文），翻译只发生在显示边界（视图 / 控制器），后端模块不得 `require("luci.i18n")`
—— `substore-cron.sh` 会在独立的 lua 进程里跑 `core.sync`，那里没有 LuCI 环境。

## 7.1 / 7.2 / 7.3 的实测探针

```
$ lua5.1 -e '... out.generate({vless节点}, "surge", {name="P"}) ...'
[Proxy]
V = vless, 1.2.3.4, 443, username=u, tls=true        ← Surge 协议清单里没有 vless

$ lua5.1 -e '... out.generate({vmess节点}, "egern", {name="P"}) ...'
[Proxy]
M = vmess, 1.2.3.4, 443, username=u, tls=true        ← Egern 的配置是 YAML，不是逗号行

$ lua5.1 -e '... out.generate({vmess+reality节点}, "qx", {name="P"}) ...'
[server_local]
vmess=1.2.3.4:443, method=none, password=u, tls-host=s.example.com,
tls-verification=true, reality-base64-pubkey=PBK, reality-hex-shortid=SID, tag=R
```

## 7.3 详细说明（唯一一条会影响本次新功能的）

`sample.conf` 的说明原文（`crossutility/Quantumult-X` 仓库，`[server_local]` 前）：

> …if the corresponding line (socks5: `over-tls=true`, http: `over-tls=true`,
> trojan: `over-tls=true` or `obfs=wss`, anytls: `over-tls=true`, … vmess:
> `obfs=over-tls` or `obfs=wss`, vless: `obfs=over-tls` or `obfs=wss`) contains
> the `reality-base64-pubkey` param, then the standard TLS will be replaced with
> the Reality.

即：QX 里 vmess / vless 的「TLS 标志」写作 `obfs=over-tls`（或 `obfs=wss`），
trojan / anytls 才写 `over-tls=true`。而 `qx_tls()` 对所有协议统一输出
`tls-host=` + `tls-verification=true`（探针第三段可见）—— 于是 vmess / vless 的
`reality-base64-pubkey` **很可能被 QX 忽略**，节点退回普通 TLS。

本次**没有**改 `qx_tls()`：它是既有实现，改动会让**所有** QX vmess / vless TLS
节点的输出形态变化（不只是 Reality 节点），需要单独决策与回归；而且
`tls-host` / `tls-verification` 在 QX 里是否对 vmess / vless 同样有效**没有找到
官方依据**（`sample.conf` 里只用 `obfs=` 形式，但「未出现」不等于「无效」）。
本次只保证：**只要 TLS 标志生效，公钥就已经写在那行上了**（`qx_reality()` 覆盖
vmess / vless / trojan / anytls 四类，与 `sample.conf` 的 Reality 条目一致）。

**处置候选**：A. 维持现状 + 本节记录；B. `qx_tls()` 按协议分叉（vmess / vless 走
`obfs=over-tls` + `obfs-host`，trojan / anytls 维持现状），需要同步更新
`parser_surge.parse_qx_line` 的读取端与 `tests/protocol_registry_test.lua`。

## 第一轮修复记录（7.5 / 7.6 / 7.8）

**7.5 引号感知切分** —— 新增 `parser_surge.split_fields()`（`parser_surge.lua`），
`parse_surge_line` 与 `parse_qx_line` 的切分都改走它。规则：

* 先数引号个数，**奇数则退回旧的 `gmatch("[^,]+")`**。订阅内容不可信，落单的
  引号若被当成「开引号」，会把后面的 `sni=` / `over-tls=` 全吞进同一个字段，
  比按逗号切更糟。
* 偶数时按引号开合切分，引号内的逗号不再是分隔符；引号本身保留在字段里，
  由既有的 `unquote()`（Loon 位置参数）或原样（QX kv 值）处理。
* 无引号的输入与旧实现**逐字符等价**：同样按逗号切、同样丢弃空字段、同样 trim。

**7.6 Loon 传输参数** —— `parse_surge_line` 增加 `transport=` / `path=` / `host=`
三个映射（`transport=http` 按 Loon 文档「会按 WebSocket 处理」落成 `ws`），放在
`ws=true` / `ws-path` / `ws-headers=Host:` 之后，同一行两种写法都出现时**以新写法为准**。

**回归测试**：新增 `tests/parser_surge_fields_test.lua`（36 条断言），覆盖两个
缺陷的修复点、旧写法回归、无引号输入的逐字符等价、空字段边界、奇数引号边界、
以及「新写法优先」。文件头写明「修复前应当失败」。

**反向验证**：把 `parser_surge.lua` stash 掉后跑该文件，得到 **12 条 FAIL**，症状
与预测完全一致（`"pa` / `"p` / `"uu` 被截断的凭据、`net=tcp`、`path=nil`、
`host=nil`、旧写法的 `/old` 与 `old.example.com` 胜出）；`git stash pop` 后
**0 条 FAIL**。全套测试 58 个文件、0 失败。

**7.8 删除** —— `root/usr/share/substore/age.lua` 与 `tests/age_test.lua` 已从工作区
删除。审计复核发现它们并非「写完没人用」的死代码，而是**未完成的半成品**：
`age.lua` 文件头声称实现了 sha256 / hmac-sha256 / hkdf / chacha20 / poly1305 /
x25519 / bech32 / armor / STREAM，实际只写到 `M._hkdf_sha256` 就停了，末尾留着
`-- @@NEXT@@` 续写标记（全仓库仅此一处）；`tests/age_test.lua` 引用的
`tests/age_vectors/README.md` 根本不存在。两者都**未被 git 跟踪**，删除即不可恢复，
因此删除前已在仓库外留了一份备份（`~/age-lua-wip-backup-2026-10-05/`，含
`age.lua` 与 `tests/age_test.lua` 两个原文件）。后续若要继续这条线，从该备份恢复即可。

---

# 附：P2 修复范围（不含本文件所列项）

P2 为审计表中**其余中危 / 低危**项中性质明确、无需另行决策的缺陷，例如
M6 / M9 / M13 / M14 / M16 / M17 / M18 / M19 / M23 / M24 / M25 / M26 / M27 / M30
与 L1 / L3～L6 / L8～L26 等。逐项修复并补回归测试，完成后在 CHANGELOG 中记录。
本文件所列各项**不在** P2 范围内。
