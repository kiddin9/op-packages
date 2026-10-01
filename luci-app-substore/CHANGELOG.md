# Changelog — luci-app-substore

All notable changes to this project will be documented in this file.

## [2.6.8-r1] - P2 批次六：网络安全与健壮性（L10 / L11 / L12 / L14）

P2 批次六，四项都围绕「**检查的强度不能低于被检查者**」这条线：
前两项让校验真正拦得住，后两项让失败路径不再留下副作用。

### L10 DNS 解析失败改为 fail-closed（`http.lua`）

`M.check_public` 在 `resolve()` 返回 nil 时**放行**，理由写的是「无 DNS 解析能力时
尽力而为」。那是一个 SSRF 绕过口：

- 检查侧：`resolve()` 返回 nil → 跳过全部私网判定 → 放行
- 实际连接侧：curl 自己做解析，`127.0.0.1.nip.io` 这类**公网可解析到内网**的域名
  会被它解析到 `127.0.0.1` 并连上去

只要本机这一刻解析不出来（nixio 缺失、解析器临时故障、超时），两者就分叉。
检查的强度不能低于被检查者，现在解析失败一律拒绝。

代价为零：本包依赖 `luci-lua-runtime`，后者在 Makefile 里硬依赖 `+luci-lib-nixio`
（已核对上游），所以 `resolve()` 返回 nil 只意味着「真的解析不了」——
那种情况下 curl 同样解析不了，下载本来就会失败，只是错误信息会从「连接失败」
变成「无法解析目标主机名」，反而指对了方向。

### L11 `parse_url` 补端口范围校验（`http.lua`）

`hostport:match("^([^:]+):(%d+)$")` 只保证端口是数字，`http://host:99999/` 与
`http://host:0/` 都能通过。这两个端口连不出去，下载必然失败，却会先经过一轮
DNS/SSRF 检查，最终报出「连接失败」这种指错方向的原因。`parse_proxy` 早已做了
同样的 1–65535 校验，这里对齐。

IPv6 字面量分支（`[::1]:port`）走的是另一条赋值路径，同样纳入校验。

### L12 探测目标拒绝以 `-` 开头的主机名（`probe.lua`）

命令形如 `ping -c 1 -W 2 <host>`，`host` 若为 `--help` / `-c`，会被 busybox 的
**getopt 当成选项**而不是参数。`util.shq` 的单引号由 shell 剥掉，getopt 看到的
仍然是 `-x` —— 引号挡不住这一层。

合法主机名（RFC 1123 要求首字符为字母或数字）与 IP 都不会以 `-` 开头，所以直接拒绝。
`ping` / `tcping` / `url_test` / 批量 `probe` 四条路径共用 `safe_host`，一处收口。

### L14 下载临时文件在每一条退出路径上清理（`http.lua`）

`fetch_curl` 此前只在「本轮开始」和「2xx 成功」两处 `os.remove`，其余失败路径
（curl 报错、超过大小限制、重定向无 Location、重定向目标无效/不安全、
HTTP 4xx-5xx、重定向次数过多）都把 `/tmp/substore_dl_*.tmp{,.hdr,.err}` 留在原地。

OpenWrt 的 `/tmp` 是 tmpfs —— 占的是内存。订阅更新失败后 cron 会定时重试，
于是一轮轮往内存里堆文件，其中 `.tmp` 可能是部分下载的响应体，最大到 `max-size`。

现在收敛成一个 `cleanup()` 闭包，在**每一条** `return` 之前调用。

### 测试

- 新增 `tests/network_security_test.lua`（38 条断言）：L10 的 fail-closed 与
  「公网字面量仍放行」对照；L11 的 `:0` / `:65536` / `:99999` 拒绝与
  `:1` / `:65535` / 默认端口接受（含 IPv6 分支）；L12 用 `io.popen` 替身断言
  「以 `-` 开头的主机名**一个子进程都不启动**」，并用合法主机名反向确认替身有效；
  L14 用模拟 curl 写盘的替身，逐条验证三条失败路径后 `/tmp` 无残留
- 全部用例不触网
- `tests/http_proxy_test.lua` 的重定向链用例改用**公网 IP 字面量**而非
  `cdn.example.com`：`check_public` 现在解析失败即拒绝，用域名会让
  「公网目标应放行」变成「取决于本机有没有 DNS」，测试不可复现
- 反向验证：新断言在修复前的 `HEAD` 上 **19 条失败**（L10×2 / L11×4 / L12×4 / L14×9），
  在修复后全部通过

## [2.6.7-r1] - P2 批次五：控制器健壮性（L3 / L4）

P2 批次五，修控制器的两项缺陷：一类是**未登录可达的 500**，一类是
**点了按钮却什么都没发生**。两者都属于「静默」——不报错、看起来正常。

### L3 重复表单字段让 `formvalue` 返回 table，直接崩在 `:gsub` 上

- LuCI 的 `formvalue` **不保证返回字符串**。依据上游 `luci/http.lua` 的
  `urldecode_message_body`：

  ```lua
  elseif what == parser.VALUE and name then
      local val = msg.params[name]
      if type(val) == "table" then val[#val+1] = ...
      elseif val ~= nil then msg.params[name] = { val, ... }   -- ← 第二次出现变成 table
  ```

  而 `formvalue` 原样返回 `msg.params[name]`；上游 luadoc 也写着
  `@return HTTP input value or table of all input value`。
- 控制器有 ~30 处直接对返回值做 `:gsub` / `util.trim` / `urlencode`，
  遇到 table 会抛 `attempt to call method 'gsub'` → **HTTP 500**。
  实测复现：`action_create` / `action_save` / `action_local_create` /
  `action_local_save` / `action_combo_save` / `action_node_set_group` /
  `action_probe` / `action_download` 共 8 个 action 崩溃。
- **攻击面不限于已登录用户**：`/substore/download` 是无需登录的入口
  （供 Passwall / OpenClash 拉取），对它 POST 一个重复的 `token` 字段即可触发。
