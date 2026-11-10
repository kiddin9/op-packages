# 不引入测试框架，改用语法级门禁

- 状态：已接受
- 日期：2026-10-05
- 决策者：cocolight

## 背景

模板（ai-template-repository）的默认 DoD 要求「新增或更新对应测试，且全量测试通过」。
本项目没有可运行的单元测试：它是 LuCI 软件包，前端代码依赖浏览器侧的 LuCI 模块加载
机制（`'require views/portal/common as common'` 这类调用在 Node 下无法解析），后端是
ucode 插件（只能由 rpcd 加载，脱离 rpcd 无法调用）。

要真正跑起单测，就得引入浏览器模拟层 + ubus 模拟层，等于为 2000 行代码建一套测试
基础设施。

## 决策

不引入测试框架。质量门禁改为**语法级检查 + 交叉引用一致性**，全部实现在
`scripts/check.sh`，CI 与本地调用同一个脚本：

| 检查 | 拦住什么 |
|------|----------|
| `node --check` | JS 语法错误 |
| `python3 -m json.tool` | 菜单 / ACL 的 JSON 语法错误 |
| `shellcheck` | init 脚本的 shell 问题 |
| `msgfmt --check` | 翻译文件损坏 |
| ubus 方法 ↔ ACL 白名单 | 改了 `.uc` 忘改 ACL（运行时才暴露为 Access denied） |
| 行尾 | Windows 上把脚本改成 CRLF（设备上 `bad interpreter`） |
| 占位符扫描 | 模板替换漏做 |

在 `ROADMAP.md` 中明确列出「回归测试体系」为 planned，并要求在它落地前，
涉及有状态/分支逻辑的改动，其验收标准写成**设备上的可观察现象**而非「检查通过」。

## 后果

- 正面：门禁是实跑的、可判定的、本地与 CI 完全一致；不引入构建步骤；clone 后
  5 秒内知道有没有把语法写坏。
- **负面（明确承认）**：语法级门禁**无法**发现逻辑错误。`run_rpc()` 吞掉后端失败
  这类缺陷（v2.0.0-r7 已知缺陷）任何一项检查都抓不到 —— 它语法完全正确。
  因此 DoD 文档里为这类改动设了更高的验收要求。
- `shellcheck` 与 `msgfmt` 缺失时门禁**降级但不消失**（退化为 `sh -n`，并明确打印
  `skip`），不会静默通过。

## 备选方案

- vitest + jsdom模拟 LuCI：不选。见「背景」—— 成本远超收益，且测出来的多是模拟层的行为。
- 在 CI 里拉 SDK 真编译 `.apk`：不选作为门禁（耗时数分钟、易 flake），但保留为发布前
  的人工验证项，写在 `docs/definition-of-done.md` 的「按类型的差异」里。
