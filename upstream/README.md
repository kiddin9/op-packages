# upstream/ — 上游源码快照（vendor）

本目录是 **`meow-rs/meow-rs` 仓库 `openwrt/` 目录的原样快照**，由
`.github/workflows/sync-upstream.yml` 调用 `scripts/sync-upstream.sh` 自动刷新。

- `PIN` — 快照对应的上游 commit
- `OPENWRT_TREE` — 快照对应的上游 `openwrt/` tree SHA；同步脚本以此判断 `openwrt/` 是否真正发生变化
- `SNAPSHOT` — 上游仓库 / ref / commit / tree / 提交时间等同步元数据
- `openwrt/` — 上游 `openwrt/` 目录原样内容（含 `meow/files/`、`luci-app-meow/`、
  `build-ipk.sh`、`docker/side-router.sh`）

## 约定

**不要手工修改本目录下的任何文件。** 上游一有 `openwrt/` 更新，这里会被整体刷新。
需要本地改动请写成 `patches/*.patch`，然后通过 `scripts/apply-patches.sh` 重新生成
`meow/` 与 `luci-app-meow/`。
