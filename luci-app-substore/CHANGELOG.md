# Changelog — luci-app-substore

All notable changes to this project will be documented in this file.

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