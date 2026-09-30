# Changelog — luci-app-substore

All notable changes to this project will be documented in this file.

## [2.6.0-r1] - 协议覆盖补全与导入/输出保真修复

本轮起因：用户报告「添加本地订阅 → 表单导入」的「类型」下拉框协议不全，
与 README 描述不符。审计后确认问题存在，且**「文本导入」存在更严重的同类缺口**，
并顺带查出若干静默数据丢失 / 非法输出问题。所有修改均经代码或测试确认，
未做任何推测性改动。

### 协议覆盖（本次报告的主问题）

- **表单导入缺 `hysteria`(v1) 与 `socks`**：`nodeform.js` 的下拉框只有 8 个协议，
  而 `node.lua` 的 `M.PROTOS`、节点页协议筛选、规则 `proto_filter` 都认 10 个。
  用户因此无法用表单录入这两类节点。
- **文本导入（URI）缺 `hysteria`(v1) 与 `socks`/`socks5`**，且这是**导出→导入回环断裂**：
  `output_uri.to_share_uri` 会生成 `hysteria://` 与 `socks5://` 链接，但 `parser.parse_uri`
  对二者一律返回 `unsupported proto`。含这两类节点的订阅文本会被**整行静默丢弃**。
  已新增 `parse_hysteria` / `parse_socks` 并补齐 `SUPPORTED` 分发表。
- **简易 YAML 兜底解析的协议表漂移**：该处自维护一份映射，缺
  `hysteria2` / `hysteria` / `tuic` / `wireguard`，且 `socks5` 未归一，更严重的是
  对认不出的 `type` 用 `or "vmess"` 兜底 —— 一份 sing-box YAML 里的
  hysteria2/tuic/wireguard 出站会变成数个**字段全错的假 vmess 节点**（静默数据损坏）。
  现改为复用 `parser_clash_yaml.TYPE_MAP`（单一事实来源），未知协议直接丢弃。
- **简易 YAML 兜底解析的 `outbounds:` 分支从不生效**：该分支同时接受 Clash 的
  `proxies:` 与 sing-box 的 `outbounds:` 段名，却只读 Clash 的 `port` / `name`，
  而 sing-box 用 `server_port` / `tag`。结果是 sing-box YAML 出站**全部被静默丢弃**
  （识别了段名却解析出 0 个节点）。现按 `parser_json_config.parse_singbox_json`
  读取的键名逐字补齐别名：`server_port` / `tag` / `auth_str` / `auth` /
  `tls.server_name` / `tls.insecure` / `security`(vmess 加密方式) / `network`。

### 归一化

- **`socks5` → `socks` 归一**：两者是同一协议的不同写法（Clash 写 `socks5`、
  sing-box 写 `socks`、分享链接写 `socks5://`）。输出模块本来就同时认两种写法，
  但 `node.filter` 与 `rules.proto_filter` 是精确比较，两种写法互相看不见 ——
  节点页按协议筛选与规则过滤都会漏。现统一为规范名 `socks`。

### 输出保真

- **clashmeta：hysteria(v1) 的 SNI 丢失**。此前统一输出 `servername`，而 mihomo 的
  hysteria 系列没有该字段（写 `servername` 会被忽略），SNI 丢失会导致客户端
  以 IP 校验证书、握手直接失败。现按协议区分：hysteria / hysteria2 输出 `sni`，
  vmess / vless / trojan 仍输出 `servername`。同时补上 v1 的 `obfs`（普通字符串）。
- **clashmeta：socks5 的 `password` 被输出两次**（通用字段段 + 协议专属段），
  在 YAML 里形成重复键，属非法/歧义配置。现协议专属段只补 `username`。
- **clashmeta / singbox / surge：`http` 的用户名丢失**，只输出密码。现按上游文档
  补齐 `username`（mihomo 的 http / socks5 用 `username` + `password`；
  Surge 家族用 `username=` / `password=` 具名参数）。
- **singbox：hysteria(v1) 字段名错误**。此前输出 `password` 与
  `obfs = { type, password }`，但 sing-box 的 hysteria 出站认证字段是 `auth_str`，
  `obfs` 是**普通字符串**（对象形式是 hysteria2 的 salamander 专属）。
  该修正与本项目 `parser_json_config` 自身的回读逻辑一致
  （其按 `outbound.password or outbound.auth_str or outbound.auth` 读取）。
- **`output_uri` / `output_clash_meta`：hysteria(v1) 不应出现 `obfs-password`**。
  该字段是 hysteria2 的 salamander 专属，写到 v1 上是非法参数/非法键。

### 表单

- **`core.FORM_KEYS` 缺 `username`**：`merge_form_node` 先按 `FORM_KEYS` 清空原节点
  再套用提交值，不在表里的字段会保留旧值 —— 用户在表单里**清空用户名也删不掉**
  （`collectNodes` 会略过空值）。已补入。

### 已知限制（本轮不修，均有明确原因）

- **混合格式文本导入不支持**。README 称可粘贴「YAML / URI / JSON / wg-quick `.conf` 混合」
  文本，但 `parse_local → parse → detect` 只识别**一种**格式，其余部分被静默丢弃
  （已实测：「URI + WG conf」只剩 WG 节点；「URI + JSON」只剩 URI 节点）。
  这是**功能缺失**而非小缺陷，需要重新设计 parser 的分段架构（规格 §22 明确警告
  不要直接采用未经验证的逐行算法），故留待专门版本处理。
- **sing-box 的 hysteria(v1) 出站还要求 `up` / `down`（带宽）**，本项目的节点模型
  不承载该字段。凭空填默认值属于猜测，故不输出；用户需在自己的配置里补上。
- **hysteria(v1) 的上游 URI 规范未能核实**（上游文档站点持续 404，无法取得权威定义）。
  因此 `parse_hysteria` 只保证解析本项目 `output_uri` 自身生成的链接形态
  （回环已验证），认不出的查询参数一律忽略而不报错，不臆造参数语义。
- **`http` 不加入任何 UI 协议列表**：规格 §25 的权威协议表恰好是 10 个协议、不含 `http`。
  它可由 Clash YAML / JSON 配置导入并正常导出（凭据已修），但不作为表单可选项。
- **`parser_yaml.lua` 为死代码**（`parser.lua` 顶部 require 后从未调用），
  其中留有同样未归一的 `socks5` 映射，仅记录，不影响运行。
- **`parse_tuic` / `parse_hysteria2` 按第一个 `@` 切分 userinfo**，与 `parse_socks`
  修复前同类（密码含裸 `@` 会被切坏）。本轮只修了 socks，其余留作观察项。

### 测试

- 新增 `tests/protocol_coverage_test.lua`（110 项断言），覆盖上述全部修复：
  hysteria / socks 的 URI 导入与导出→导入回环、混合文本不再丢行、
  兜底解析不再造假日 vmess、sing-box YAML 出站别名、`socks5` 归一后筛选/规则命中、
  clashmeta / singbox / surge 的输出字段、`FORM_KEYS` 的 `username`。