- 现新增 `fv(http, key)` 统一取值：table 取最后一个（与「同名参数后者覆盖
  前者」一致），`nil` 保持 `nil`（`post_ok` 依赖它区分「无 token」与
  「空 token」）。全部调用点收敛到这一处。
- **更正审计表的表述**：触发条件是 **POST 重复字段**，不是 GET。GET 查询串
  走的是 `urldecode_params`，它只做 `params[name] = ...` 覆盖、**不建表**。
- 顺带清理：`action_node_delete` 里 `if type(idx_param) == "table"` 的兜底
  在 `fv` 之后已成为死代码，移除。

### L4 `combo_save` / `delete` / `update` / `node_delete` 静默失败

违反项目 §18（失败必须让用户看见，不能「失败了却看起来像成功」）：

- `action_delete`：`core.remove` 的返回值被整个丢弃。非法 ID / 订阅不存在时
  返回 `false`，页面照常跳回列表 —— 用户点了删除，订阅还在。
- `action_combo_save`：名称留空、或一个来源都没勾选时整段跳过直接跳回列表；
  `add_combo` / `save_combo` 的返回值同样被丢弃（非法 ID、未选来源、写入失败
  一律静默）。
- `action_update`：订阅不存在（ID 拼错 / 已被删除）时静默跳回列表。
- `action_node_delete`：下标解析不出数字、或下标全部越界时静默跳回列表；
  `write_nodes` 失败也不提示。
- 现四处全部补上原因回显。

### 测试

- 新增 `tests/controller_robustness_test.lua`，27 项断言：
  - 12 个 action 逐个在「所有字段都重复提交」下调用，断言**不抛错**；
  - 重复字段取值语义（取最后一个）；
  - L4 四处的失败回显 + 成功路径不带 `err` 的守卫。
- **反向验证**：指向 `HEAD` 版控制器重跑，**27 项中 18 项失败**，
  崩溃点正是审计表标注的行（`substore.lua:90/118/146/170/321` 与
  `util.lua:9`），确认测试覆盖的是真实缺陷而非恒真。
- 全量回归：41 个 Lua 测试文件（1809 项断言）+ `cron_result_test.sh`(14)
  全部通过。
- 版本号 2.6.6-r1 → 2.6.7-r1。

## [2.6.6-r1] - P2 批次四：核心数据层（代理解析 / 去重 / cron 退出码 / 规则字段）

P2 批次四，修四项缺陷（审计表 M16 / M17 / M18 / M30）。前三项在数据通路上，
症状都是「静默失效」——不报错、看起来正常，但结果不对或故障无人知晓；
M30 则是「字段读得到、界面写不了」的静默数据丢失。

### M16 未加方括号的 IPv6 代理地址被拼成非法代理串

- `M.parse_proxy` 用 `^([^:]+):(%d+)$` 拆 host:port。IPv6 字面量里全是冒号，
  这个模式必然失配，于是整个 `::1:1080` 落进「无端口」分支当作**主机名**，
  再原样拼回去得到 `http://::1:1080` —— 冒号歧义，`curl -x` 与 `http_proxy=`
  都解析不了（curl 会把 `::1:1080` 整个当主机名），**代理静默失效**。
  更糟的是走 `[::1]:1080` 这条正确写法时，为做主机校验把方括号拆掉后
  **没有拼回去**，同样得到 `http://::1:1080`。
- 现分三处修正：① 记录是否带方括号；② 未加方括号却含多个冒号时**明确报错**
  并给出正确写法（`::1:1080` 到底是「地址 ::1 + 端口 1080」还是地址
  `::1:1080`，语法上无法判定 —— 与其猜一个再拼一条解析不了的串，不如让用户
  补方括号）；③ 拼回代理串时，主机含冒号就补上方括号。

### M17 去重键不含凭据，同入口的多账号被误删

- `M.dedup` 此前只按 `proto|server|port` 去重。同一台服务器上的**多账号**是
  极常见的形态（同一入口不同 uuid / 不同密码），这些节点会被判为重复而
  只剩第一个 —— 用户看到节点数莫名变少，且**丢的是哪个不可预期**。
- 现抽出 `identity_key()`，按协议取各自的凭据参与去重键：
  vmess/vless → uuid；shadowsocks → method+password；ssr → method+password+
  protocol+obfs；trojan/hysteria/hysteria2 → password；tuic → uuid+password；
  socks/http → username+password；wireguard → peer 公钥（沿用原有逻辑）。
  凭据完全相同的节点仍然照常去重。

### M18 cron 脚本把「Lua 根本没跑完」当成成功

- `substore-cron.sh` 的退出码判定是 `''|0) exit 0`。结果行**缺失**被和
  「0 个失败」归为一类 —— 而结果行缺失的真实含义是 Lua 没跑到最后：
  模块加载失败、`core.list()` 抛异常（它在 `pcall` 之外）、解释器中途死掉。
  于是一次彻底失败的订阅更新在 cron 与外部监控看来**与成功无异**，
  故障永远不会被发现。
- 现把空结果行单列：写 stderr 诊断并 `exit 1`。

### M30 「协议筛选 / 重命名」字段读得到、界面写不了

- 控制器 `read_rules_fields` 一直在读 `proto_filter_*` 与 `rename_map`，
  但三个表单（form.htm / local_form.htm / combo.htm）**都没有提交它们的控件**。
  后果有两层：① 功能不可达，用户永远设不了这两项；② 更严重的是
  **静默数据丢失** —— 控制器每次把 `formvalue` 的 `nil` 落成 `""`，
  于是通过 UCI 手工设过的值在下一次保存时被抹掉。
