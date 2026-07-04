#!/bin/sh
set -eu

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

grep -q "OC_TESTED_VERSION=\"2026.6.11\"" root/usr/bin/openclaw-env || fail "tested OpenClaw version not pinned"
grep -q "NODE_VERSION_V2=\"22.23.0\"" root/usr/bin/openclaw-env || fail "default Node.js version not pinned"
grep -q "OC_NODE_MIN_VERSION=\"\${OC_NODE_MIN_VERSION:-22.19.0}\"" root/usr/bin/openclaw-env || fail "minimum Node.js version not pinned"
grep -q "oc_assert_node_min_version" root/usr/bin/openclaw-env || fail "Node.js minimum version check missing"
grep -q 'oc_node_version_ge "$from_pkg" "$required"' root/usr/bin/openclaw-env || fail "package Node.js requirement must not lower static minimum"
if grep -q 'v1_tarball' root/usr/bin/openclaw-env; then
	fail "installer must not silently fall back to legacy Node.js tarball"
fi

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

grep -q "opkg install python3-light" luasrc/controller/openclaw.lua || fail "wechat install must auto install python3-light"
grep -q "ensure_openclaw_user" luasrc/controller/openclaw.lua || fail "wechat install must ensure openclaw user"
grep -q "NPM_CONFIG_CACHE" luasrc/controller/openclaw.lua || fail "wechat install must set npm cache"
grep -q "openclaw 用户无法写入微信登录目录" luasrc/controller/openclaw.lua || fail "wechat login writable preflight missing"
grep -q "node_modules/@tencent-weixin/openclaw-weixin" luasrc/controller/openclaw.lua || fail "wechat uninstall must remove npm project plugin"
grep -q "dropChannel(d.plugins.installs)" luasrc/controller/openclaw.lua || fail "wechat uninstall must clean plugin installs"
grep -q "openclaw-weixin" root/etc/init.d/openclaw || fail "weixin channel migration missing"
grep -q "delete d.plugins.entries\\['openclaw-weixin'\\]" root/etc/init.d/openclaw || fail "weixin duplicate entries cleanup missing"
grep -q "npm/projects" root/etc/init.d/openclaw || fail "npm plugin project ownership fix missing"
grep -q "! -path.*npm/projects" root/etc/init.d/openclaw || fail "npm plugin projects should be excluded from openclaw ownership reset"
grep -q "archived-extensions" root/etc/init.d/openclaw || fail "legacy weixin extension archive missing"
grep -q "find_wechat_plugin_dir" luasrc/controller/openclaw.lua || fail "wechat npm plugin detection missing"
grep -q "wechat_register_plugin_cmd" luasrc/controller/openclaw.lua || fail "wechat install must register npm plugin config"
grep -q "plugins.installs\\['openclaw-weixin'\\]" luasrc/controller/openclaw.lua || fail "wechat plugin installPath registration missing"
grep -q "packageName: '@tencent-weixin/openclaw-weixin'" luasrc/controller/openclaw.lua || fail "wechat plugin packageName registration missing"
grep -q "channels\\['openclaw-weixin'\\].enabled = true" luasrc/controller/openclaw.lua || fail "wechat channel enable registration missing"
grep -q "Registered openclaw-weixin npm plugin" luasrc/controller/openclaw.lua || fail "wechat install log must confirm config registration"
grep -q "@tencent-weixin/openclaw-weixin/openclaw.plugin.json" root/usr/share/openclaw/oc-config.sh || fail "oc-config wechat npm detection missing"

grep -q "var url = 'http://'" luasrc/view/openclaw/console.htm || fail "console must force HTTP gateway URL"
grep -q "新窗口打开" luasrc/view/openclaw/console.htm || fail "console must expose a new-window entry"
if grep -q "document.createElement('iframe')" luasrc/view/openclaw/console.htm; then
	fail "console must not embed OpenClaw in an iframe"
fi

grep -q "root/usr/libexec" scripts/build_ipk.sh || fail "ipk script must package shell helpers"
grep -q "root/usr/libexec" scripts/build_run.sh || fail "run script must package shell helpers"

echo "ok"