- 全量测试：`tests/*_test.lua` 逐文件运行，**0 个失败文件**；
  `tests/cron_result_test.sh` rc=0。

### 版本

- 版本号 2.5.1-r1 → 2.6.0-r1（协议覆盖为功能增强，走 minor）；
  `README.md` / `README.en.md` / `docs/INSTALL.md` 同步。

## [2.5.1-r1] - 安全加固与数据保真修复

本轮为缺陷修复版本，重点是**命令注入 / SSRF 绕过 / 静默数据丢失**三类问题。
所有修改均经代码或测试确认，未做任何推测性改动。

### 安全

- **修复命令注入（可被远程触发）**：此前拼 shell 命令行时使用 `string.format("%q")`
  做转义。`%q` 生成的是**双引号**字符串，而 `/bin/sh` 在双引号内**仍然执行**
  `$(...)` 与 `` `...` `` 命令替换——已实测确认 `format("%q", "$(touch /tmp/x)")`
  会真的创建文件。新增 `util.shq()` 改用单引号转义（`'` → `'\''`），并应用于所有
  拼接外部数据的位置：
  - `http.lua`：curl / wget 命令行、临时文件路径、`-x` 代理参数、错误输出文件
  - `http.lua`：`http_proxy` / `https_proxy` 环境变量赋值
  - `core.lua`：`logger -t luci-app-substore <msg>`（msg 含下载失败原因等外部内容）
  - `probe.lua`：探测命令
  - `util.lua`：`ensure_dir` 的 `mkdir -p`
- **修复 SSRF 检查绕过（fail-open）**：`http.parse_url` 只按 `/` 截断主机部分，
  于是 `http://127.0.0.1?a=1` 的「主机」是 `127.0.0.1?a=1`——既非合法主机名也非
  数值型 IPv4，DNS 解析必然失败，而**解析失败是放行的**，`curl` 实际连的是回环地址
  （路由器上正是 LuCI 的 `:80`）。现按 RFC 3986 截断到第一个 `/` `?` `#`，
  并额外剥离 userinfo（`http://evil@127.0.0.1/` 同理可绕过）。
- **修复 curl 后端接受 3xx**：`code:match("^[23]%d%d$")` 会把 3xx 当成成功。
  重定向应由 `-L` 跟随并由 `validate_redirect_chain` 逐跳校验，而不是靠 3xx 直接放行；
  现只接受 `2xx`。
- **修复 wget 后端不检查退出码**：`os.execute` 的返回值此前被忽略，
  下载失败但残留部分内容时会当成成功解析。现要求退出码为 0。

### 数据保真（静默丢字段）

- **修复从 LuCI 表单编辑 WireGuard 节点会丢掉全部 AmneziaWG 参数**：
  `amnezia-wg-option` 在表单里是 JSON 文本框，提交上来是**字符串**，
  而 `output_wireguard_conf` / `output_clash_meta` / `output_uri` 三处都要求它是
  `table`——字符串被静默忽略。现于表单模式统一解码；JSON 非法时**明确报错**
  而不是留个字符串让它在导出时无声消失。
- **修复表单里的数组字段被写成标量**：`allowed-ips` / `reserved` / `dns` 在统一模型中
  是数组（见 `.conf` 解析），但表单输入框只能给字符串，导出到 mihomo / sing-box
  时字段类型非法（这两个客户端的对应字段是列表）。现于表单模式拆分为数组；
  单值 `dns` 仍保持字符串，与 `.conf` 解析保持一致。
- **修复 AmneziaWG 3.0 / 3.1 字段在 `.conf` 导入时被丢弃**：`.conf` 键名白名单只到
  1.5 版，`HeaderProtectionKey` / `ContentPaddingAddition` / `RekeyAfterTime` /
  `RekeyTimeout` / `RejectAfterTime` / `KeepaliveTimeout` / `MaxHandshakeAttempts` /
  `RandomTrailers` / `DisableCookies` 九个字段在导入时被丢掉，而同样的配置走
  Clash / JSON / URI 路径却能通过——同一份配置换个格式就丢参数。键名核对自
  amneziawg-tools `src/config.c`；布尔字段按 `parse_bool` 的规则只认 `on` / `off` / 数字。
- **修复多个 `[Peer]` 的 `.conf` 只产出部分节点**：现每个 `[Peer]` 各生成一个节点
  并共享 `[Interface]` 设置；AmneziaWG 参数表**按节点复制**，避免多个节点共享
  同一个 table 而互相影响。
- **修复节点改名规则中的 Lua 模式陷阱**（`node.lua`）：
  - `-` 在 Lua 模式里是**惰性量词**，于是 `Node-(\d+)` 被解释成 `Nod` + `e-` + 数字，
    **永远匹配不上且不报错**。现于字符类外转义为 `%-`
  - `|` 在 Lua 模式里没有「或」语义，整个规则静默不匹配。现按**顶层** `|` 拆成多个
    候选依次替换；括号内与字符类 `[...]` 内的 `|` 不拆（拆开会得到残缺模式，比不拆更糟）
  - `\b` / `\B` 原被映射成 `%b`——那是 Lua 的「成对匹配」模式，语义完全不同。
    现按无操作处理（Lua 模式无词边界）
  - 模板改名的替换值现在转义 `%`，否则 `[50% OFF]` 这类名字会产生 NUL 字节
- **修复 Clash YAML 的 `type` 字段泄漏进节点**：`type` 是协议判别字段（已被映射为
  `proto`），原样拷进来会让 `output_uri` 把它当成 vmess 的 header type 写出
  （`"type":"vmess"`），生成客户端无法识别的 `vmess://` 链接。
- **修复订阅流量信息无法清空**：`save_meta` 用 `pairs` 遍历补丁，而 `pairs` 永远
  不会给出 `nil` 值，调用方无法表达「把这个字段删掉」，导致过期的流量/到期时间
  一直显示。新增 `core.CLEAR` 哨兵表达清除。

### 界面

- **修复节点保存失败无反馈**：`action_node_save` 此前只在成功分支做事，
  其余情况一律静默重定向——用户提交了坏数据却看到「已保存」的样子（违反 §18）。
  现所有失败路径（下标无效 / 内容为空 / 解析失败 / 写入失败）都经 `?err=` 回传，
  并在节点页渲染为可见的错误提示。
- **修复存储型 XSS**：节点页的分组下拉与组合订阅页的名称用 `<%= %>` 原样输出
  （未转义），恶意订阅里的分组名/名称可注入脚本。现统一走 `luci.util.pcdata()`。

### Cron

- **退出码现在反映本轮结果**：`substore-cron.sh` 此前无论成败一律 `exit 0`，
  cron 的 `MAILTO` / 外部监控无法据此判断。现只要有订阅更新失败即返回非 0；
  找不到 lua 解释器（整条链路不可用）同样返回非 0，而不是静默成功。

### 解析器补齐