- 现三个表单补齐控件（协议勾选框 + 重命名文本域），并把协议清单收敛到
  `core.RULE_PROTOS` 单一来源，由控制器与三个模板共用：两边各写一份的话，
  一旦漂移，勾选框就会生成一个永远匹配不到任何节点的 `proto_filter`，
  而症状是「勾了没用」——不报错，最难查。清单用的是 `node.normalize` 产出的
  **规范**协议名（`socks5` 在解析阶段已归一成 `socks`，故不在清单内）。
  已有值在编辑页回填，避免「打开编辑页看不到当前设置，一保存就被覆盖」。

### 测试

- 新增 `tests/rules_fields_test.lua`，42 项断言：`RULE_PROTOS` 的形态 /
  唯一性 / 规范性，三个模板与控制器的静态检查，以及「控制器收集逻辑产出的
  CSV 真的能被 `node.apply_rules` 用来筛选、`rename_map` 真的生效」的行为检查。
  **反向验证**：指向 `HEAD` 版模板与控制器重跑，**17 项失败**。
- `tests/node_extended_test.lua` 扩充 dedup 段（6 项新断言）。原有用例
  「两个 uuid 不同的 vmess 应合并成 1 个」正是 M17 要修的**错误行为**，
  已改为断言修复后的正确结果。
  **反向验证**：指向 `HEAD` 版 `node.lua` 重跑，**6 项失败**。
- `tests/cron_result_test.sh` 增加两项用例（`core.list()` 抛异常、
  模块加载失败），共 14 项。**反向验证**：指向 `HEAD` 版脚本重跑，**3 项失败**。
- `tests/controller_local_test.lua` 的 `substore.core` stub 补上 `RULE_PROTOS`
  （控制器现在会遍历它）。
- 全量回归：40 个 Lua 测试文件（1782 项断言）+ `cron_result_test.sh`(14)
  全部通过。
- 版本号 2.6.5-r1 → 2.6.6-r1。

## [2.6.5-r1] - P2 批次三：输出层合法性（配置能否被目标客户端加载）

P2 批次三，修输出层七项缺陷（审计表 M19 / M23 / M24 / M25 / M27 / L21 / L22）。
共同判据只有一条：**生成的文件/链接必须能被目标客户端真正加载**，
而不是「看起来像那么回事」。

### M23 wireguard 数组字段以字符串形态原样透传

- 节点模型里 `allowed-ips` / `reserved` / `dns` 的形态取决于来源：Clash YAML 的
  嵌套列表解析后是 table，表单导入 / URI 导入 / `.conf` 导入后是
  `"0.0.0.0/0, ::/0"` 这样的**字符串**。输出层此前不看类型直接透传，于是
  sing-box 出 `"allowed_ips":"0.0.0.0/0"`、`"reserved":"1,2,3"`，
  clash-meta 出 `allowed-ips: 0.0.0.0/0` 这个**标量**。
- 而 mihomo 的 `allowed-ips` / `dns` 是 `[]string`、`reserved` 是 `[]uint8`，
  sing-box 同名字段亦然 —— 标量反序列化失败，**整份配置拒绝加载**。
- 现统一归一为列表：clash-meta 的 `yaml_value` 改为「数组或逗号分隔字符串 →
  YAML 列表」；sing-box 的 `allowed_ips` / `dns` 走 `as_list`，
  `reserved` 走 `as_num_list`（sing-box 要求 `[1,2,3]` 数字，字符串数组同样失败）。
  空值不输出该键（`allowed-ips: []` 也是非法值）。

### M27 未加引号的 YAML 标量里反斜杠被静默翻倍

- `esc_yaml` 先无条件执行 `gsub("\\", "\\\\")` 再判断是否需要引号。而反斜杠
  **不在** `need_quote` 的触发集里，所以 `pa\ss` 走的是「不加引号」这条路：
  输出 `password: pa\ss` 的字面文本是 `pa\\ss`，YAML 按 plain scalar 回读
  得到**两个反斜杠** —— 密码 / 路径直接错。
- 现把转义链移进 `if need_quote` 分支：未加引号时反斜杠就是字面反斜杠，
  加引号时才需要转义。`pa\ss` → `pa\ss`；`pa\ss: x`（含 `:`，需引号）
  → `"pa\\ss: x"`。

### M24 hysteria2/hysteria 分享链接丢掉「跳过证书校验」

- 该分支只读 `n.insecure`。但按 `parser.lua` 自身的注释，模型里的**权威字段是
  `skip-cert-verify`**（sing-box JSON 的 `tls.insecure` 也映射到它），
  而 `insecure` 只是 URI 参数名、**只有 URI 解析器会写它**。
- 于是 Clash YAML / sing-box JSON / 表单导入的节点在导出分享链接时，
  「跳过证书校验」被整个丢掉，客户端按严格校验握手直接失败。
- 现按 `skip-cert-verify` → `skip_cert_verify` → `insecure` 的优先级读取，
  统一归一为 `insecure=1` / `insecure=0`（falsy 判定与 `output_singbox.lua`
  的 `bool()` 一致：`false` / `"false"` / `0` / `"0"` 视为否）。

### M25 trojan/tuic 分享链接的 alpn 数组未归一

- 这两个分支把 `n.alpn` 直接交给 `url_encode`，而 `url_encode` 会
  `tostring()` —— alpn 为 table 时（Clash YAML 的 alpn 列表、sing-box JSON 的
  `tls.alpn` 导入后都是 table）链接里出现 `alpn=table%3A%200x...`，
  客户端解析失败。vless 分支早已做了归一，这两处漏了。
- 现抽出 `alpn_str()` 统一处理，三处共用。

### L21 成员列表里含逗号的名字被当成两个成员

- Surge 家族 `[Proxy Group]` 与 QX `[policy]` 的成员列表是
  `NAME = select, X, Y, DIRECT`，语法里**没有引号 / 转义机制**。名字里的逗号
  会被当成成员分隔符：`A,B` 被读成两个成员 `A` 与 `B`，两个都不存在 ——
  Surge / QX 会因「引用不存在的代理」**拒绝加载整份配置**。
