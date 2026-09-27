# 架构设计 — luci-app-substore

OpenWrt / ImmortalWrt 原生 LuCI 机场订阅管理工具。参考 Sub-Store 功能体验，独立设计与实现，不复制上游代码。

## 1. 目标与范围

原生 OpenWrt 软件包，不使用 Docker，不依赖外部云端服务。在低性能路由器（内存 ≤ 512MB，存储紧张）上运行。

功能范围：
- 订阅管理：多订阅源增删改查、手动/定时更新、更新时间/节点数/状态展示
- 节点管理：解析常见代理协议、查看/搜索/筛选/排序/重命名/去重
- 订阅处理：按条件筛选、去重、重命名、排序、多订阅合并、生成客户端订阅
- 输出格式：13 种全量实现（Plain JSON / Stash / Clash.Meta / Surfboard / Surge / SurgeMac / Loon / Egern / Shadowrocket / QX / sing-box / V2Ray / V2Ray URI）
- 订阅链接：转换结果以订阅链接形式下发，供 Passwall / OpenClash 等拉取
- LuCI 界面：订阅列表、编辑更新、节点查看、规则配置、输出复制、状态日志

## 2. 技术选型

| 层 | 选型 | 理由 |
|----|------|------|
| 后端核心 | **Lua 5.1 纯脚本库** | 用户选定；不依赖 luci.*，可独立测试；跨 LuCI 版本稳定 |
| LuCI 前端 | **Lua 兼容模式 (luci-lua-runtime)** | 用户选定；在 23.05+/24.10+/25.12 以 Lua 兼容层运行 |
| 数据存储 | 独立数据文件 `/etc/substore/*.json` | CLAUDE.md 要求订阅/状态用独立文件，不用 UCI 存节点数据 |
| 配置 | UCI `/etc/config/substore` | 仅存订阅源元数据、处理规则、输出设置 |
| 后台服务 | procd（仅当需要常驻/定时时） | 定时更新可走 LuCI 页面触发 + cron，避免常驻 |
| 输出接口 | LuCI 路由 / CGI，带随机 Token 鉴权 | CLAUDE.md 安全要求 |

## 3. 模块划分

```
luci-app-substore/
├── Makefile                 # 软件包构建
├── root/
│   ├── etc/config/substore  # UCI 配置
│   ├── usr/lib/lua/luci/    # LuCI 前端（controller / model / view）
│   └── usr/share/substore/  # 纯 Lua 核心库 + 数据目录
├── src/                     # 可选：需编译的辅助（暂无）
└── docs/                    # 文档
```

核心库（`/usr/share/substore/`，纯 Lua，不依赖 luci.*）：
- `core.lua` — 订阅源元数据读写、状态管理、订阅链接生成（token + generate_link）
- `parser.lua` — 订阅格式解析（Base64/URI/Clash YAML/JSON）
- `node.lua` — 节点模型、筛选、去重、重命名、排序
- `node_converter.lua` — 协议间字段映射与协议转换
- `converter.lua` — 通用转换器（字段映射、URL 模板渲染）
- `output.lua` — 统一格式分发（FORMAT_ALIASES 别名映射、content-type/扩展名）
- `output_clash_meta.lua` — Clash.Meta / Mihomo / Stash YAML
- `output_uri.lua` — 分享链接 URI / Shadowrocket / V2Ray URI
- `output_singbox.lua` — sing-box JSON
- `output_v2ray.lua` — V2Ray/Xray JSON
- `output_formats.lua` — Surge 系 / Loon / QX / Egern / Plain JSON
- `http.lua` — 订阅下载（SSRF 防护、超时、大小限制）
- `util.lua` — 通用工具（原子写、时间、日志、Base64、JSON）

LuCI 前端（`/usr/lib/lua/luci/`）：
- `controller/admin/substore.lua` — 路由注册
- `model/cbi/substore/*.lua` — 配置界面
- `view/substore/*.htm` — 页面模板

## 4. 数据流

订阅 URL / 本地文本 → `http.lua` 下载（SSRF 防护）→ `parser.lua` 解析 → `node.lua` 统一节点模型 → 去重/筛选/重命名/排序 → `output.lua` 按目标格式生成 → LuCI 界面 / 订阅下载端点

**订阅链接下发流程**：每个订阅在创建时生成随机 16 位十六进制 `token`，存入元数据。客户端请求公开端点
`GET /substore/download?token=<token>&target=<format>`（如 `target=ClashMeta`），无需登录态、靠不可猜测的 token 鉴权，
按 `target` 实时转换节点并返回（`node_converter.lua` 负责协议间转换，`output.*` 负责格式生成）。

节点统一内部模型（协议无关）：
```lua
{
  proto = "vmess"|"vless"|"trojan"|"shadowsocks"|"hysteria2"|"tuic"|"ss"|...,
  name = "节点名",
  server = "host",
  port = 443,
  uuid = "uuid", password = "...", cipher = "...", -- 协议特有字段
  raw = "原始URI串"  -- 保留原始，便于无损转发
}
```

## 5. 安全设计（CLAUDE.md 第 6 节）

- **SSRF 防护**：`http.lua` 下载前解析主机名，拒绝 localhost/内网/链路本地/保留地址；DNS 解析后二次校验；处理重定向
- **资源限制**：订阅响应体最大大小（默认 10MB 可配）、连接/总超时、并发限制
- **路径穿越**：订阅名/文件名做白名单校验，禁止 `..`、`/`
- **命令注入**：不将用户输入拼入 shell；需要时用参数化执行
- **凭据保护**：订阅 URL 中的 token/密码不写入普通日志；输出接口用随机 Token 鉴权
- **导入校验**：解析时对结构/大小/嵌套深度做限制，防恶意 YAML/JSON 资源耗尽
- 所有安全策略结合 OpenWrt 实际网络环境实现并编写测试

## 6. 兼容性约束

- 目标 LuCI 使用 Lua 兼容模式，需依赖 `luci-lua-runtime` + `luci-compat`（23.05+）
- Lua 控制器沿用 `module()` + `entry()` 风格（24.10 有效，活跃插件仍在使用）
- **25.12 风险**：LuCI 模板优先级已转向 `.ut`（ucode），`.htm` 为 Legacy。阶段4 已评估迁移方案，详见 `docs/UCODE_MIGRATION.md`（含 `.htm`→`.ut` 语法对照与逐模板映射；核心库纯 Lua 可通过 `include()` 复用，迁移成本集中在 5 个模板的胶水代码）
- 不假设所有 OpenWrt 版本依赖一致，分版本适配
- 纯 Lua 核心库优先用 Lua 5.1 标准库（luci 自带 lua5.1），避免 luarocks 依赖
- 如需要 YAML 解析：优先评估纯 Lua 实现或 luci 内置，避免重运行时
- `/lib/functions/luci.sh` 已移除，postinst 用 `rm -f /tmp/luci-indexcache` + `/etc/init.d/luci reload` 刷新缓存

## 7. 文档清单

README.md、docs/ARCHITECTURE.md、docs/BUILD.md、docs/INSTALL.md、docs/SECURITY.md、docs/TESTING.md、CHANGELOG.md