- `vless://` 补 `path` / `host` / `flow`；`vmess://`（新格式）补
  `host` / `path` / `headerType` / `fp` / `alpn`；`trojan://` 补
  `type`→`net` / `path` / `host` / `fp`；`hysteria2://` 补 `security` 与
  `skip-cert-verify`；经典 vmess JSON 的 `aid` 正确映射为 `alterId`
- `b64u_decode` 增加 round-trip 校验：合法 base64url 解码后重新编码必然一致，
  明文则不一致——以此区分「这是 base64」和「这就是明文」，避免把明文
  误当 base64 解出乱码
- `M.detect` 调整判定顺序：Surge 配置在 URI 兜底分支之前判定，避免被误判成 URI

### 测试

- 新增 `tests/security_fixes_test.lua`（37 项）：`shq` 用真实 `sh -c` 验证命令替换
  不发生；`parse_url` 的 query / fragment / userinfo 剥离；`save_meta` 的 `CLEAR`
  语义；改名的 `-` / `|` / `%` 行为
- `tests/cron_result_test.sh` 增加退出码断言（含缺解释器、无订阅文件两种边界），
  并验证该测试确实能捕获修复前的行为（对旧脚本跑会失败 3 项）
- `tests/controller_local_test.lua` 增加 `action_node_save` 的 6 条失败路径断言，
  同样验证对旧控制器会失败 6 项
- `tests/wireguard_conf_test.lua` 增加表单路径断言（AWG JSON 解码、数组归一、
  非法 JSON 报错、单值 DNS 保持字符串），并覆盖 AWG 3.0 / 3.1 字段导入与多 `[Peer]`
- 全量：33 个 `tests/*_test.lua` 共 **1286** 项断言全部通过；shell 测试 11 项通过

### 已知限制（未在本轮修复）

- LuCI 里 `amnezia-wg-option` 仍是**单个 JSON 文本框**，没有逐字段的表单控件。
  数据已能正确往返（见上），但录入体验不佳。逐字段化属于新功能，按版本约定
  应进入 minor 版本，故不在 2.5.1 中改动。
- wget 后端的下载体积上限仍是**下载后**判断（busybox wget 没有「下载前限流」的选项）。
- 括号内的「或」`(a|b)` 在改名规则中不支持（Lua 模式无此语义，按字面处理）。

### 版本

- 版本号 2.5.0-r1 → 2.5.1-r1；README.md / README.en.md / docs/INSTALL.md 同步

## [2.5.0-r1] - 订阅可靠性、错误反馈与 WireGuard 去重修复

- **修复严重缺陷（订阅更新可能「看起来成功其实失败」）**：`core.sync` 失败时是
  「返回 `nil, err`」而**不是**抛异常，而调用方只判断了 `pcall` 的第一层返回值。
  `pcall` 返回 `true` 只说明没有抛错，第二个返回值才是 `sync` 自身的结果——
  于是「同步返回 `nil, err`」被统计成**成功**。
  - `root/usr/bin/substore-cron.sh`：改为 `local ok, res, err = pcall(core.sync, id)`，
    并要求 `ok and res` 才算成功；失败时打印真实原因。同时把脚本输出同时写 stdout 与
    syslog（原先只进 syslog，cron 邮件里看不到）
  - `root/usr/lib/lua/luci/controller/admin/substore.lua`：`action_update` 同样处理两层结果
- **修复严重缺陷（代理静默失效，属 silent fallback）**：
  - `core.sync` 原先在「代理已启用但代理地址无效」时只记一条日志就**直连下载**，
    用户会以为流量走了代理、实际暴露真实 IP。现改为**明确失败**并把原因写入订阅状态
  - wget 后端原先在遇到它不支持的代理协议（`socks*`）时**丢掉代理继续直连**。
    现改为明确报错并提示安装 curl 或改用 http 代理（busybox wget 只能通过
    `http_proxy` / `https_proxy` 环境变量使用 http(s) 代理）
- **修复严重缺陷（wget 后端重定向绕过 SSRF 预检）**：curl 路径逐跳校验重定向目标，
  wget 路径**完全不校验**，可被重定向到 `127.0.0.1` / 内网而绕过 `check_public`。
  现 wget 改用 `-S` 输出响应头日志，由新增的 `http.validate_redirect_chain`
  按出现顺序解析整条重定向链并逐跳复检，任一跳不安全即整体失败并**丢弃响应体**。
  另修复协议相对地址（`//host/path`）被误当成同主机路径而漏检的问题
- **修复严重缺陷（界面失败无反馈）**：订阅的新建 / 保存 / 本地订阅新建 / 保存
  失败时，控制器只静默跳回列表页，用户看到的是「什么都没发生」，与成功无法区分。
  现失败原因经 `?err=` 回传到列表页并渲染为可见的错误提示
- **修复严重缺陷（WireGuard 节点被错误去重合并）**：去重键为 `proto+server+port`，
  而同一 endpoint 上的**不同 peer 公钥是不同节点**，会被错误合并而丢节点。
  现 WireGuard / `wg` 节点的去重键并入 peer 公钥（兼容 `public-key` / `public_key` /
  `peer-public-key` / `peer_public_key` 四种写法）；其余协议去重行为**完全不变**
- **修复严重缺陷（多个 WireGuard 节点被拼进一个 `.conf`）**：一个 `.conf` 文件只能包含
  一个 `[Interface]`，拼接会产生客户端无法导入（或只取首段）的畸形配置。
  现多于一个 WireGuard 节点时**明确报错**（错误信息含节点数与「一条隧道」提示），
  而不是静默拼接
- **修复 AmneziaWG `.conf` 导出键名靠猜测**：原先用「首字母大写」由内部键名推导 `.conf`
  键名，多词键会被写错（`header-protection-key` → `Header-protection-key`，
  正确为 `HeaderProtectionKey`），未知键可能让客户端拒绝整份配置。
  现改为显式映射表，只输出能**确定**键名的键（`Jc/Jmin/Jmax/S1–S4/H1–H4/I1–I5/J1–J3/Itime`），
  映射不到的键一律不输出；已支持键集合零变化
- **修复模板注入（HTML / JS）**：7 个模板把用户可控数据（订阅名、URL、代理、节点字段、
  解析错误信息）直接以 `<%= %>` 原样输出。现按上下文分别转义：
  HTML 用 `luci.util.pcdata`，注入 JS 的字符串用 `json_encode`（并转义 `</` 防止提前
  闭合 `script`），URL 用 `urlencode`
- **修复日志/错误信息泄漏凭据**：新增 `http.redact_proxy`（代理地址去凭据）与
  `http.scrub_credentials`（抹掉 URL 中的 `//user:pass@`），用于日志与订阅错误信息
- **修复失败路径污染 `node_count`**：同步失败时不再把 `node_count` 清零——
  磁盘上的旧节点仍在、订阅链接仍在下发，清零会让界面显示与实际不符
- 新增测试：`tests/controller_local_test.lua`（22 项）、`tests/template_escape_test.lua`（21 项）、
  `tests/cron_result_test.sh`（5 项）；`tests/wireguard_conf_test.lua` 扩至 93 项、
  `tests/node_extended_test.lua` 扩至 28 项、`tests/http_proxy_test.lua` 扩充代理矩阵与
  重定向链复检。全部测试共 1174 项断言通过