- 现 `names_of()` 排除含逗号的名字（节点定义仍留在 `[Proxy]` / `[server_local]`
  中，只是不进成员列表），并统一先过 `util.one_line()`：定义行本就经过
  `one_line`（换行→空格），成员列表若用原始名就对不上定义行，同样是悬空引用。

### M19 QX `[policy]` 引用未定义的服务器

- QX 的 `[server_local]` 只输出 shadowsocks / vmess / vless / trojan 四类协议，
  而 `[policy]` 用**未过滤**的 `names_of(nodes)` 收集全部节点名 ——
  hysteria2 / tuic / socks / wireguard 等没有定义行，列进 `static=` 就是
  **悬空引用**。
- 现按「真正写出了 `[server_local]` 行的节点」收集成员。

### L22 非数字 port 原样输出

- `port: abc` / `port: 443/tcp` 这类非数字值会让 mihomo 拒绝加载整份配置。
  sing-box / v2ray 输出一直用 `tonumber() or 0` 兜底，clash-meta 漏了。
  现对齐。

### 已核实无需修改

- **M26**（hysteria/hysteria2/tuic 缺 `security` 时不输出 TLS）已在 P0 批次四
  修复（`fb51e6e` 为三者补了 `node.normalize` 的 `security` 默认值），
  经探针复核：raw 节点经 `normalize` 后 sing-box / clash 均正确输出 TLS。

### 测试

- 新增 `tests/output_legal_test.lua`，39 项断言，覆盖上述七项，
  并对「本就正确的行为」加了守卫（数组形态不被破坏、字符串 alpn 不受影响、
  数字端口不被改写、无 `insecure` 时不输出该参数）。
- **反向验证**：把测试指向 `HEAD` 版输出模块重跑，39 项中 **28 项失败**，
  确认它们覆盖了缺陷而非恒真；其余 11 项是行为守卫，本就应当通过。
- 全量回归：41 个 Lua 测试文件（1786 项断言）+ `cron_result_test.sh`(11) 全部通过。
- 版本号 2.6.4-r1 → 2.6.5-r1。

## [2.6.4-r1] - P2 批次二：wg-quick 导入健壮性与 IPv6 内网判定

P2 批次二，修 `parser.lua` 的五项缺陷（审计表 M9 / L20 / L16 / L17 / L18）。
每项均先复现、后修改，并新增回归测试。

### M9 wg-quick `.conf` 一个坏 `[Peer]` 废掉整份文件

- **首个失败对端即中止**：`if not host … then return nil, … end` 位于
  `for _, p in ipairs(peers)` **循环体内**，于是第一个缺 `Endpoint`（或
  `Endpoint` 解析不出端口）的 `[Peer]` 会让整份 `.conf` 返回 `nil`，
  同文件里其它完好的对端全部丢失。现在只跳过该对端；若一个可用对端都没有
  （`#peers > 0` 已保证走不到「没有 [Peer]」分支），返回错误而**不是空列表** ——
  空列表会被上层当成「解析成功但 0 节点」的静默失败。
- **不剥行内注释**：行扫描只跳**整行** `#` / `;` 注释，而 wg-quick 的
  `parse_options` 用 `stripped="${line%%\#*}"`，即从**第一个** `#` 起全部丢弃
  （不要求 `#` 前有空白）。于是 `Endpoint = 1.2.3.4:51820 # 备用` 会把
  `# 备用` 当成值的一部分，`split_hostport` 取不到端口，同样整份作废。
  现对齐 wg-quick 语义做行内剥离；`;` 按上游行为**不**作注释符，
  仅保留本实现原有的整行容忍。

### L20 多 `[Peer]` 时数组字段被所有节点共享

- `for k, v in pairs(common) do out[k] = v end` 是浅拷贝，而 `common.dns`
  （多值时为数组）与 `common.reserved`（恒为数组）是 **table**，于是所有生成的
  节点指向**同一个表** —— 按节点编辑 DNS 会同时改到全部节点。紧邻的
  `amnezia-wg-option` 子块本就做了副本（注释还专门说明了这个隐患），这两个漏了。
  现统一走一层表拷贝。

### L16 `parse_local_link` 丢掉 query 与 userinfo

- **无路径时 query 全丢**：authority 用 `^([^/]*)` 切分，`?` 不在排除集内，
  于是 `http://host:port?target=ClashMeta&name=Foo` 的 authority 变成
  `host:port?target=ClashMeta&name=Foo` —— `host` 被污染，`target` / `name` /
  `uid` 全部丢失。现改为 `^([^/?]*)`。
- **不剥 userinfo**：`detect_local_link` 一直会剥 `user@`，此处漏了。
  现同样剥离（按**最后一个** `@`，与 M10 的约定一致）。

### L17 `is_private_host` 的 IPv6 判定可被等价写法绕过

- 旧实现拿字符串比前缀（`^::` / `^f[cd]` / `^fe[89ab]`）并只对 `^0*` 做一次
  去零，于是 `[0::1]`、`[0000::1]`、`[0:0:0:0:0:0:0:1]`（同一个回环地址的
  不同写法）**全部被判成公网**，而 `[::ffff:8.8.8.8]` 反被判成内网。
  现先把 IPv6 字面量**展开成 8 组 16 位数值**（含 `::` 压缩、zone id、
  嵌入式 IPv4 写法）再判定：`::` / `::1`、IPv4 映射地址按 IPv4 规则递归判定、
  ULA `fc00::/7`、链路本地 `fe80::/10`。该函数目前未被生产代码接线
  （仅 `detect_local_link` 调用，而后者只被测试引用），属**潜在** SSRF 缺口，
  非当前可利用路径。

### L18 纯空白 / 只有 BOM 的内容报「无法识别的订阅格式」

- `M.detect` 会 trim 并去 BOM 后判为 `empty`，而 `M.parse` 只挡住了完全空串
  （`content == ""`），`format == "empty"` 不匹配任何分支，于是掉到末尾报
  「无法识别的订阅格式」。内容确实是空的，不是格式不认识 —— 提示误导。
  现返回与空串一致的 `{ nodes = {}, format = "empty" }`。

