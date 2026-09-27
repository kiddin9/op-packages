#!/bin/sh
# push-github.sh —— 把 luci-app-dnsguard 推到 GitHub（dellzou/luci-app-dnsguard）
#
# 为什么单独写这个脚本：WorkBuddy 的 GitHub 连接器（Copilot 作用域）**没有建仓权限**
# （create_repository 返回 403 Resource not accessible by integration），
# 而 GitHub 也不会因为一次 push 就自动建仓。所以第一次必须先在网页建一个**空仓库**。
#
# 用法：
#   sh push-github.sh            # 预检 + 推送
#
# 前置：先在 https://github.com/new 建仓库
#   Repository name : luci-app-dnsguard
#   Public / Private: 自选（建议 Public，和 luci-app-routerreport 一致）
#   ⚠️ 不要勾 Add a README / .gitignore / license —— 勾了就会和本地历史冲突

set -u
REPO="git@github.com:dellzou/luci-app-dnsguard.git"
DIR=$(cd "$(dirname "$0")" && pwd)

cd "$DIR" || exit 1

echo "== 1) SSH 鉴权 =="
ssh -o ConnectTimeout=10 -T git@github.com 2>&1 | grep -q 'Hi dellzou' \
	&& echo "   OK  已认证为 dellzou" \
	|| { echo "   FAIL 密钥未生效（期望 'Hi dellzou!'）"; exit 1; }

echo "== 2) 远端仓库是否存在 =="
if git ls-remote "$REPO" >/dev/null 2>&1; then
	echo "   OK  远端可达"
else
	echo "   FAIL 仓库还不存在。请先到 https://github.com/new 建一个空仓库："
	echo "        name = luci-app-dnsguard（不要勾 README/.gitignore/license）"
	exit 1
fi

echo "== 3) 本地待推内容 =="
git log --oneline | head -5
echo "   tag: $(git tag -l | tr '\n' ' ')"
echo "   待推提交数: $(git rev-list --count HEAD)  文件数: $(git ls-files | wc -l)"

echo "== 4) 推送 =="
git branch -M main 2>/dev/null || true
git remote set-url origin "$REPO" 2>/dev/null || git remote add origin "$REPO"
git push -u origin main
git push origin --tags

echo
echo "完成：https://github.com/dellzou/luci-app-dnsguard"