- 版本号 2.4.0-r2 → 2.5.0-r1；README.md / README.en.md / docs/INSTALL.md 同步
- 已知限制（本次**未**修改，另行处理）：`check_public` 在无 DNS 解析能力时放行
  （fail-open）且解析与下载之间存在 TOCTOU 窗口；wget 路径的重定向校验是事后的
  （busybox wget 无 `--max-redirect`），响应体虽被丢弃但请求已经发出，且无法限制下载体积；
  AmneziaWG 3.0 / 3.1 新增的 9 个字段（`HeaderProtectionKey`、`ContentPaddingAddition`、
  `RekeyAfterTime`、`RekeyTimeout`、`RejectAfterTime`、`KeepaliveTimeout`、
  `MaxHandshakeAttempts`、`RandomTrailers`、`DisableCookies`）**不被 `.conf` 解析器接受**
  （白名单外，导入即丢弃），但会从 Clash / JSON / `wireguard://` 导入路径原样透传；
  sing-box 本身不支持 AmneziaWG，其输出会丢弃 AWG 参数

## [2.4.0-r2] - 修复 vmess 加密方式与 TLS 层混淆

- **修复严重缺陷**：经典 vmess 分享链接 `vmess://base64(json)` 的 `scy` 是**加密方式**
  （`auto` / `aes-128-gcm` / `chacha20-poly1305` / `none` / `zero`），`tls` 才是 **TLS 层**
  （`"tls"` 启用，`""` 不启用）。解析器此前把 `scy` 写进了统一模型的 `security` 字段，
  而该字段在项目其余各处一律表示 TLS 层（`node.lua` DEFAULTS、vless/trojan URI 的
  `security=`、Xray `streamSettings.security`、Clash `tls: true`）
  - 后果：**一个不启用 TLS 的节点被三个目标同时误判为启用 TLS**，而这是机场订阅最常见的形态
    - sing-box 多出 `"tls": {}`，同时 `security` 被写成加密方式
    - V2Ray `streamSettings.security: "auto"` —— **非法取值，Xray 会拒绝启动**
    - Clash.Meta 多出 `tls: true`；Surge 家族多出 `tls=true`
  - 统一模型新增 `cipher` 字段专表 vmess 加密方式，`security` 回归纯 TLS 层语义
  - 解析侧：`parser.lua` 经典 vmess JSON 改为 `cipher = scy`、`security` 由 `tls` 推导；
    `parser_json_config.lua` 的 sing-box 导入改为 vmess 的 `security` → `cipher`，
    TLS 由 `tls` 对象表达（并补齐 `alpn` / `insecure` → `skip-cert-verify` 的反向映射）；
    `parser.lua` 简易 YAML 回退路径同步修正
  - 输出侧：`output_singbox.lua` / `output_v2ray.lua` / `output_uri.lua` 的 vmess 加密方式
    改取 `cipher`；`output_clash_meta.lua` 原本就取 `cipher`，此前因 `cipher` 从未被写入而
    恒回退到 `auto`（`cipher: aes-128-gcm` 这类非默认值会被静默丢弃，本次一并修复）
- **修复 `tls` 字段的真值陷阱**：空串 `""` 在 Lua 中为真值，`tls: ""`（经典 vmess JSON 表示
  「不启用 TLS」的标准写法）会被 `output_formats.lua` / `output_clash_meta.lua` 的
  `if node.tls then` 误判为启用 TLS。`node.normalize` 现将 `""` / `"none"` / `"false"`
  归一为 `nil`、`"true"`（简易 YAML 解析器的字符串布尔）归一为 `true`，并把 `tls` 统一
  落到权威字段 `security`
- **非法加密方式不再写入配置**：新增 `node.VMESS_CIPHERS` 白名单，非白名单取值
  （如被第三方工具误写成 `"tls"` 的）在归一化时丢弃，输出端回退到 `auto`，
  避免生成客户端拒绝加载的配置
- 新增测试 `tests/vmess_cipher_test.lua`（47 项），覆盖上述全部路径与分享链接回环
- 版本号 2.4.0-r1 → 2.4.0-r2；README.md / README.en.md / docs/INSTALL.md 同步

## [2.4.0-r1] - sing-box / V2Ray 输出完整配置

- ⚠️ **破坏性变更**：`target=singbox` 与 `target=v2ray` 由「仅含 `outbounds` 的片段」
  改为「`outbounds` + 分流的完整可用配置」。2.3.x 的片段需粘进已有配置使用；
  2.4.0 起可直接作为单文件配置启动。已粘进客户端的老链接会拿到不同结构，请重新导出。
- sing-box 完整配置（`output_singbox.lua`）
  - 节点出站 + `selector`（tag `select`，供手工切换）+ `urltest`（tag `auto`，自动测速）
    + `direct` / `block`
  - `route.final` 指向 `select`；内置 `ip_is_private` → `direct` 私网直连规则；
    `auto_detect_interface` 开启
  - **刻意省略 route 规则的 `action` 字段**：该字段自 sing-box 1.11.0 起才存在，其默认值
    即 `"route"`。sing-box 会拒绝未知字段，而省略默认值在 1.10 与 1.11+ 上都能工作
  - 无可用节点时不生成 `selector` / `urltest`（其 `outbounds` 不允许为空），`final` 退回 `direct`
- V2Ray / Xray 完整配置（`output_v2ray.lua`）
  - 节点出站 + `freedom`(tag `direct`) / `blackhole`(tag `block`) + `log`
  - `observatory`（`subjectSelector` / `probeUrl` / `probeInterval`）+ `routing.balancers`
    （tag `auto`，`leastPing`）——`leastPing` 必须依赖 observatory 的探测结果才会生效
  - `routing.rules`：`geoip:private` → `direct`，其后 `tcp,udp` 兜底 → `balancerTag: auto`；
    `domainStrategy` 为 `IPIfNonMatch`
  - 无可用节点时改为 `outboundTag: direct` 兜底，且不生成 `balancers` / `observatory`
- 两者均**不含 `inbounds` / `dns`**：会绑定本地监听端口、覆盖用户既有 DNS 设置，交由用户维护
- 修复 `util.json_encode` 无法表达空对象：Lua 空表经 `is_array` 判定会被编码成 `[]`，
  而 sing-box 的 `tls`、Xray 的 `settings` 必须是对象。新增 `util.JSON_EMPTY_OBJECT` 占位符
  - 由此修复一处既有缺陷：sing-box 节点 `security=tls` 但无 `sni` / `alpn` 时会产出非法的 `"tls":[]`
- 新增 `util.unique_tags(nodes, reserved)`：sing-box 与 Xray 均要求 outbound tag 唯一，
  节点重名（订阅里很常见）或与保留 tag（`direct` / `block` / `select` / `auto`）同名时
  自动追加 ` #2`、` #3`
  - Xray 的 balancer / observatory `selector` 按**前缀**匹配 tag，因此额外把保留 tag 的
    所有真前缀也登记为冲突——否则名为 `d` 的节点会让 `direct` 出站被误纳入负载均衡