### 测试

- `tests/wireguard_conf_test.lua` 新增 23 项断言（行内注释、坏 `[Peer]` 跳过、
  全部对端不可用报错、多对端数组字段不共享）。
- `tests/parser_local_link_test.lua` 新增 28 项断言（无路径 query、userinfo、
  IPv6 内网判定的 16 种写法与 4 种公网反例、空白 / BOM 内容）。
- **反向验证**：把两个测试文件指向 `HEAD` 版 `parser.lua` 重跑，
  新增断言分别失败 16 项 / 13 项，确认它们确实覆盖了缺陷而非恒真。
- 全量回归：40 个 Lua 测试文件（1747 项断言）+ `cron_result_test.sh`(11) 全部通过。
- 版本号 2.6.3-r1 → 2.6.4-r1。

## [2.6.3-r1] - P2 批次一：JSON 编解码保真与主机名拆分

P2 批次一，修 `util.lua` 的三项缺陷（审计表 M13 / M14 / L13）。
每项均先复现、后修改，并新增回归测试。

### M14 `json_decode` 永不返回错误串

- **错误被丢弃**：结尾写成 `local v = parse(); return v` —— `parse` 的第二返回值
  （错误串）被直接丢掉。后果是所有调用方的
  `local data, err = util.json_decode(...)` 里 **`err` 判断全是死代码**，
  畸形输入一律表现为「解出来是 nil」，与「内容本来就是 `null`」无法区分。
  现在 `parse` 的错误逐层透出（对象、数组、键、值四处），顶层再判一次。
- **内层错误被吞**：数组循环里无条件 `if val == nil then val = JSON_NULL end`，
  于是 `[1,]` 这种畸形输入被静默接受（`parse` 报错后游标不前进，下一轮读到 `]`
  就当作数组结束），解出 `{1, <null占位>}`。现在内层错误直接上抛。
- **尾部脏数据被忽略**：`parse` 只消费一个值，`"1 2"` / `"[1] junk"` /
  `"1.2.3"`（数字模式只吃 `1.2`）都被当成合法值，尾部内容凭空消失。
  现在解析后必须确认无剩余内容（尾随空白仍允许）。

### M13 数组 `null` 与空对象往返被改写

- **数组里的 `null` 变成 `[]`**：解码时用 `JSON_NULL` 占位保留位置，但
  `json_encode` **没有对应的编码分支**，占位符落进 `is_array` 判定（空表判为数组）
  被编成 `[]` —— `[null,1]` 往返变成 `[[],1]`，结构被悄悄改写。已补分支还原为
  `null`。
- **空对象变成空数组**：`{"tls":{}}` 解出的裸 `{}` 会被 `is_array` 判成数组、
  编码回 `[]`，于是 `{"tls":{}}` 往返变成 `{"tls":[]}`。sing-box / Xray 里要求是
  **对象**的字段（`tls` / `settings`）会因此被客户端拒绝。现在解码空对象时返回
  既有的 `M.JSON_EMPTY_OBJECT` 占位（该常量的注释本就说明了这个用途），
  空数组仍编码为 `[]`。

### L13 `split_hostport` 把尾随冒号当成主机名

- `"example.com:"` 原样返回 `host="example.com:"`（端口匹配失败后直接返回整串）。
  调用方拿这个带冒号的串当主机名去解析 DNS 必然失败，而失败点离此处很远、
  很难定位。现在剥掉**结尾**的冒号；`"::1"` 这类不带方括号的裸 IPv6 不受影响，
  剥完为空则返回 `nil, nil`。

### 测试

- 新增 `tests/util_json_test.lua`（29 项断言）：错误上报、尾部脏数据、
  `null` / 空对象 / 空数组往返、以及既有行为的回归（转义、unicode、数字、字符串）。
- `tests/run_tests.lua` 的 `split_hostport` 段扩 4 项（尾随冒号、`[::1]:`、
  裸 `::1`、裸 `:`）。
- 全量回归：40 个 Lua 测试文件 + `cron_result_test.sh`(11) 全部通过，0 失败。
- 版本号 2.6.2-r1 → 2.6.3-r1。

## [2.6.2-r1] - 更新日志补记与遗留缺陷汇总

**文档批次，无代码改动。**

- **补记 P0 四次推送的更新内容**：`[2.6.0-r2]` ～ `[2.6.0-r5]` 四个条目对应提交
  `12ab1a7` / `46fe3b6` / `2b9934e` / `fb51e6e`。这四次推送当时**未提升版本号**
  （`Makefile` 始终为 `2.6.0-r1`），因此本文件原先没有对应条目；现按推送顺序补记，
  使更新日志与实际推送一一对应。包版本号未回改，历史提交未被重写。
- **新增 [`docs/LEGACY_ISSUES.md`](docs/LEGACY_ISSUES.md)**：汇总截至 2.6.1-r1 审计中
  已确认但**尚未修复**的问题，每项给出代码级依据、影响面与候选修复方案，供决定后续
  修复优先级。原始 70 项审计表未落盘，该文件自本次起作为「未修复项」的权威清单。
- **修正一处遗留项的描述**：`[2.6.1-r1]` 中记录的「sing-box YAML 读取侧不读传输参数」
  经实测确认**比原描述更严重**——两个读取侧都不把 `transport.type` 映射到 `net`，
  ws / grpc / h2 节点导入后**整层传输丢失**（退化为 tcp 直连），而非仅丢 path/host。
  详见 `docs/LEGACY_ISSUES.md` 第 3 节。
- 版本号 2.6.1-r1 → 2.6.2-r1。

## [2.6.1-r1] - P1 批次缺陷修复（解析保真 / 输出合法性）

本轮修复 2.6.0 审计表中 **P1 批次的 13 项缺陷**，另修复审计过程中实测确认的
**4 项新缺陷**。所有修改均先做代码级审计、再用临时探针复现缺陷、修改后复测，
并补齐回归测试（新增 `tests/p1_fixes_test.lua`，97 项断言）。未做任何推测性改动。

