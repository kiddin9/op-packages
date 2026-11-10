# 用 JavaScript 视图 + ucode 取代 Lua 实现

- 状态：已接受
- 日期：2026-10-05
- 决策者：cocolight
- 影响版本：2.0.0

## 背景

1.x 用 Lua + CBI model + `luci-compat` 实现。这套路径在OpenWrt 上的实际问题是：

- `luci-compat` 是**兼容层**，不是目标环境。官方文档本身不推荐新应用使用它。
- 端口扫描的旧实现是「每个端口跑一次 `nc -z`，且只扫 loopback」。慢，且扫出来的是
  路由器自己都访问不到的地址。
- 配置写回要经CBI，逻辑分散在 `luasrc/model/cbi/portal/settings.lua` 与
  `luasrc/portal.lua` 两处。

与此同时 LuCI 已把 JavaScript 视图作为正式路径，`rpcd-mod-ucode` 让后端可以不依赖
Lua 运行时。

## 决策

2.0.0 起前端改为三个纯 JavaScript 视图（`htdocs/luci-static/resources/view/portal/`），
后端改为 ucode rpcd 插件（`root/usr/share/rpcd/ucode/portal.uc`），不再需要
`luci-compat`。

端口扫描改为读 `/proc/net/tcp[6]`，只保留**从 LAN 地址可达**的监听端口。

## 后果

- 正面：去掉一个兼容层依赖；扫描从「N 次进程调用」变成「一次文件读取」；`uci` schema
  不变，老配置可直接沿用。
- 负面：1.x 用户的自定义要迁移（`icon` → `icon_url` 语义见 README的 *Migrating*
  一节）；`portal.uc` 只能用 ubus 调用，不能当CLI 工具用（rpcd 加载时不定义 `ARGV`）。
- **负面（已发生）**：`run_rpc()` 沿用「promise 链 + `.catch()`」的写法，而后端用
  `{ ok: false }` **返回**失败，于是 resolved 的失败被当成成功 —— 这是 v2.0.0-r7
  已知缺陷的根因 1。教训：跨语言边界必须有一方显式检查成功标志，不能靠异常传播。

## 备选方案

- 继续维护 Lua 实现：不选。`luci-compat` 是过渡设施，且扫描实现无法在不重写的情况下
  改进。
- 前端改用 TypeScript + 构建步骤：不选。本项目是纯脚本包，引入构建会让「clone 即可
  审查」失效，CI 也无法在合理时间内验证。