- 导出结果可重新导入：完整配置里的 `selector` / `urltest` / `direct` / `block` /
  `freedom` / `blackhole` 会被解析器正确跳过，只取真实节点（已加往返测试）
- 新增测试 `tests/output_full_config_test.lua`（82 项）
- `tests/output_formats_test.lua` / `tests/ssr_test.lua` 更新为断言「不含 ssr 出站」
  而非「outbounds 为空」，适配完整配置语义
- 版本号 2.3.0-r2 → 2.4.0-r1；README.md / README.en.md / docs/INSTALL.md 同步

## [2.3.0-r2] - 新增 Clash 原版与 WireGuard .conf 输出，输出层清理

- 新增输出格式 **WireGuard / AmneziaWG `.conf`**（`target=wgconf`，别名 `wg` / `wireguard` / `amneziawg` / `amnezia` / `conf`）
  - 与 `parser.parse_wireguard_conf` 互为逆操作：输出 `[Interface]` / `[Peer]` 标准 wg-quick 配置
  - `[Interface]`：PrivateKey / Address（IPv4 + IPv6 合并）/ ListenPort / MTU / DNS / AmneziaWG 参数（键名首字母大写，按键名排序保证可 diff）
  - `[Peer]`：PublicKey / PresharedKey / AllowedIPs / Endpoint / PersistentKeepalive
  - IPv6 Endpoint 自动加方括号（`[2001:db8::1]:51821`）
  - 仅输出 wireguard 节点；无 wireguard 节点时明确报错（而非下载到空文件）
  - 已知有损项：`Reserved` 不是 wg-quick 标准键，导出时不写出（`reserved` 仍保留在 clash.meta / sing-box / URI 输出中）
  - 新增模块 `root/usr/share/substore/output_wireguard_conf.lua`
- 新增输出格式 **Clash 原版**（`target=clash`），面向 Dreamacro Clash / ClashX / Clash for Windows
  - 过滤原版不支持的协议（vless / hysteria2 / hysteria / tuic / wireguard），其余复用 Clash.Meta 的 YAML 生成
  - 采用排除法而非白名单，避免误丢原版其实支持的协议
- ⚠️ **行为变更**：`target=clash` 语义由「Clash.Meta」改为「Clash 原版」。原先使用 `?target=clash` 拉取 Clash.Meta 配置的用户请改用 `target=clashmeta`（或 `yaml` / `mihomo`）
- ⚠️ **行为变更（无感）**：未指定 `target` 时的默认格式显式固定为 `clashmeta`，与历史默认行为一致
- 输出层清理（`output.lua`）
  - 删除死代码 `to_clash_yaml` / `to_json` / `to_base64`（无任何调用点；且 `to_clash_yaml` 会把 `type:` 写成原始协议名，产出非法 YAML）
  - 删除随之失效的 `util` / `node` require
  - 新增 `M.FORMAT_OPTIONS` 作为格式清单的唯一数据源，`subscriptions.htm` 与 `output.htm` 两处硬编码 `<option>` 列表改为遍历生成，避免新增格式时漏改模板
  - 默认格式提取为 `DEFAULT_FORMAT` 常量，供 content-type / 扩展名 / 生成三处共用
- 新增测试 `tests/output_new_formats_test.lua`（66 项）：格式注册表一致性（每个 UI 选项都有别名、content-type、扩展名与分发分支）、Clash 原版协议过滤、`.conf` 结构与 AmneziaWG 键排序、IPv6 方括号、无 wireguard 报错、`.conf` 导出 → 重新导入的完整往返
- `tests/core_link_test.lua` 的目标格式列表改为从 `output.FORMAT_OPTIONS` 派生，新增格式自动纳入覆盖
- 版本号 2.3.0-r1 → 2.3.0-r2；README.md / README.en.md / docs/INSTALL.md 同步（输出格式 13 → 15 种）

## [2.3.0-r1] - wg-quick / AmneziaWG .conf 导入与导出修复

- 新增 wg-quick / AmneziaWG `.conf` 文本导入：解析 `[Interface]` / `[Peer]` 分段
  - `[Interface]`：PrivateKey / Address（自动区分 IPv4 与 IPv6）/ ListenPort / MTU / DNS
  - `[Peer]`：PublicKey / PresharedKey / AllowedIPs（拆分为数组）/ PersistentKeepalive / Endpoint（拆出 server + port，支持 `[v6]:port`）
  - AmneziaWG 参数（Jc/Jmin/Jmax/S1–S4/H1–H4/I1–I5/J1–J3/Itime）按白名单映射到 `amnezia-wg-option`，未知键丢弃（不猜语义）
  - 键名大小写不敏感，支持 `#` / `;` 注释；缺少 Endpoint 时明确报错而非产出半成品节点
  - 本地订阅文本导入与远程订阅下载同时生效（无需改 sync 流程）
- 修复 P1 引入的数组输出缺陷：clash.meta 的 `allowed-ips` / `reserved` / `dns` 值为数组时改用 YAML 列表输出，不再产生 `table: 0x...`
- 修复 sing-box `local_address`：同时有 IPv4/IPv6 时输出数组，不再逗号拼接（非法值）
- `amnezia-wg-option` 子块按键名排序输出，同一节点每次导出结果一致，便于 diff
- 修复 `parser_clash_yaml` 列表项误判：`- "::/0"` 等引号标量含冒号时不再被解析成 table
- 补全 sing-box / Clash JSON 导入：`local_address` 数组拆分、`persistent_keepalive_interval`、`listen_port`、`amnezia-wg-option`
- 新增 `listen-port` 字段贯通全链路（表单 / FORM_KEYS / clash.meta / sing-box / URI 输出）
- 新增测试 `tests/wireguard_conf_test.lua`（61 项）、`tests/amnezia_wg_test.lua`（67 项）
- 版本号 2.2.0-r5 → 2.3.0-r1；README.md / README.en.md / docs/INSTALL.md 同步

## [2.2.0-r5] - WireGuard 完整字段与 AmneziaWG 支持

- WireGuard 节点补全字段：public-key/pre-shared-key/ip/ipv6/allowed-ips/reserved/persistent-keepalive/mtu/dns/amnezia-wg-option
- Clash Meta 导出字段名修正为 public-key/pre-shared-key，补齐 ip/allowed-ips 等必填项，支持 amnezia-wg-option 子块全量输出
- sing-box 导出修正 pre_shared_key，补齐 local_address/reserved/persistent_keepalive_interval
- parser 补读 WireGuard 扩展字段，兼容旧名 peer-public-key/preshared-key
- core FORM_KEYS 补入 WireGuard 扩展字段，避免表单编辑后丢失
- nodeform.js PROTO_FIELDS.wireguard 扩充，表单显示完整字段
- local_form.htm / node_edit.htm FIELD_LABELS 补入 WireGuard 扩展字段标签
- parser_clash_yaml 补内联数组解析，支持 reserved/allowed-ips
- output_clash_meta esc_yaml 修复 find 平文匹配 bug
- 版本号 2.2.0-r4 → 2.2.0-r5；README/INSTALL 同步

