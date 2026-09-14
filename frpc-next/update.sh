#!/bin/bash

# 自动更新 OpenWrt frpc-next 包的版本和 Hash
# 依赖: curl, grep, sed, sha256sum (或 shasum)

set -e

PKG_DIR=$(cd "$(dirname "$0")"; pwd)
MAKEFILE="$PKG_DIR/Makefile"

if [ ! -f "$MAKEFILE" ]; then
    echo "错误: 找不到 Makefile 文件 ($MAKEFILE)"
    exit 1
fi

# 1. 获取当前本地版本
CURRENT_VERSION=$(grep 'PKG_VERSION:=' "$MAKEFILE" | cut -d'=' -f2 | tr -d ' ')
echo "当前本地版本: $CURRENT_VERSION"

# 2. 获取 GitHub 上的最新版本号
LATEST_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')

if [ -z "$LATEST_VERSION" ]; then
    echo "错误: 无法从 GitHub 获取最新版本号。"
    exit 1
fi

echo "GitHub 最新版本: $LATEST_VERSION"

# 3. 比较版本
if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
    echo "版本已经是最新，无需更新。"
    exit 0
fi

echo "发现新版本! 正在准备更新..."

# 4. 更新 Makefile
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/PKG_VERSION:=.*/PKG_VERSION:=$LATEST_VERSION/" "$MAKEFILE"
else
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$LATEST_VERSION/" "$MAKEFILE"
fi

echo "Makefile 更新成功: $CURRENT_VERSION -> $LATEST_VERSION (Binary Mode)"
