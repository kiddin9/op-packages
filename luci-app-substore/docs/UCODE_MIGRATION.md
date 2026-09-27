# 模板迁移评估：`.htm` (Lua) → `.ut` (ucode)

> **状态**：评估完成，未执行迁移。原因：本机无 OpenWrt 构建/运行环境，`.ut` 模板无法编译验证，冒然上线未经验证的 `.ut` 比保留 `.htm` 更危险（若 25.12 模板加载器优先 `.ut`，带 bug 的 `.ut` 会直接覆盖原本可用的 `.htm`）。

## 1. 背景

本项目的 LuCI 前端采用 **Lua 兼容模式**（`luci-lua-runtime` + `luci-compat`），模板为 `.htm`（Lua 代码 + `<% %>` / `<%= %>` / `<%: %>` 标签）。

| LuCI 版本 | 模板体系 | 本项目的 `.htm` |
|-----------|----------|------------------|
| 23.05 | Lua（`.htm`） | ✅ 原生支持 |
| 24.10 | ucode（`.ut`）为主，Lua 兼容层保留 `.htm` | ✅ 经 `luci-lua-runtime` |
| 25.12+ | 趋向 ucode（`.ut`），Lua 兼容层可能移除 | ⚠️ 风险点 |

调研结论（来自 LuCI 上游变更）：24.10 起 `luci-base` 重写为 ucode，模板加载器优先查找 `.ut`；`.htm` 通过 Lua 兼容层继续工作。25.12 若彻底移除 `luci-lua-runtime`，则 `.htm` 失效，需 `.ut` 模板。

## 2. 涉及文件（5 个模板）

`root/usr/lib/lua/luci/view/substore/` 下：
- `subscriptions.htm` — 订阅列表（表格、token 链接、复制按钮、多表单）
- `form.htm` — 添加/编辑订阅
- `nodes.htm` — 节点查看（GET 表单筛选/排序）
- `output.htm` — 输出页（格式下拉、textarea）
- `settings.htm` — 设置页（cron 选择器、规则）

## 3. `.htm` → `.ut` 语法对照

| 事项 | Lua `.htm` | ucode `.ut` |
|------|-----------|-------------|
| 输出标签 | `<%=expr%>` | `<%= expr %>`（ucode 表达式）或 `{{= expr }}` |
| 翻译标签 | `<%:Text%>` | `<%:Text%>`（保留，语义一致） |
| 引入其它模板 | `<%+header%>` / `<%+footer%>` | `<% include("header") %>` / `<% include("footer") %>` |
| 取 HTTP 参数 | `require("luci.http")` + `http.formvalue(...)` | 预绑定全局 `http`，`http.formvalue(...)` |
| 取查询参数 | `luci.dispatcher.context.query` | 预绑定全局 `REQUEST`，`REQUEST.query` |
| 迭代数组 | `for _, v in ipairs(t) do ... end` | `for (let v in t) { ... }` |
| 条件 | `if cond then ... end` | `if (cond) { ... }` |
| 字符串拼接 | `..` | `+` |
| 三元 | `a and b or c`（有陷阱） | `cond ? a : b` |
| 取长度 | `#t` | `length(t)` |
| 索引 | `t[k]` / `t.k` | `t[k]` / `t.k` |
| 核心库调用 | `require("substore.core")` 后 `core.xxx()` | `core = include("substore/core.lua")` 后 `core.xxx()` |

## 4. 关键决策点

1. **核心库无需改写**：`/usr/share/substore/*.lua` 是纯 Lua，ucode 通过 `include()` 加载 Lua 文件并调用其函数（ucode 内置 Lua 互操作）。这是本方案最有利的一点——迁移成本集中在 5 个模板文件的“胶水代码”，核心逻辑（解析/转换/输出）不受影响。

2. **控制器**：`controller/admin/substore.lua` 目前用 `module()` + `entry()`。24.10 仍支持；若 25.12 要求 ucode 控制器（`.uc`），则需另写 `controller/admin/substore.uc`。与模板一样，属胶水层。

3. **数据存储与下载端点**：`core.lua`、`action_download` 逻辑与模板语言无关，无需迁移。

## 5. 建议的落地策略

按“能验证再迁移”原则，分步：

- **第 1 步（当前）**：保持 `.htm` + `luci-lua-runtime` 依赖，确保 23.05 / 24.10 可用。
- **第 2 步**：在真实 24.10 设备上安装，验证 `.htm` 经兼容层正常渲染。
- **第 3 步**：拿到 25.12 构建环境后，逐模板迁移为 `.ut`（可 `.htm` 与 `.ut` 并存，LuCI 优先 `.ut`），每个模板迁完即在设备上验证页面。
- **第 4 步**：25.12 若移除 Lua 运行时，同步评估控制器 `.uc` 迁移。

## 6. 示例迁移（subscriptions.htm 片段）

Lua 现状：

```html
<%
local core = require("substore.core")
local items = core.list()
for _, it in ipairs(items) do
%>
  <tr><td><%=it.name%></td></tr>
<%
end
%>
```

ucode 等价：

```html
<%
let core = include("substore/core.lua");
let items = core.list();
for (let it in items) {
%>
  <tr><td><%= it.name %></td></tr>
<%
}
%>
```

> 注：`include("substore/core.lua")` 的路径与 ucode 的 `LUCI_PATH` / `package.path` 解析规则有关，具体以 25.12 目标机的 `include` 路径解析为准，迁移时需在设备上确认。