## [2.2.0-r4] - 节点协议标签统一为 Type / 类型

- 节点列表页筛选标签与表头由 `Protocol / 协议` 统一改为 `Type / 类型`
- 节点编辑 / 本地订阅表单导入的协议选择标签由 `Protocol` 改为 `Type`，中文显示为“类型”
- `nodeform.js` 标签键由 `protocol` 改为 `type`，与下拉框 `data-k="type"` 一致
- `local_form.htm` / `node_edit.htm` 的 `FIELD_LABELS` 由 `"protocol": "<%:Protocol%>"` 改为 `"type": "<%:Type%>"`
- 版本号 2.2.0-r3 → 2.2.0-r4；README.md / README.en.md / docs/INSTALL.md 版本同步

## [2.2.0-r3] - 节点表单导入字段语言混合优化

- 「添加本地订阅」表单导入 /「编辑节点」页：名称 / 分组 / 协议保持系统语言（中/英切换），其余技术参数字段固定为英文（Server / Port / Password / Cipher / Method / Security / Network / Header Type / Path / Obfs / Obfs Param / Obfs Password / Protocol Param / Skip Cert Verify / Private Key / Peer Public Key），与 Clash YAML / 分享链接字段名保持一致，提升可对照性

## [2.2.0-r2] - 节点页按钮顺序调整

- 「节点」页「筛选」后的「刷新」「删除」按钮位置互换（现为：筛选 | 删除 | 刷新）

## [2.2.0-r1] - 节点页批量选择与操作

- 「节点」页关键词搜索框缩短为原长度的 3/5（`size` 默认 20 → 12）
- 节点表格最左新增复选框列：表头复选框全选 / 取消全选，行复选框单独勾选
- 「筛选」后新增「刷新」按钮（重载页面，筛选参数随 GET URL 自动保留）与「删除」按钮（勾选批量删除，confirm 确认，返回保留筛选参数）
- action_node_delete 的 idx 参数支持逗号分隔多值，倒序 table.remove 避免下标偏移；行内单删路径不变
- po/zh-cn 新增 Refresh / Delete selected nodes? / Please select nodes first 三条
- 版本号 2.1.3-r6 → 2.2.0-r1；README.md / README.en.md / docs/INSTALL.md 版本与功能描述同步

## [2.1.3-r6] - 节点分组与单节点编辑

- 表单导入节点行新增「分组」输入框（`data-k="group"`，parse_local 透传入模型）
- 节点页「关键词:」前新增「分组:」下拉筛选（选项为当前订阅节点的去重分组，精确匹配走 node.filter）；排序新增按分组
- 节点页「名称」后新增「分组」列：单元格内嵌输入框，onchange 经 XHR 提交 node_set_group 无刷新保存（成功绿闪/失败红闪提示）
- 节点页行尾新增「操作」列：编辑（新页面 node_edit.htm，复用协议动态字段，可改名称/分组/服务器/端口/协议全字段）与删除（confirm 确认，返回保留筛选参数）
- 单节点标识：渲染前标注原始数组下标 __idx（filter 保留表引用、sort 原地排序，下标穿透筛选排序）
- core.lua 新增 merge_form_node：表单字段整体替换（可清空），raw/tags 等非表单字段保留；删除/编辑后刷新引用该订阅的组合
- 动态字段 JS 抽取为 /luci-static/resources/substore/nodeform.js，local_form.htm 与 node_edit.htm 共用（翻译字典留模板内服务端渲染）
- 控制器新增 node_edit / node_save / node_delete / node_set_group 四路由
- 已知语义：单节点编辑/删除/分组在订阅下次「更新」或本地订阅重新保存后被覆盖（用户已确认接受）
- po/zh-cn 新增 分组/编辑节点/删除确认 等 6 条；tests/core_merge_node_test.lua 新增（17 断言）

## [2.1.3-r5] - 本地订阅表单全面接入系统语言

- local_form.htm 规则区硬编码中文（启用规则/关键词包含/关键词排除/去重/提示语）改为 `<%:...%>` 可翻译字符串，随 OpenWrt 系统语言自动切换中英文
- po/zh-cn 新增 Enable rules / Keyword include / Keyword exclude / Dedup 等 5 条
- 至此 local_form.htm 页面无任何硬编码中文（剩余中文均为代码注释）
- 说明：旧 form.htm（订阅链接表单）存在同样的硬编码中文存量问题，未在本次改动范围内

## [2.1.3-r4] - 表单导入枚举字段下拉化 + hysteria2 混淆闭环

- 表单导入枚举字段改为下拉框（选项以模型/输出模块实际支持的值为准，对齐 PassWall 式交互）
  - 传送方式 net：tcp/ws/h2/grpc；伪装类型 headerType：none/http（vmess/vless/trojan/shadowsocks 新增该字段）
  - vmess 加密方式 cipher：auto/aes-128-gcm/chacha20-poly1305/none/zero；新增 TLS 开关（修复表单无法生成 TLS vmess 节点的缺口）
  - vless 新增 flow（默认/xtls-rprx-vision）；security：none/tls/reality
  - shadowsocks 加密方式 method：常用 11 种枚举
  - hysteria2 新增混淆类型 obfs（无/salamander）+ 混淆密码 obfs-password
  - 下拉选项按协议区分（hysteria2.obfs），不影响 ssr 的 obfs 自由文本
- hysteria2 混淆导入导出闭环：output_uri 补 obfs/obfs-password 参数输出；output_clash_meta 补 obfs/obfs-password 行；output_singbox 补 obfs 对象；parser 的 hy2 URI 解析回读 obfs 参数
- po/zh-cn 新增 伪装类型 / 混淆密码 翻译
- tests/parser_local_form_test.lua 扩至 39 断言：hy2 混淆透传/URI 回环/双输出、vmess headerType/tls 透传

## [2.1.3-r3] - 表单导入字段中文化并扩充协议字段

- 表单导入动态字段标签支持简体中文（server/port/password/cipher/net/path/sni 等，po/zh-cn 新增 13 条）
- 扩充各协议字段集合，覆盖 Clash 风格节点常见字段：vmess/vless/trojan 新增 path、host、udp、skip-cert-verify；vmess 新增 alterId、cipher；ssr/shadowsocks/tuic/wireguard 新增 udp
- udp / skip-cert-verify 改为下拉框（默认/true/false），不再手填文本
- parser.lua `parse_local` 表单模式改为全字段透传 + 类型修正（port/alterId 转数字，udp/skip-cert-verify 字符串转布尔，network→net、method↔cipher、obfs-param/protocol-param 别名同步），不再因白名单丢字段

## [2.1.3-r2] - 修复本地订阅表单导入跳回列表

