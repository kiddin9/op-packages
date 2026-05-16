#!/bin/sh
set -eu

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

grep -q "OC_TESTED_VERSION=\"2026.5.12\"" root/usr/bin/openclaw-env || fail "tested OpenClaw version not pinned"
grep -q "oc_assert_node_min_version" root/usr/bin/openclaw-env || fail "Node.js minimum version check missing"

grep -q "wechat.htm" Makefile || fail "Makefile must install wechat.htm"
grep -q "luci-app-openclaw.json" Makefile || fail "Makefile must install rpcd ACL"
if grep -q "openclaw.zh-cn.lmo" Makefile; then
	fail "main package must not install openclaw.zh-cn.lmo"
fi

if grep -q 'export HOME="$OC_DATA"' root/etc/profile.d/openclaw.sh; then
	fail "profile must not export HOME globally"
fi
grep -q 'HOME="$OC_DATA"' root/etc/profile.d/openclaw.sh || fail "openclaw wrapper must inject HOME locally"

if grep -q "chmod -R 777" luasrc/controller/openclaw.lua; then
	fail "uninstall path must not chmod -R 777"
fi
grep -q "is_safe_openclaw_root" luasrc/controller/openclaw.lua || fail "uninstall safety check missing"
grep -q "local q_install_path = shellquote(install_path)" luasrc/controller/openclaw.lua || fail "uninstall rm must shellquote install_path"
grep -q "rm -rf \" .. q_install_path" luasrc/controller/openclaw.lua || fail "uninstall rm must use quoted install_path"

grep -q "command -v python3" luasrc/controller/openclaw.lua || fail "wechat install must check python3"
grep -q "ensure_openclaw_user" luasrc/controller/openclaw.lua || fail "wechat install must ensure openclaw user"
grep -q "NPM_CONFIG_CACHE" luasrc/controller/openclaw.lua || fail "wechat install must set npm cache"
grep -q "openclaw-weixin" root/etc/init.d/openclaw || fail "weixin channel migration missing"

grep -q "var url = 'http://'" luasrc/view/openclaw/console.htm || fail "console must force HTTP gateway URL"
grep -q "existing.src" luasrc/view/openclaw/console.htm || fail "console iframe must refresh token URL"

grep -q "root/usr/libexec" scripts/build_ipk.sh || fail "ipk script must package shell helpers"
grep -q "root/usr/libexec" scripts/build_run.sh || fail "run script must package shell helpers"

echo "ok"
