# 发布版本号改用纯语义化 tag（去掉 `-rN` 后缀）

- 状态：已接受
- 日期：2026-10-16
- 决策者：cocolight

## 背景

在此之前，发版约定（AGENTS.md §9）把 git tag / GitHub Release 与 OpenWrt 的包修订号
绑死：tag 用 `v<PKG_VERSION>-r<PKG_RELEASE>`（如 `v3.0.1-r1`）。实际核对显示，9 个 git
tag、3 个 GitHub Release、以及 CHANGELOG 中除首版外的所有已发布版本头都带 `-rN`。

这带来两个问题：

- 对外版本号不干净：用户与下游看到的是 `v3.0.1-r1`，而非语义化版本期望的 `v3.0.1`；
- `-rN` 把两件事混在一起 —— OpenWrt 的**包修订号**（`PKG_RELEASE`，包文件名离不开它）
  与项目**对外发布标识**（git tag / Release），后者本可自由定义。

注意：OpenWrt 包名恒为 `PKG_VERSION-rPKG_RELEASE`（如 `luci-app-portal-3.0.1-r1`），
这是包管理器不可改的命名，`.apk` / `.ipk` 文件名永远带 `-rN`。要改的只是**对外标识**，
不是包名。

## 决策

对外版本号改用纯语义化版本，规则如下（自下一版 `v3.0.2` 起生效，已发布的
`v3.0.1-r1` 等保留不变，不回改写历史）：

- `PKG_VERSION` 变化（semver 升级）：tag 与 release title 均为 `v<PKG_VERSION>`
  （如 `v3.0.2`）；
- 仅升 `PKG_RELEASE`、不改 `PKG_VERSION` 的纯打包重发：tag 与 release title 为
  `v<PKG_VERSION>+<PKG_RELEASE>`（如 `v3.0.1+2`），用 semver 构建元数据而非 `-rN`；
  不新建 CHANGELOG 段落，只在对应 `[<PKG_VERSION>]` 段下注明「PKG_RELEASE → N
  （仅打包修正）」并回传 `.apk` 资产；
- `CHANGELOG.md` 的 `[Unreleased]` 改名为 `[<PKG_VERSION>] - 日期`（不带 v、不带
  `-r` / `+N`），顶部补空 `[Unreleased]`；
- `Makefile` 的 `PKG_VERSION` / `PKG_RELEASE` 仍照常填写，仅用于生成 OpenWrt 包名。

## 后果

- 正面：对外版本号回归语义化（`v3.0.1`），与用户/下游预期一致；`-rN` 歧义消除 ——
  包修订号留在 Makefile 与包名里，tag 只表达语义化版本；纯打包重发有独立可寻的
  tag（`v3.0.1+2`），且不会污染 CHANGELOG 主版本头。
- 负面（明确承认）：一个语义化版本下可能对应多个 tag（`v3.0.1` 与 `v3.0.1+2`），
  需要约定「`+N` 仅用于无用户可见变更的打包重发」，否则易乱；构建元数据 `+N` 在
  semver 比较中被视为等价（仅作构建信息），依赖 tag 排序的工具需另行处理。
- 未变：`PKG_RELEASE` 仍是 OpenWrt 包升级判别的关键（同 `PKG_VERSION` 下靠它区分
  新包），须照常递增；门禁仍是 `scripts/check.sh` 一处。

## 备选方案

- **保留 `v<PKG_VERSION>-r<PKG_RELEASE>`（即现状）**：不选。正是要解决的「对外版本号
  带 `-r`」问题，且与语义化版本预期冲突。
- **纯 `v<PKG_VERSION>`，纯打包重发不建新 tag、只回传资产**：不选。用户明确希望重发
  仍有独立可寻的 tag，故采用 `+N` 构建元数据而非完全不标记。
- **删除/重建已发布的 `v3.0.1-r1` 为 `v3.0.1`**：不选。破坏性，会断开现有 `.apk` 下载
  引用并改写已发布历史；保留历史、新约定从下一版起更稳妥。
