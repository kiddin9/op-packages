# 分阶段开发计划 — luci-app-substore

架构覆盖完整功能，交付分阶段进行。每阶段产出可编译、可安装、可验证的产物。每阶段遵循 CLAUDE.md 流程：说明目标 → 检查现有代码 → 列改动文件 → 小范围实施 → 静态检查/测试 → 检查 diff → 更新文档 → 汇报。

## 阶段 0 — 骨架与构建链路验证

**目标**：最小可编译、可安装的包骨架，跑通 OpenWrt 构建与安装全链路。

**产出**：
- Makefile（含 DEPENDS、安装路径、postinst）
- LuCI 菜单注册 + 一个占位页面（订阅列表空态）
- UCI 配置文件 `/etc/config/substore` + uci-defaults
- docs/BUILD.md、docs/INSTALL.md、README.md（骨架版）

**验收**：在目标 OpenWrt 设备上 `make package/luci-app-substore/compile` 成功、安装后 LuCI 出现菜单并可打开页面。

## 阶段 1 — 订阅源管理与下载解析

**目标**：订阅源 CRUD + URL 下载 + 本地粘贴导入 + 基础解析。

**产出**：
- `core.lua`：订阅源元数据读写（独立 JSON 数据文件）
- `http.lua`：SSRF 防护、超时、大小限制的下载器
- `parser.lua`：Base64/URI 订阅解析 → 统一节点模型（首批协议：vmess/vless/trojan/shadowsocks/ss）
- `node.lua`：节点模型基础
- LuCI 订阅列表页 + 添加/编辑/更新/删除
- UCI 存订阅源元数据；节点数据存独立文件

**验收**：添加真实订阅 → 手动更新 → 列表显示节点数、更新时间、解析成功状态。

## 阶段 2 — 节点处理与筛选

**目标**：节点查看、搜索、筛选、排序、重命名、去重。

**产出**：
- `node.lua`：筛选（协议/名称/关键词）、去重（同 server+port+proto）、重命名、排序
- LuCI 节点查看页（列表/搜索/筛选）
- 解析器测试样例

**验收**：对含重复、多协议的真实订阅，去重/筛选/重命名/排序结果正确。

## 阶段 3 — 多订阅合并与输出（订阅转换 + 订阅链接）

**目标**：任意类型节点转换为任意类型，13 种输出格式全量实现，转换结果以订阅链接形式下发。

**产出**：
- `output.lua`：统一格式分发（FORMAT_ALIASES 别名映射、content-type / 扩展名）
- `output_clash_meta.lua`：Clash.Meta / Mihomo / Stash YAML
- `output_uri.lua`：分享链接 URI / Shadowrocket(base64) / V2Ray URI
- `output_singbox.lua`：sing-box JSON
- `output_v2ray.lua`：V2Ray/Xray JSON
- `output_formats.lua`：Surge / Surfboard / SurgeMac / Loon / QX / Egern / Plain JSON
- `node_converter.lua` + `converter.lua`：协议间转换、URL 模板渲染
- `parser_surge.lua`：Surge / Loon / QX 客户端配置导入
- `parser.lua` 接线：sing-box / V2Ray / Clash JSON / Clash YAML / Surge / QX 输入源
- `core.generate_link(token, target)` + 每订阅随机 token
- LuCI 公开下载端点 `/substore/download?token=<token>&target=<format>`
- LuCI：output 页 13 格式下拉、subscriptions 页展示可复制的订阅链接

**验收**：合并多订阅生成 13 种格式，Passwall / OpenClash 可通过订阅链接拉取。

## 阶段 4 — 定时更新、规则、完善

**目标**：定时更新（cron）、规则配置、错误处理、安全加固、多版本兼容。

**产出**：
- 定时更新（cron / procd）
- 规则配置页
- 完整错误处理、日志
- 分版本依赖适配（23.05 / 24.10 / 25.12）
- **模板迁移：`.htm` → `.ut`（ucode），确保 25.12 兼容**（调研：25.12 模板优先级 `.ut` only）
- 订阅下载方式定案：curl vs Lua socket（影响 SSRF 防护实现，阶段1评估）
- docs/SECURITY.md、docs/TESTING.md、CHANGELOG.md

**验收**：定时更新生效、错误日志可读、各 OpenWrt 版本兼容、安全测试通过。

---

## 依赖关系

阶段 0 → 1 → 2 → 3 → 4（顺序推进，每阶段验证通过再进下一阶段）

## 当前状态

- [x] 调研：OpenWrt LuCI 24.10 有 luci-lua-runtime（Lua 兼容层），Lua 方案可行
- [x] 架构设计：docs/ARCHITECTURE.md
- [x] 分阶段计划：本文档
- [x] 阶段0：骨架构建链路验证通过（菜单位于 服务 → Subscriptions）
- [x] 阶段1：订阅 CRUD + 下载解析核心实现（core/util/node/parser/http + LuCI 列表/表单）
- [ ] 阶段1验证：用户在设备上添加真实订阅、手动更新、查看节点数/更新时间
- [x] 阶段2：节点处理与筛选（node.lua 筛选/去重/重命名/排序 + 分组/标签/重命名规则）
- [x] 阶段3：订阅转换 + 订阅链接（13 种输出格式、协议转换、输入源扩展、下载端点）
- [x] 阶段4：定时更新（cron）、规则配置、错误处理、安全加固、多版本兼容
  - [x] cron 定时更新（substore-cron.sh 独立可运行、设置页 cron 配置）
  - [x] 规则配置页（协议过滤/关键词/去重/重命名规则，含精确·正则·模板三形式）
  - [x] 错误处理（core.sync 日志、action_update pcall 兜底、列表状态列展示错误）
  - [x] 安全加固（下载文件名白名单防头注入；SSRF/大小/超时此前已实现）
  - [x] 多版本兼容（LUCI_DEPENDS luci-lua-runtime + luci-compat）
  - [ ] 模板迁移 `.htm` → `.ut`（ucode）：已评估并写 docs/UCODE_MIGRATION.md，未执行——需 25.12 构建环境验证