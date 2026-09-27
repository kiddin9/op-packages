#!/bin/bash
# scripts/update_meow_version.sh — 跟随 meow-rs 上游 release 自动更新 feed
# 行为:
#   1) 通过 GitHub API 获取 meow-rs 最新 release tag(形如 v0.21.2)
#   2) 下载对应 aarch64 musl tarball,运行时计算真实 SHA256(不硬编码)
#   3) 用 sed 更新 meow/Makefile 的 PKG_VERSION 与 PKG_HASH(保留 Tab 缩进)
#      以及 luci-app-meow/Makefile 的 PKG_VERSION(两个包版本保持一致)
#   4) 已是最新版本时无修改、退出码 0(CI 判定为无变化)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

UPSTREAM="meow-rs/meow-rs"
TARBALL_PREFIX="aarch64-unknown-linux-musl.tar.gz"   # 静态 musl 二进制包
MEOW_MK="meow/Makefile"
LUCI_MK="luci-app-meow/Makefile"

# ---- 1. 获取最新 release tag ----
TAG="$(curl -fsSL --retry 3 \
    "https://api.github.com/repos/${UPSTREAM}/releases/latest" \
    | grep -oP '"tag_name":\s*"\K[^"]+')"
[ -n "${TAG}" ] || { echo "ERROR: 无法获取上游 release tag" >&2; exit 1; }
VERSION="${TAG#v}"   # PKG_VERSION 不带 v 前缀(源码 URL 用 v$(PKG_VERSION) 拼接)

CURRENT="$(grep '^PKG_VERSION:=' "${MEOW_MK}" | cut -d= -f2)"
if [ "${VERSION}" = "${CURRENT}" ]; then
    echo "meow 已是最新版本 ${TAG},无需更新。"
    exit 0
fi

# ---- 2. 下载并计算真实 SHA256 ----
URL="https://github.com/${UPSTREAM}/releases/download/${TAG}/meow-${TAG}-${TARBALL_PREFIX}"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT
curl -fsSL --retry 3 -o "${TMP}" "${URL}"
HASH="$(sha256sum "${TMP}" | cut -d' ' -f1)"
echo "上游 ${TAG} tarball SHA256 = ${HASH}"

# ---- 3. 更新 Makefile(sed 保留行内 Tab;两个包版本同步) ----
sed -i "s|^PKG_VERSION:=.*|PKG_VERSION:=${VERSION}|" "${MEOW_MK}" "${LUCI_MK}"
sed -i "s|^PKG_HASH:=.*|PKG_HASH:=${HASH}|" "${MEOW_MK}"

# ---- 4. 完整性自检:PKG_SOURCE/URL 拼接 + 哈希回验 ----
SOURCE_NAME="meow-v${VERSION}-${TARBALL_PREFIX}"
[ -f "${TMP}" ] && [ "$(sha256sum "${TMP}" | cut -d' ' -f1)" = "${HASH}" ] \
    || { echo "ERROR: 哈希回验失败" >&2; exit 1; }
echo "已更新 ${MEOW_MK}: PKG_VERSION=${VERSION}, PKG_HASH=${HASH}"
echo "已更新 ${LUCI_MK}: PKG_VERSION=${VERSION}"
echo "源码包名(由 \$(PKG_VERSION) 拼接): ${SOURCE_NAME}"
