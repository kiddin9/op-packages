# 仓库与项目配置说明

本文说明代码之外还需要配置什么：工具链、Git、行尾、CI、分支保护。
AI 的行为规则见 [AGENTS.md](../AGENTS.md)。

> ⚠️ 本文件是 `scripts/check.sh` 中「模板占位符」检查的唯一豁免文件 ——
> 因为它必须描述占位符语法本身，字面上含有双花括号。

## 1. 环境要求

| 组件 | 要求 | 说明 |
|------|------|------|
| Git | ≥ 2.28 | 本仓库已用 `main` 作默认分支 |
| POSIX Shell | `sh` | `scripts/check.sh` 与 `root/etc/init.d/liteportal` 都按 POSIX `sh` 写 |
| Node.js | ≥ 18 | 仅用于 `node --check`（语法解析），CI 用系统自带版本 |
| Python | ≥ 3.8 | 仅用于 `python3 -m json.tool` |
| shellcheck | 任意 | 可选；缺失时门禁降级为 `sh -n` 语法检查并明确打印 `skip` |
| gettext | 任意 | 提供 `msgfmt`；缺失时翻译检查 `skip` |
| Linux SDK | 与目标固件匹配 | 仅构建 `.apk` / `.ipk` 时需要，见 §6 |

Windows 下所有命令均可在 Git Bash 执行。跳过 `shellcheck` / `msgfmt` 的两项会打印
`skip` 而**不是静默通过** —— 门禁降级但不消失。

## 2. Git 配置

### 仓库级签名

只影响当前仓库，不动全局配置：

```bash
git config user.name  "cocolight"
git config user.email "you@example.com"
```

提交署名与版权声明统一用 `cocolight`。

### 行尾（本项目踩过的坑）

仓库自带 `.gitattributes`，库内与工作区一律 LF，**它会覆盖全局的
`core.autocrlf=true`**。

这个项目对此尤其敏感：`root/etc/init.d/liteportal` 一旦被检出成 CRLF，装到设备上就会
`bad interpreter: /bin/sh^M`，而它在仓库里看起来完全正常。

验证：

```bash
git ls-files --eol              # 期望 i/lf 与 w/lf 一致
git check-attr eol -- root/etc/init.d/liteportal   # 期望 eol: lf
```

若克隆后文件已被转成 CRLF：

```bash
git add --renormalize .
git commit -m "chore: normalize line endings"
```

`scripts/check.sh` 的行尾检查会在 `w/crlf` 时直接失败并给出这条修复命令。

### 文件权限位

`scripts/check.sh` 在索引中必须是 `100755`：

```bash
git ls-files -s scripts/                # 期望 100755
git update-index --chmod=+x scripts/check.sh   # 修复
```

⚠️ `git add` / `git reset --mixed` 会按工作区推断模式把索引重置回 `100644`，
所以 `--chmod=+x` 必须在 `git add` **之后**执行。

本项目的 `root/etc/init.d/liteportal` **不需要**可执行位 —— 它由 `luci.mk` 在打包时
设为 0755。

## 3. 行尾与目录约定

| 路径 | 用途 |
|------|------|
| `htdocs/` | LuCI 前端（安装到 `/www/luci-static/`） |
| `root/` | 设备文件树，安装到 `/` |
| `po/` | 翻译模板与 zh_Hans 翻译 |
| `scripts/` | 辅助脚本（不安装到设备） |
| `docs/` | 文档；`docs/adr/` 为架构决策记录 |
| `.github/workflows/` | CI 工作流 |
| `dist/` | 发版检查清单等产物 |

详见 [architecture.md](architecture.md)。

## 4. CI（GitHub Actions）

只有一个工作流：`.github/workflows/build.yml`，job `test`。它本身不写检查逻辑，
只做两件事：装依赖（`shellcheck`、`gettext`），然后调 `sh scripts/check.sh`。

**因此加检查只改 `scripts/check.sh` 一处**，本地与 CI 不可能漂移。

首次推送到 GitHub 后需在仓库设置里补齐三步：

1. **启用 Actions**：Settings → Actions → General → Allow all actions and reusable workflows。
2. **收紧权限**：同页 Workflow permissions 选 *Read repository contents*
   （与 workflow 里的 `permissions: contents: read` 一致）。
3. **设置分支保护**：Settings → Branches → Add branch protection rule，分支名 `main`：
   - 勾选 *Require a pull request before merging*
   - 勾选 *Require status checks to pass before merging*，搜索并勾选 **`test`**

   ⚠️ required status checks 的名称必须与 workflow 的 **job 名**一致。
   `build.yml` 的 job id 是 `test` 且未设 `name:`，因此列表里显示为 `test`。
   **改 job 名之前先改保护设置**，否则 PR 会永远卡在 “Expected — Waiting for
   status to be reported”。

`runs-on` 显式钉 `ubuntu-24.04` 而非 `ubuntu-latest`：跟随 latest 会在 GitHub 切换
镜像时让 CI 行为突变（系统依赖包名可能变化），钉住后升级时机由你决定。

## 5. 落地配置清单

- [x] `AGENTS.md` §2「常用命令」表已填本项目真实命令
- [x] `README.md` / `README.zh-CN.md` 的安装、运行、排查已填
- [x] `ROADMAP.md` 状态总览表含**可判定的**验收标准
- [x] `.github/workflows/build.yml` 调真实门禁（非占位警告）
- [x] `.gitattributes` 已提交（库内与工作区 LF）
- [ ] `scripts/check.sh` 索引模式为 `100755`（提交后用 `git ls-files -s scripts/` 核对）
- [ ] GitHub：启用 Actions、收紧 Workflow permissions
- [ ] GitHub：为 `main` 开启分支保护 + required status checks `test`

## 6. 构建（可选）

构建需要与目标固件匹配的 ImmortalWrt SDK，步骤见
[README.md](../README.md) 的 *Building*。要点：SDK 与源码树必须都在 Linux 文件系统上，
不能放在 `/mnt/` 下 —— WSL2 跨文件系统会让构建极慢或失败。

CI **不**做 SDK 构建：它耗时数分钟且易因网络 flake。一个真编译 PR 会在
[definition-of-done.md](definition-of-done.md) 的「按类型的差异」里被要求本地构建验证。

## 7. 常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| `bad interpreter: /bin/sh^M` | 脚本被检出成 CRLF | 见 §2 行尾 |
| `Permission denied: ./scripts/check.sh` | 索引缺可执行位 | 见 §2 权限位，或直接 `sh scripts/check.sh` |
| CI 里行尾检查失败 | 全局 `autocrlf` 与 `.gitattributes` 冲突 | `git add --renormalize .` 后提交 |
| 改了 job 名后 PR 一直卡在 Expected | required status checks 名称未同步 | 见 §4 第3 步 |
| ACL 检查报某方法缺失 | 改了 `liteportal.uc` 的 methods 表但没改 ACL | 补 ACL；见 [architecture.md](architecture.md) §3 |
| `node --check` 报 LuCI 语法错 | 用了浏览器专属语法 | `--check` 只做解析，报错即语法问题 |
