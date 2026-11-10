# 完成定义（Definition of Done）

功能是否算「完成」，以以下条件**同时满足**为准。本文件是 `AGENTS.md` §5 的详细版。

## 通用清单

- [ ] `ROADMAP.md` 中该行「验收标准」全部满足
- [ ] `sh scripts/check.sh` 输出 `ALL CHECKS PASSED`（本地与 CI 同一个脚本）
- [ ] 未引入无关改动（无顺手重构/格式化噪声）
- [ ] 相关文档（README / AGENTS / architecture / ADR）同步更新
- [ ] `CHANGELOG.md` 的 `[Unreleased]` 已记录本次改动
- [ ] `ROADMAP.md` 状态更新为 `done`

## 本项目的替代项：无单元测试

模板默认要求「新增或更新了对应测试，且全量测试通过」。本项目**没有可运行的单元测试**，
因此用下面这组**可判定的替代物**顶上。它们的共同点是：能被一条命令判定，不依赖主观
描述。

| 本应做到的 | 本项目的判定方式 |
|------------|------------------|
| 改动 JS 后语法没坏 | `node --check` 覆盖全部 5 个 JS |
| 改动的 shell 脚本没退化 | `shellcheck -s sh root/etc/init.d/liteportal` |
| JSON 配置能被加载 | `python3 -m json.tool` 覆盖菜单与 ACL |
| 新增 ubus 方法能被调用 | `scripts/check.sh` 的 ubus↔ACL 对应关系检查 |
| 翻译文件没写坏 | `msgfmt --check` |
| 菜单指的视图确实存在 | `scripts/check.sh` 的 menu.d `path` ↔ `view/*.js` 存在性检查（漏了 = 设置页整页空白） |
| 改名没有漏掉某处路径常量 | `scripts/check.sh` 的运行时标识一致性检查（以 `Makefile` 的 `PKG_NAME` 推导期望值，逐处比对 5 个文件） |
| 没在 Windows 上把脚本改成 CRLF | 行尾检查（这会直接让设备上 `bad interpreter`） |
| 模板占位符没漏替换 | 占位符扫描 |

**这不是「测试够了」的借口。** ROADMAP 第 6 项（回归测试体系）就是为补上真测试而列的；
在那之前，改动 `common.js` / `assets.js` 这类**有状态、有分支**的代码时，
验收标准应写成设备上的可观察现象（例：「设备上重命名后文件名确实改变，且失败时弹错误
提示」），而不是「检查通过」。

## 按类型的差异

| type | 额外要求 |
|------|----------|
| `feat` | 必须新增可判定的验收标准（进 `ROADMAP.md`）；改了 ubus 方法则同步 ACL |
| `fix` | 必须在 `ROADMAP.md` 记录**根因**，而不只是改了什么；验收标准要能区分「修好」与「碰巧没触发」 |
| `docs` | 无需检查命令，但链接必须可用（本项目文档互链较多，改名要全仓库 grep） |
| `chore` / `ci` | 不得降低既有门禁强度（不得从 `scripts/check.sh` 摘项、不得加 `\|\| true`） |
| `build` / `Makefile` | 需在真实 SDK 上构建过一次，并确认产物落在 `bin/packages/<arch>/luci/` |

## 禁止的「完成」信号（伪完成）

- 声称「检查已通过」但未实际运行 `sh scripts/check.sh`。
- 声称「已安装到设备测试」但没有 `ubus call` 输出作为证据。
- 从 `scripts/check.sh` 里摘掉一项检查，或给它加 `|| true` 让门禁变绿。
- 放宽 `.gitattributes`、shellcheck 严重级别或 msgfmt 参数来让检查通过。
- 只改 `.uc` 不改 ACL —— 运行时才暴露为 *Access denied*。
- 声称「已推送 / 已开 PR」而实际未执行（推送与发版是**显式动作**，需明确要求）。