### 解析保真（节点导入）

- **trojan 密码未做 URL 解码**：`trojan://p%40ss%3Aword@host:443` 的密码被当成
  字面量 `p%40ss%3Aword` 存下，认证必然失败。已补 `util.url_decode`。
- **vmess classic JSON 忽略 `host` / `path`**：`vmess://base64({...})` 里的
  `host`（ws Host 头）与 `path`（ws 路径）被静默丢弃，服务端按默认路径匹配失败。
  现已保留；未提供时不会凭空造出字段。
- **SSR 密码 base64 回退不可达**：密码字段的 base64 解码走了不可达分支，
  明文密码会被解成乱码并写盘下发。已改用往返一致性判据的解码器。
- **`ssr://` 外层不接受 base64url 字母表**（新发现）：`util.base64_decode` 会把
  `-` / `_` 当非法字符**直接剔除**，于是外层用 base64url 编码的 `ssr://` 链接
  少掉若干字符、整串解成乱码——server / port / 密码全错，且不报错。
  已改用 `base64_url_decode`（对标准 base64 输入逐字节等价，严格更宽容）。
- **userinfo 按首个 `@` 切分**：密码含未转义的 `@` 时（`hysteria2://p@ss@host:443`）
  密码被截断、host 变成 `ss@1.2.3.4`。trojan / hysteria2 / hysteria / tuic
  改为按**最后一个** `@` 切分。
- **vless / trojan / vmess / hysteria2 / tuic / ss 缺 host·port 校验**：残缺节点会
  被写成 `server: ` / `port: 0`，mihomo 与 sing-box 会**拒绝加载整份配置**——
  一个节点废掉整个订阅。解析阶段即丢弃（port 必须落在 1..65535）。
- **sing-box YAML 的嵌套 `tls:` map 被跳过**：`tls: {enabled, server_name, insecure}`
  整层丢失，导出的 trojan/vmess/vless 静默退化成明文，hysteria2/tuic 更让客户端
  以 `C.ErrTLSRequired` 拒绝启动。现已展开为 `security` / `sni` /
  `skip-cert-verify` / `alpn` / `fp`。
- **简易 YAML 解析器不支持嵌套序列**（新发现）：`tls.alpn:` 后跟 `- h2` 会让
  映射收集器在该行立刻中断，**不只 alpn 丢失，排在它后面的 `utls.fingerprint`
  也一并消失**。已新增序列收集逻辑（声明顺序置于映射收集器之前，
  避免 Lua 局部函数 upvalue 捕获陷阱）。
- **通用 JSON 节点忽略 `type` 字段、无协议白名单**：`type` 不再被忽略，改为按
  权威映射表转成协议并消费掉；未知类型（`snell` / `ssh` / `shadowtls` 等）
  直接丢弃，而不是兜底成 vmess 造出字段全错的假节点。
- **Surge 段名大小写敏感**：`[PROXY]` / `[Server_Local]` 全大写段名不被识别，
  而 `[` 开头的内容会被判成 JSON 数组，整份订阅报「JSON 解析失败」，一个节点都
  拿不到。段名判定改为大小写不敏感。
- **Surge / QX 未知协议无白名单**（H6 的 Surge 侧）：`A = snell, …` 会把
  `proto="snell"` 透传进模型，输出端变成 sing-box 的 `type: "snell"` /
  Xray 的 `protocol: "snell"` 这类非法取值。现与 Clash YAML 走同一张权威表。
- **订阅列表文件含非法条目时崩溃**：`core.list()` 的 `pairs(meta)` 会抛
  `table expected, got string`，订阅列表页直接 500；cron 路径更糟——
  异常让整轮同步在打印统计前中断，而 `substore-cron.sh` 据此判为**成功**。
  现在过滤坏条目、返回可用条目并带上损坏错误，写路径据此拒绝落盘
  （避免下次保存把坏条目永久抹掉）。

### 输出合法性

- **`output_v2ray` 协议白名单**：原判定是「不等于 ssr」，于是 hysteria2 /
  hysteria / tuic / wireguard 被写成 Xray 根本不认识的 `"protocol": "hysteria2"`，
  凭据还被塞进无意义的 `users` 字段——Xray 解析到未知 protocol 会拒绝整份配置。
  改为白名单（vmess / vless / trojan / shadowsocks / ss / socks / socks5 / http）。
- **clashmeta 从不写 `flow`**：vless 的 `xtls-rprx-vision` 丢失，mihomo 按普通
  vless 处理，服务端要求 vision 时握手失败。surge / v2ray / URI 三个输出都写
  flow，只有 clashmeta 漏了；而 Clash YAML 解析器明确会回读 flow。
- **clashmeta 丢弃 grpc / h2 传输参数**：只写 `network: grpc`，不写
  `grpc-opts.grpc-service-name`，客户端用默认服务名去连、握手失败——与 ws 丢
  path 同类。h2 同理，现按上游文档写 `h2-opts.host`（**列表**）与
  `h2-opts.path`（标量）。服务名取自 `node.path`，与 v2ray 的 `serviceName`、
  sing-box 的 `service_name` 同源。

### 健壮性

- **改名替换串里的 `%` 未转义**：`%` 后接非数字字符会被 gsub 静默吞掉
  （`50%off` → `50off`），**结尾的 `%` 会注入一个 NUL 字节**
  （`100%` → `100\0`）——节点名会写进节点文件并下发给所有客户端。
  现已把字面 `%` 转义为 `%%`，`$1` 仍按捕获引用处理。
- **修复自身引入的 `and/or` 三元陷阱**：`(cond) and nil or x` 在 cond 为真时得到
  `nil`，再被 `or x` 兜回 `x`，等于没生效（正是代码里已注释警告过的坑）。
  已改为显式 `if`。

### 测试

- 新增 `tests/p1_fixes_test.lua`：97 项断言覆盖上述全部修复，
  每项都先在修改前复现缺陷、修改后断言修复行为。
