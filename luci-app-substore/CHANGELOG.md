# Changelog — luci-app-substore

All notable changes to this project will be documented in this file.

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