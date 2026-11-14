#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# 跑全部离线测试。可在开发机（macOS/Linux）或目标设备（OpenWrt/busybox）上执行：
#   sh tests/run-all.sh

set -u
cd "$(dirname "$0")/.." || exit 1

rc=0
for t in tests/sanitize-test.sh tests/render-test.sh tests/sessions-parse-test.sh; do
	echo "=== $t ==="
	sh "$t" || rc=1
	echo
done

if [ "$rc" -eq 0 ]; then
	echo "全部测试通过"
else
	echo "有测试失败"
fi
exit "$rc"