- 全量回归：39 个 Lua 测试文件 + `run_tests.lua`(47) + `cron_result_test.sh`(11)
  全部通过，0 失败。
- 版本号 2.6.0-r1 → 2.6.1-r1。

### 已知未修复（待确认，本轮未改）

> 汇总已迁移至 [`docs/LEGACY_ISSUES.md`](docs/LEGACY_ISSUES.md)，含各项的代码级
> 依据、影响面与候选修复方案。此处保留索引：

- **H10 的丢更新（lost update）**：`load()` → `save()` 之间无任何锁，并发写会
  互相覆盖。Lua 5.1 没有可用的原子锁原语（`os.rename` 覆盖语义无法 CAS、
  无 `flock`、`io.open` 无 `"x"` 模式、无 `link()`），`mkdir` 方案有陈旧锁死锁
  风险。建议作为已知限制记录，或引入 `nixio` 的 flock（本机无法验证）。
- **M28 / M29（CSRF `post_ok()`、ACL）**：依赖 LuCI 框架运行时行为
  （`test_post_security`、ACL 解析），本机无 LuCI 运行环境，无法验证，故未改。
- **sing-box 读取侧传输整层丢失**：`parse_singbox_json` 不读 `transport.type` /
  `transport.path` / `transport.headers.Host` / `tls.utls.fingerprint`，
  简易 YAML 侧同样不处理 `transport`。实测 ws 节点导入后 `net=tcp`、`path=nil`、
  `host=nil`，即整层传输丢失（原记录为「不读 path/host」，实测更严重）。
- **`converter.lua` / `node_converter.lua` 为死代码**：应用中无任何转换入口，
  但 README 声称「协议转换：任意协议 → 任意协议」。

## [2.6.0-r5] - P0 批次四：表单编辑丢 TLS、注入 XSS 与协议字段清单漂移

> 补记条目，对应提交 `fb51e6e`。编号说明见下方 `[2.6.0-r2]` 末尾。

- **H2 节点页注入 `<script>` 的 id 未转义 `</`**：`json_encode` 不转义 `<`，
  而 `</script` 在 HTML 词法阶段就闭合脚本元素（与 JS 字符串上下文无关）。
  id 直接来自查询串，构造 `</script><script>alert(1)</script>` 即可执行任意脚本。
  与 `node_edit.htm` / `local_form.htm` 一致改为 `json_encode` 后转义 `</`。
- **H3 表单编辑静默清空「表单没渲染的字段」**：根因是 `nodeform.js` 的
  `PROTO_FIELDS` 与 `core.merge_form_node` 的 `FORM_KEYS` 是两份各自维护的清单，
  前者决定渲染什么、后者决定清空什么，必然漂移。表单没渲染的字段提交不上来，
  合并时一并清空等于用空值覆盖原值：
  - vmess 的 TLS 层字段是 `security`，表单却渲染 `tls` —— 编辑一次就把
    `security` 抹成 `nil`，`normalize` 再补成 `"none"`，**启用 TLS 的节点静默变明文**；
  - hysteria2 / hysteria / tuic 是 TLS-only，表单不渲染 `security` —— 编辑一次就丢
    TLS，sing-box 因 `C.ErrTLSRequired` 拒绝启动；
  - WireGuard 的 `dns`、vmess 的 `flow` 同理被抹掉。

  修法：字段清单收敛到唯一来源 `substore/node.lua` 的 `M.PROTO_FIELDS`，由 LuCI
  页面渲染成 `window.SUBSTORE_PROTO_FIELDS` 注入（协议列表 `M.PROTOS` 同样处理），
  `nodeform.js` 不再自带副本。`core.merge_form_node` 只清空「本协议表单渲染过」的
  字段，外加：
  - `FORM_ALIASES` —— 解析器产出的下划线写法（`skip_cert_verify`、`obfs_param`…）
    与 `tls`/`security`、`method`/`cipher` 互为别名，必须跟随规范名一起清空，
    否则残留值「关不掉」（`build_tls` 在 `security` 为 `"none"` 时还会退回 `n.tls`）；
  - 协议被改过时把旧协议的字段一并清空（vmess 改 trojan 不该留 uuid）；
  - 协议未知时退回旧的「清空全部表单字段」行为。
- 顺带修掉审计中发现的两个同类问题：
  - `node.lua` 的 `DEFAULTS` 补 hysteria2 / hysteria / tuic 的 `security="tls"` ——
    TLS-only 是协议约束，属归一化该保证的不变量（与 trojan 同理）。Clash YAML /
    sing-box JSON 导入的这两个协议原先没有 `security`，导出的是客户端起不来的配置；
  - `FIELD_LABELS` 补 `"protocol"`（SSR 表单原先显示英文键名）。

测试：`core_merge_node_test.lua` 扩到 28 项；新增 `view_injection_test.lua`
（38 项，静态检查注入转义与字段清单一致性）；全套 38 个测试文件通过。

## [2.6.0-r4] - P0 批次三：列表文件损坏抹除订阅、原子写失效与 token 可预测

> 补记条目，对应提交 `2b9934e`。编号说明见下方 `[2.6.0-r2]` 末尾。

- **H8 `core.load` 不再把「解析失败」当成空列表**：原先 `json_decode` 失败即
  `return 0, {}`，而 `M.add` / `M.add_local` / `M.add_combo` 会在这个空表上追加
  一条再整表写回 —— **一次损坏就抹掉用户全部订阅**，且 `_seq` 归零后重新发出
  `s00000001` 这类已用过的 ID。现在 `load` 返回第三个值 `err`，写入路径据此拒绝
  操作；`M.list` 也把 `err` 透出给调用方。
- **H9 `atomic_write` 检查 write / close / rename 的返回值**：磁盘写满时 `f:write`
  失败但 `os.rename` 仍会成功，等于**原子地换上一个残缺文件**而调用方以为写入成功。
  失败路径统一清理临时文件并返回 `false, err`。