- 修复「添加本地订阅」页选择「表单导入」直接提交表单并跳回订阅列表的问题
  - local_form.htm：模式切换下拉框原为 `onchange="this.form.submit()"`，改为纯 JS 切换显示，不再提交
  - 移除重复的 hidden `local_mode` 字段；文本/表单两个 `content` 字段通过 disabled 互斥，保证只提交一个
  - 提交前（onsubmit）表单模式将节点序列化为 JSON 写入隐藏 content 字段
  - 编辑页初始内容由 `util.json_encode` 注入 JS（不再 pcdata 转义，避免破坏 JSON.parse）

## [2.1.3] - 新增本地订阅功能

- 新增本地订阅：支持文本导入与表单导入双模式，本地订阅不走网络更新，Update 按钮禁用
- 首页按钮调整：`添加订阅` → `添加订阅链接`，新增 `添加本地订阅`
- 数据模型扩展：`local`、`raw_content`、`local_mode` 字段，`core.add_local` / `parser.parse_local`
- 控制器新增 `localform` / `local_create` / `local_save` 路由
- 视图新增 `local_form.htm`，表单导入支持 vmess/vless/trojan/shadowsocks/ssr/hysteria2/tuic/wireguard 动态字段

## [2.1.2] - 完善协议列表

- 补齐节点列表和规则配置中缺失的协议选项
  - nodes.htm：补齐 ssr、hysteria、wireguard、socks 四个协议
  - substore.lua：补齐 ssr、hysteria、wireguard、socks 四个协议

## [2.1.1] - 修复延迟显示 Bug

- 修复「节点」页面延迟列显示异常问题
  - 修正 innerHTML 与 textContent 的差异，确保失败时正确显示红色 "Fail" 文本
  - 之前版本中由于使用 textContent，HTML 标签被显示为纯文本

## [2.1.0] - 网络探测优化

- 优化「节点」页面的网络探测（Ping/TCPing/URL Test）显示
  - 在节点列表表格中新增「延迟」列，直接显示每个节点的测速结果
  - 移除独立的探测结果弹窗，结果直接展示在表格内，查看更加直观
  - 使用 data 属性进行节点匹配，提高稳定性

## [2.0.0] - 组合订阅

- 新增「组合订阅」（选择性合并多个订阅 + 组合订阅链接）
  - core.lua：新增 add_combo / save_combo / combo_nodes / combo_refresh / refresh_combos / is_combo；
    组合订阅物化为自身节点文件，无 URL、无 cron/代理，可叠加关键词包含/排除与去重规则；
    sync 遇组合走重算而非下载，源订阅更新后自动 refresh_combos 重算依赖它的组合
  - controller：新增 combo / combo_save 路由与 action_combo_save（复用 read_rules_fields）
  - view：新增 combo.htm（名称 + 来源复选框 + 规则显隐）；subscriptions.htm 增「添加组合订阅」
    按钮、组合行徽标与来源显示、编辑路由区分
  - Makefile：安装 combo.htm；版本号 1.0.0 → 2.0.0（2.0.0-r1）
  - i18n：po/zh-cn 新增 添加/编辑组合订阅、组合、来源订阅
  - tests/core_combo_test.lua 新增（23 断言）

## [1.0.0] - 正式版

- 修复 Clash 订阅（机场常见「流式 JSON 节点」写法）解析为 0 节点的问题
  - 部分机场生成的 Clash/Mihomo 配置把每个代理节点写成单行流式 JSON：`- {"name":"…","type":"vmess","server":"…","port":443,…}`（含嵌套 `ws-opts`），而非缩进块风格；原解析器只认块风格，导致 `name`/`server`/`port` 全部读空、节点被丢弃
  - parser_clash_yaml.lua `read_list`：识别 `- {…}` 流式 JSON 对象并 `util.json_decode` 解析
  - parser_clash_yaml.lua `map_clash_node`：把 Clash 的 `ws-opts.path` / `ws-opts.headers.Host` 映射到统一模型的 `path` / `host`（此前 ws 节点丢失 path）
  - tests/parser_clash_yaml_test.lua 新增流式 JSON 节点用例（vmess ws + ssr，含 path/host 映射，+14 断言）
- 修复 Shadowrocket 订阅（base64url / BOM）无法解析、内部 vmess 节点读不出的问题
  - parser.lua `detect`：base64 检测接受 URL-safe base64url（`-` `_` 无 padding）与 UTF-8 BOM 前缀；
    对「纯字母数字且长度非 4 倍数」的去 padding base64url，尝试解码并校验是否含 vmess/vless/trojan/ss/ssr 节点再判定
  - parser.lua `parse` / `parse_vmess`：改用 `util.base64_url_decode`（兼容标准 base64 与 base64url）
  - tests/run_tests.lua 增补 base64url / BOM 订阅检测与解析用例（+4 断言）
- 补齐协议能力矩阵的四项缺口（hysteria2 / tuic / wireguard 全链路导入导出 + JSON 配置导入放开 + Surge 家族输出）
  - parser.lua：SUPPORTED 增加 hysteria2 / tuic / wireguard；新增 parse_hysteria2 / parse_tuic /
    parse_wireguard（wireguard 采用本项目自定义 scheme `wireguard://base64(json)#name`，因 wireguard 无统一 URI 标准）
  - parser_json_config.lua：proto_map / SUPPORTED 从 4 协议扩到 11（补 hysteria/hysteria2/tuic/wireguard/
    socks/http/ssr）；sing-box 解析补 hysteria2/tuic/wireguard/socks/http 分支，V2Ray 解析补 socks/http 分支，
    Clash 解析补 hysteria2/tuic/wireguard/socks/http/ssr 分支（ssr 读 cipher/protocol/obfs/obfs-param/protocol-param）
  - output_uri.lua：新增 wireguard 输出（`wireguard://base64(json)#name`），与 parser 回环一致
  - output_formats.lua：Surge 家族新增 tuic 行（username=uuid/password/sni/alpn）；surge_config 统一丢弃
    wireguard（Surge 需专用多段 [WireGuard] 配置，单行无法表达），ssr 仅 Loon/Egern 保留
  - output_singbox.lua：wireguard 输出读取 kebab-case 字段（private-key/peer-public-key/preshared-key，
    snake 回退），导入后经此输出字段不再丢失
  - node.lua：PROTOS 已含 hysteria2/tuic/wireguard，无改动
  - tests/protocol_support_test.lua 新增（58 断言）：hy2/tuic/wireguard URI 导入、base64 订阅、
    sing-box/Clash JSON 导入、Surge tuic 输出 + wireguard 丢弃、sing-box wireguard kebab 输出
