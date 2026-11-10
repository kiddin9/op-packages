# 架构决策记录（ADR）

本目录记录项目的重要架构决策，供人与 AI 助手在改动前查阅。

## 约定

- 一个文件一个决策，命名 `NNNN-kebab-title.md`（四位递增序号）。
- 复制 [template.md](template.md) 起草新记录。
- 状态为「已接受」的记录**不得直接修改**；需要变更时新增一条 ADR，并在新旧记录中标注取代关系。
- 新增 / 更新 ADR 的提交类型用 `docs:`。

## 索引

| 编号 | 标题 | 状态 |
|------|------|------|
| [0001](0001-record-architecture-decisions.md) | 采用 ADR 记录架构决策 | 已接受 |
| [0002](0002-javascript-views-over-lua.md) | 用 JavaScript 视图 + ucode 取代 Lua 实现 | 已接受 |
| [0003](0003-no-test-framework-syntax-level-gate.md) | 不引入测试框架，改用语法级门禁 | 已接受 |
| [0004](0004-serve-portal-from-main-uhttpd.md) | 门户改由主 uhttpd 的子路径提供 | 已接受 |
| [0005](0005-semver-release-tags.md) | 发布版本号改用纯语义化 tag（去掉 `-rN` 后缀） | 已接受 |
| [0006](0006-search-box.md) | 门户页搜索框：引擎清单在 LuCI 表单，`links.json` 只传模板 | 已接受 |
| [0007](0007-liteportal-runtime-identifier-rename.md) | 运行时标识从 `portal` 全量更名为 `liteportal` | 已接受 |