- **H10 临时文件名唯一化**：原先固定为 `"<path>.tmp"`，两个进程同时写同一路径会
  交错写进同一个临时文件，`rename` 上去的是两者内容的混合体，各自的原子性都失效。
  现改为 `"<path>.tmp.<8 字节随机 hex>"`。
- **H11 `rnd_hex` 改用内核熵源**：Lua 5.1 的 `math.random` 是 31 位 LCG，原实现每次
  调用都重新播种，同一时钟刻度内给出相同序列：**实测 20 万次调用约 9.7% 重复**。
  订阅下载 token 是访问控制的唯一凭据，重复即可被猜测。现优先读 `/dev/urandom`，
  仅在不可用时退回只播种一次的 PRNG。

新增 `tests/data_integrity_test.lua`（28 项断言）覆盖上述四项，
全套 37 个 Lua 测试文件全部通过。

## [2.6.0-r3] - P0 批次二：解析器静默吞掉整份订阅

> 补记条目，对应提交 `46fe3b6`。编号说明见下方 `[2.6.0-r2]` 末尾。

- **base64 里包着 YAML / JSON**（`parser.lua`）：base64 分支原先一律把解码结果按
  URI 列表解析。机场把整份 Clash 配置或 sing-box 配置 base64 后直接下发是常见做法，
  这类订阅会得到 **0 个节点且不报错**，用户只看到「订阅为空」。现在解码后重新走一遍
  `detect`/`parse` 复用既有分支；`inner == "base64"` 时不再递归（避免 base64 套
  base64 无限递归），外层容器格式仍报 `base64`。
- **流式风格与行尾注释**（`parser_clash_yaml.lua`）：
  - 新增 `parse_flow_map` / `split_top`：`- {name: A, type: vmess, server: 1.1.1.1}`
    是合法 YAML 但不是合法 JSON（键没加引号），`util.json_decode` 必然失败，
    原先**整项被静默丢弃**。现在 JSON 解失败后回落到 YAML 流式映射解析，并正确
    切分 `{}` / `[]` 内部以及引号内的逗号（`alpn: [h2, http/1.1]`）。
  - 新增 `strip_comment`：YAML 规定内联注释的 `#` 前必须有空白，且引号内的 `#`
    不是注释。原先 `proxies: # 说明` 会把注释文本当成值，`proxies` 变成字符串，
    **整份配置被判定为「没有 proxies」**。列表项同样处理（`- {...} # 注释`）。

回归测试：新增 20 项断言（base64 包 YAML / JSON / 嵌套 base64、流式映射、流式数组值、
行尾注释、`#` 无空白与引号内 `#` 必须保留）。

## [2.6.0-r2] - P0 批次一：sing-box TLS 失效、未知协议泄漏与输出格式注入

> 补记条目，对应提交 `12ab1a7`。

**输出正确性：**

- `output_singbox`：tls 块补 `enabled=true`。sing-box 的 `OutboundTLSOptions.Enabled`
  是 bool + `omitempty`（`option/tls.go`），**缺省即 false**：只写 `server_name` 而不写
  `enabled` 等于没配 TLS —— vmess/vless/trojan 退化为明文拨号，hysteria2/tuic 更会因
  `C.ErrTLSRequired` 拒绝启动。顺带移除因此变成死代码的空表分支，并更正
  `parser_json_config` 里「enabled 缺省即 true」的错误注释。
- `parser_clash_yaml`：未知 Clash 类型（snell / shadowtls / mieru 等）改为**丢弃**。
  原先 `TYPE_MAP[p.type] or p.type or "vmess"` 会把它透传成 sing-box 的 `type:"snell"`、
  Xray 的 `protocol:"snell"` 这类非法取值，客户端会拒绝加载整份配置；缺失 type 时兜底成
  vmess 则是凭空造出字段全错的假节点。`parser.lua` 的简易 YAML 兜底解析（复用同一张
  `TYPE_MAP`）早已如此处理，此处对齐。
- `output_clash_meta`：`sni` 与 `servername` 同时存在时只输出一个 `servername` 键。
  Clash YAML 导入会同时填上两者，原先各写一行让 YAML 出现**重复键**。
- `output_clash_meta`：`esc_yaml` 补 `\r` / `\t` 转义，并在转义前判断是否需要加引号 ——
  转义后的 `"\t"` 落在 plain scalar 里会被 YAML 当成两个普通字符；未加引号的换行/回车
  则直接破坏文档结构。
- `output_formats`：tuic 的 alpn 为数组时（sing-box JSON / Clash YAML 的 alpn 列表
  导入后即为 table）不再 `attempt to concatenate a table value`。

**换行注入**（节点名等来自订阅内容，属不可信输入）：

- 新增 `util.one_line`：把值压成单行（换行/回车转空格，其余控制字符丢弃）。
- `output_formats`：`surge_line` / 代理组行 / Quantumult X 的 `server_local` 与 `policy`
  行统一压平 —— 含换行的节点名会截断当前行并**伪造出新的代理行**。
- `output_wireguard_conf`：`.conf` 注释行压平 —— 否则节点名里的 `"\n[Interface]"`
  会**注入出真正的配置段**。

回归测试：新增 34 项断言覆盖以上全部缺陷（含 sing-box TLS 往返、surge/QX/wgconf 的
行数不变性、未知类型丢弃、控制字符转义）。

> **关于以上四条 `-r2` ～ `-r5` 的编号**：这四次推送（`12ab1a7` / `46fe3b6` /
> `2b9934e` / `fb51e6e`）当时**未提升版本号**，`Makefile` 始终为 `2.6.0-r1`，
> 因此本文件中原先没有对应条目。现按推送顺序补记为 `-r2` ～ `-r5`，使更新日志与实际
> 推送一一对应。包版本号本身未回改，历史提交未被重写；从 2.6.1 起恢复
> 「每次推送提升一个版本号」的约定。

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