- 新增 SSR（ShadowsocksR）订阅源支持
  - parser.lua：SUPPORTED 增加 ssr；新增 parse_ssr 解析 ssr:// 分享链接（外层 base64、
    密码/参数 base64url 兼容标准 base64，remarks/obfsparam/protoparam/group）
  - util.lua：新增 base64_url_encode / base64_url_decode（RFC 4648 base64url）
  - node.lua：PROTOS 注册 ssr
  - output_clash_meta.lua：ssr 输出完整字段（cipher/password/protocol/obfs/obfs-param/protocol-param）
  - output_uri.lua：新增 to_ssr_uri 生成 ssr:// 分享链接（Shadowrocket / V2Ray URI 输出）
  - output_formats.lua：Loon / Egern 输出 SSR 行；Surge/Surfboard/SurgeMac 跳过 ssr（不支持）
  - output_singbox.lua / output_v2ray.lua：跳过 ssr（不支持 SSR，丢弃而非输出非法配置）
  - SSR 仅能原样输出到支持它的客户端，不能与 vmess/vless 等其它协议互转（协议不兼容）
  - view/form.htm：「订阅 URL」输入框宽度与「代理地址」对齐（70% → 60%）
  - tests/ssr_test.lua 新增（41 断言）
- 编辑订阅页新增「订阅代理」：开启后通过代理地址下载订阅（解决国内直连失败）
  - http.lua：新增 parse_proxy（http/https/socks4/socks5/socks5h，含 user:pass@，防注入）；download/curl/wget 支持代理
  - core.lua：订阅元数据新增 proxy_enable/proxy；sync() 开启且地址有效时经代理下载
  - controller：create/save 读取并持久化 proxy_enable/proxy
  - view/form.htm：订阅 URL 下方新增「订阅代理」复选框，开启时显示「代理地址」输入框（默认关闭）
  - tests/http_proxy_test.lua 新增
- 编辑订阅页展示剩余流量 / 剩余时长（仅编辑页，首页不显示）
  - http.lua：下载时捕获响应头，download() 返回值改为 body, headers, err；新增 read_headers
  - core.lua：新增 parse_userinfo；sync() 解析 subscription-userinfo 头并持久化 upload/download/total/expire
  - util.lua：新增 human_bytes / human_duration
  - view/form.htm：统计行新增「剩余流量 / 剩余时长」
  - po/zh-cn：新增 Remaining traffic / Remaining time 翻译
  - tests/core_userinfo_test.lua 新增
- 简体中文 i18n（运行时语言 zh-cn 时自动显示中文，英文时保持英文；24.10 / 25.12 实机均已验证）
  - po/zh-cn/substore.po 新增（菜单/按钮/列头/探测结果等全部 UI 字符串）
  - Makefile: install 步骤用 po2lmo 编译为 substore.zh-cn.lmo 并打包到 /usr/lib/lua/luci/i18n/
- Nodes 页新增节点网络探测（Ping / TCPing / URL 测试）
  - probe.lua 新增：Ping（ICMP 解析 time=）、TCPing（nc -z 测连接耗时）、URL 测试（curl time_total / wget uptime 差值）；并行探测，总耗时≈单节点超时；主机名/IP 白名单校验防命令注入
  - controller: action_probe 端点（POST id/mode/proto/keyword，返回 JSON），按当前 proto/keyword 过滤后逐个探测
  - view/nodes.htm: 筛选按钮后新增三按钮 + 结果表格（延迟/失败 + 成功数与平均延迟）；Desc 复选框与下拉框间距、复选框与文字间距修正
  - tests/probe_test.lua 新增（18 断言）
- 规则编辑页简化与对齐（form.htm）
  - 「定时更新时间」与「关键词包含/排除」改为与其它行一致的 cbi-section-descr + min-width:10em 标签，左对齐；cron_time_row 由 display:flex 改为 block + inline-flex
  - 移除「协议过滤」「重命名规则」字段；底部新增多关键词备注
  - node.lua: 关键词包含/排除支持逗号（含中文逗号）/空白分隔的多关键词，命中任一即保留/去除
  - tests/core_rules_test.lua 增补多关键词用例（14 断言）
- 规则下沉到订阅（per-subscription），更新订阅时直接生效；移除全局「设置」页
  - core.lua: 订阅元数据新增 rules_enable / proto_filter / keyword_include / keyword_exclude / dedup / rename_map；新增纯函数 apply_rules()；sync() 解析后按订阅规则过滤/去重/重命名再落盘；移除 load_rules()（不再依赖 luci.model.uci）
  - controller: read_rules_fields()；create/save 读取并持久化规则；移除 settings/settings_save 路由与 action_settings_save
  - view/form.htm: 新增「启用规则」复选框 + 规则字段（协议过滤/关键词包含/排除/去重/重命名），随复选框显隐
  - 删除 view/settings.htm、menu.d 的 Settings 条目、UCI config rules 'default'；uci-defaults 清理旧 substore.default
  - tests/core_rules_test.lua 新增（11 断言）
- Stage 4: 定时更新、规则、错误处理、安全加固、多版本兼容
  - substore-cron.sh: 重写为独立 cron 可运行（显式 package.path、自动探测 lua5.1/lua、pcall 保护、输出走 logger）
  - node.lua: 重命名规则统一三种形式——精确 `旧=新`、正则 `pattern -> replacement`、模板 `{server}_{port}_{proto}`（parse_rename_rules / rename_with_rules / apply_rules）
  - view/settings.htm: 重命名规则 hint、协议过滤/关键词/去重规则配置
  - controller: action_update 用 pcall 兜底，解析/写入异常不 500，错误落库并在列表页状态列展示
  - controller: action_download 文件名白名单化，防 HTTP 头注入
  - Makefile: LUCI_DEPENDS 显式 +luci-lua-runtime +luci-compat（23.05/24.10 兼容）
  - docs/UCODE_MIGRATION.md: `.htm` → `.ut`（ucode）迁移评估与对照（未执行，需 25.12 构建环境验证）
  - tests: node_rename_test.lua 增补精确匹配重命名用例（27 断言）
- Stage 3: 订阅转换 + 订阅链接（核心功能）
  - output.lua: 统一分发全部 13 种目标格式（FORMAT_ALIASES 别名映射）
  - output_uri.lua: vmess/vless/trojan/ss/hysteria2/tuic/socks 分享链接、Shadowrocket(base64)/V2Ray URI
  - output_singbox.lua: sing-box JSON outbounds
  - output_v2ray.lua: V2Ray/Xray JSON outbounds
  - output_formats.lua: Surge/Surfboard/SurgeMac/Loon/Egern/QX/Stash/Plain JSON
  - core.lua: 每订阅随机 token、generate_link(token, target)
  - controller: 公开下载端点 /substore/download?token=&target= （token 访问控制）
  - view: output.htm 13 格式下拉、subscriptions.htm 展示可复制的订阅链接
  - Makefile: 通配安装新增 .lua 模块
  - tests: output_formats_test.lua、core_link_test.lua
- Stage 1: subscription CRUD + download/parse core
  - util.lua: JSON/Base64/URL/file helpers, atomic_write
  - node.lua: protocol normalize
  - parser.lua: vmess/vless/trojan/ss URI parse
  - http.lua: curl/wget download with SSRF check
  - core.lua: subscription meta/nodes persistence, sync()
  - LuCI: subscriptions list & form, controller actions
  - tests/run_tests.lua added
- Stage 0 skeleton: package scaffolding, LuCI menu placeholder, docs.

## [0.1.0] - not yet released

- Initial package skeleton (in development).