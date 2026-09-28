#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_file() {
	[ -f "$ROOT_DIR/$1" ] || fail "missing required package file: $1"
}

assert_contains() {
	needle="$1"
	file="$2"
	grep -F -- "$needle" "$ROOT_DIR/$file" >/dev/null || fail "$file should contain: $needle"
}

assert_po_entry() {
	expected_msgid="$1"
	expected_msgstr="$2"
	file="$3"
	case "$file" in
		/*) po_file="$file" ;;
		*) po_file="$ROOT_DIR/$file" ;;
	esac

	awk -v expected_msgid="$expected_msgid" -v expected_msgstr="$expected_msgstr" '
		function quoted_value(line, value) {
			value = line
			sub(/^[^"]*"/, "", value)
			sub(/"$/, "", value)
			return value
		}
		function finish_entry() {
			if (has_msgid && has_msgstr && msgid == expected_msgid && msgstr == expected_msgstr)
				matched = 1
			msgid = ""
			msgstr = ""
			active_field = ""
			has_msgid = 0
			has_msgstr = 0
		}
		/^[[:space:]]*$/ {
			finish_entry()
			next
		}
		/^msgid "/ {
			if (has_msgid || has_msgstr)
				finish_entry()
			msgid = quoted_value($0)
			has_msgid = 1
			active_field = "msgid"
			next
		}
		/^msgstr "/ {
			msgstr = quoted_value($0)
			has_msgstr = 1
			active_field = "msgstr"
			next
		}
		/^"/ {
			if (active_field == "msgid")
				msgid = msgid quoted_value($0)
			else if (active_field == "msgstr")
				msgstr = msgstr quoted_value($0)
			next
		}
		{
			active_field = ""
		}
		END {
			finish_entry()
			exit !matched
		}
	' "$po_file" || fail "$file should contain PO entry: msgid $expected_msgid with msgstr $expected_msgstr"
}

assert_po_entry_mutation_test() {
	mutated_po="$(mktemp "$ROOT_DIR/tests/package_release_test.XXXXXX")"
	trap 'rm -f "$mutated_po"' 0 HUP INT TERM
	awk '
		$0 == "msgstr \"已开启，4 条绕过规则已生效\"" { print "msgstr \"已关闭，Tailscale 流量将由 OpenClash 处理\""; next }
		$0 == "msgstr \"已关闭，Tailscale 流量将由 OpenClash 处理\"" { print "msgstr \"已开启，4 条绕过规则已生效\""; next }
		{ print }
	' "$ROOT_DIR/po/zh_Hans/tailscale.po" > "$mutated_po"

	if (assert_po_entry "Enabled; 4 bypass rules are active" "已开启，4 条绕过规则已生效" "$mutated_po") >/dev/null 2>&1; then
		fail "assert_po_entry must reject swapped PO translations"
	fi

	rm -f "$mutated_po"
}

assert_not_contains() {
	needle="$1"
	file="$2"
	if grep -F -- "$needle" "$ROOT_DIR/$file" >/dev/null; then
		fail "$file should not contain: $needle"
	fi
}

assert_jq() {
	filter="$1"
	file="$2"
	message="$3"
	jq -e "$filter" "$ROOT_DIR/$file" >/dev/null || fail "$message"
}

line_number() {
	needle="$1"
	file="$2"
	grep -nF -- "$needle" "$ROOT_DIR/$file" | head -n 1 | cut -d: -f1
}

assert_before() {
	first="$1"
	second="$2"
	file="$3"
	first_line="$(line_number "$first" "$file")"
	second_line="$(line_number "$second" "$file")"
	[ -n "$first_line" ] || fail "$file should contain: $first"
	[ -n "$second_line" ] || fail "$file should contain: $second"
	[ "$first_line" -lt "$second_line" ] || fail "$file should place '$first' before '$second'"
}

assert_peer_pagination_after_table() {
	file="$1"
	awk '
		/return E\('\''div'\'', \{ class: '\''cbi-map'\'' \}/ { in_return = 1 }
		in_return && /E\('\''table'\'', \{/ { table_line = NR }
		in_return && /^[[:space:]]*paginationBox[[:space:]]*$/ { pagination_line = NR }
		END {
			if (table_line && pagination_line && table_line < pagination_line)
				exit 0
			exit 1
		}
	' "$ROOT_DIR/$file" || fail "$file should render peer pagination below the peer table"
}

assert_not_exists() {
	[ ! -e "$ROOT_DIR/$1" ] || fail "$1 should not exist"
}

assert_no_active_config_list() {
	option="$1"
	file="$2"
	if grep -E "^[[:space:]]*list[[:space:]]+$option([[:space:]]|$)" "$ROOT_DIR/$file" >/dev/null; then
		fail "$file must not ship an active $option default"
	fi
}

assert_release_permissions() {
	file="$1"
	awk '
		/^permissions:$/ {
			global_permissions = 1
			next
		}
		global_permissions && /^  contents: / {
			global_contents = $2
			if ($2 == "write") {
				write_count++
				write_outside_release = 1
			}
			global_permissions = 0
			next
		}
		/^jobs:$/ {
			in_jobs = 1
			next
		}
		in_jobs && /^  [A-Za-z0-9_-]+:$/ {
			job = $1
			sub(/:$/, "", job)
			job_permissions = 0
			next
		}
		in_jobs && /^    permissions:$/ {
			job_permissions = 1
			next
		}
		in_jobs && job_permissions && /^      contents: / {
			job_contents[job] = $2
			if ($2 == "write") {
				write_count++
				if (job != "release")
					write_outside_release = 1
			}
			job_permissions = 0
			next
		}
		END {
			if (global_contents != "read")
				exit 1
			if (job_contents["release"] != "write")
				exit 1
			if (job_contents["test"] == "write" || job_contents["build"] == "write")
				exit 1
			if (write_count != 1 || write_outside_release)
				exit 1
		}
	' "$ROOT_DIR/$file" || fail "$file should grant contents: read globally and contents: write only to the release job"
}

grep -Eq '^PKG_VERSION:=[0-9]+\.[0-9]+\.[0-9]+$' "$ROOT_DIR/Makefile" || \
	fail 'Makefile should declare a semantic package version'
assert_file .github/workflows/release.yml
assert_release_permissions .github/workflows/release.yml
assert_contains "tags:" .github/workflows/release.yml
assert_contains "v*" .github/workflows/release.yml
assert_contains "pull_request:" .github/workflows/release.yml
assert_contains "branches:" .github/workflows/release.yml
assert_contains "main" .github/workflows/release.yml
assert_contains "test:" .github/workflows/release.yml
assert_contains "for test in tests/*_test.sh" .github/workflows/release.yml
assert_contains "for test in tests/*_test.js" .github/workflows/release.yml
assert_contains "for file in root/etc/init.d/tailscale" .github/workflows/release.yml
assert_contains "for file in htdocs/luci-static/resources/view/tailscale/*.js tests/*_test.js" .github/workflows/release.yml
assert_contains "sh -n" .github/workflows/release.yml
assert_contains "node --check" .github/workflows/release.yml
assert_contains "jq -e" .github/workflows/release.yml
assert_contains "msgfmt --check-format" .github/workflows/release.yml
assert_contains "needs: test" .github/workflows/release.yml
assert_contains "sdk_arch: x86_64-24.10.5@sha256:" .github/workflows/release.yml
assert_contains "sdk_arch: x86_64@sha256:" .github/workflows/release.yml
assert_contains "if: startsWith(github.ref, 'refs/tags/')" .github/workflows/release.yml
assert_contains "luci-app-tailscale_*.ipk" .github/workflows/release.yml
assert_contains "luci-app-tailscale-*.apk" .github/workflows/release.yml

assert_file htdocs/luci-static/resources/view/tailscale/setting.js
assert_file tests/setting_preflight_test.js
assert_contains "refreshAdguardPreflightStatus" htdocs/luci-static/resources/view/tailscale/setting.js
assert_file root/etc/config/tailscale
assert_no_active_config_list adguard_default_upstreams root/etc/config/tailscale
assert_no_active_config_list adguard_tailnet_upstreams root/etc/config/tailscale
assert_not_contains "litata.com" root/etc/config/tailscale
assert_not_contains "litata.tailnet" root/etc/config/tailscale
assert_file root/etc/init.d/tailscale
assert_file root/usr/sbin/tailscale_helper
assert_file root/usr/sbin/tailscale_keepalive
assert_file root/usr/sbin/tailscale_adguard_dns_switch
assert_file root/usr/sbin/tailscale_openclash_bypass
assert_file root/etc/config/tailscale_openclash
assert_file root/etc/init.d/tailscale-openclash-bypass
assert_file root/etc/config/tailscale_policy_routing
assert_file root/etc/init.d/tailscale-policy-routing
assert_file root/etc/hotplug.d/iface/98-tailscale-policy-routing
assert_file root/usr/sbin/tailscale_policy_routing
assert_file root/usr/sbin/tailscale_peer_probe
assert_file root/usr/sbin/tailscale_secrets
assert_file root/lib/upgrade/keep.d/luci-app-tailscale
assert_file root/usr/libexec/rpcd/luci.tailscale
assert_file root/usr/share/rpcd/acl.d/luci-app-tailscale.json
assert_contains "Peer probe" root/usr/sbin/tailscale_peer_probe
assert_contains "LUCI_DEPENDS:=+tailscale +jshn +curl +jq +flock" Makefile
assert_contains "allow_wan_direct" root/etc/config/tailscale
assert_contains "wan_direct_zones" root/etc/config/tailscale
assert_contains "allow_wan_direct" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "wan_direct_zones" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "Allow WAN Direct" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "WAN Direct Source Zones" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "ALLOW_WAN_DIRECT" root/etc/init.d/tailscale
assert_contains "WAN_DIRECT_ZONES" root/etc/init.d/tailscale
assert_contains "TAILSCALE_PORT" root/etc/init.d/tailscale
assert_contains "firewall.ts_wan_direct" root/usr/sbin/tailscale_helper
assert_contains "Allow-Tailscale-WAN-" root/usr/sbin/tailscale_helper
assert_contains "WAN_DIRECT_ZONES" root/usr/sbin/tailscale_helper
assert_contains 'firewall.$section.src=$zone' root/usr/sbin/tailscale_helper
assert_contains 'firewall.$section.proto=udp' root/usr/sbin/tailscale_helper
assert_contains 'firewall.$section.dest_port=$port' root/usr/sbin/tailscale_helper
assert_contains 'firewall.$section.target=ACCEPT' root/usr/sbin/tailscale_helper
assert_not_contains "tailscale_openclash_bypass" root/usr/sbin/tailscale_helper
assert_not_contains "openclash_custom_firewall_rules.sh" root/usr/sbin/tailscale_helper
assert_contains 'POLICY_ROUTING_HELPER' root/usr/sbin/tailscale_helper
assert_contains '"$POLICY_ROUTING_HELPER" sync' root/usr/sbin/tailscale_helper
assert_not_contains '/etc/config/firewall' root/usr/sbin/tailscale_policy_routing
assert_not_contains 'uci commit firewall' root/usr/sbin/tailscale_policy_routing
assert_not_contains '/etc/init.d/firewall' root/usr/sbin/tailscale_policy_routing
assert_not_contains '/etc/init.d/openclash' root/usr/sbin/tailscale_policy_routing
assert_not_contains '"$MWAN3_INIT" reload' root/usr/sbin/tailscale_policy_routing
assert_not_contains '"$MWAN3_INIT" restart' root/usr/sbin/tailscale_policy_routing
assert_not_contains '"$MWAN3_INIT" start' root/usr/sbin/tailscale_policy_routing
assert_not_contains '"$MWAN3_INIT" stop' root/usr/sbin/tailscale_policy_routing
assert_not_contains 'mwan3 restart' root/usr/sbin/tailscale_policy_routing
assert_contains 'network.ts_mwan3_table52' root/usr/sbin/tailscale_policy_routing
assert_contains "PRIORITY='1000'" root/usr/sbin/tailscale_policy_routing
assert_contains "TABLE='52'" root/usr/sbin/tailscale_policy_routing
assert_not_contains "/etc/config/firewall" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "uci commit firewall" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "/etc/init.d/firewall" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "/etc/init.d/openclash reload" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "/etc/init.d/openclash restart" root/usr/sbin/tailscale_openclash_bypass
assert_contains 'msgid "OpenClash"' po/templates/tailscale.pot
assert_contains 'msgid "Protect Tailscale Traffic (Bypass OpenClash)"' po/templates/tailscale.pot
assert_contains 'msgid "Status"' po/templates/tailscale.pot
assert_contains 'msgid "Checking ..."' po/templates/tailscale.pot
assert_contains 'msgid "Enabled; 4 bypass rules are active"' po/templates/tailscale.pot
assert_contains 'msgid "Enabled; waiting for OpenClash nftables chains"' po/templates/tailscale.pot
assert_contains 'msgid "Disabled; Tailscale traffic is handled by OpenClash"' po/templates/tailscale.pot
assert_contains 'msgid "OpenClash is not installed; bypass is not required"' po/templates/tailscale.pot
assert_contains 'msgid "Unsupported; firewall4/nftables is required"' po/templates/tailscale.pot
assert_contains 'msgid "Configuration error"' po/templates/tailscale.pot
assert_contains 'msgid "Unknown status"' po/templates/tailscale.pot
assert_contains 'msgid "Unable to read OpenClash bypass status."' po/templates/tailscale.pot
assert_contains 'msgid "Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash."' po/templates/tailscale.pot
assert_contains 'msgid "Prioritize Tailscale Routes Before mwan3"' po/templates/tailscale.pot
assert_contains 'msgid "Policy Routing Status"' po/templates/tailscale.pot
assert_contains 'msgid "Enabled; mwan3 is not installed"' po/templates/tailscale.pot
assert_contains 'msgid "Enabled; no earlier mwan3-marked rule was detected"' po/templates/tailscale.pot
assert_contains 'msgid "Enabled; Tailscale routes take precedence over mwan3"' po/templates/tailscale.pot
assert_contains 'msgid "Unable to read Tailscale policy-routing status."' po/templates/tailscale.pot
assert_po_entry "OpenClash" "OpenClash" po/zh_Hans/tailscale.po
assert_po_entry "Protect Tailscale Traffic (Bypass OpenClash)" "保护 Tailscale 流量（绕过 OpenClash）" po/zh_Hans/tailscale.po
assert_po_entry "Status" "状态" po/zh_Hans/tailscale.po
assert_po_entry "Checking ..." "检查中..." po/zh_Hans/tailscale.po
assert_po_entry "Enabled; 4 bypass rules are active" "已开启，4 条绕过规则已生效" po/zh_Hans/tailscale.po
assert_po_entry "Enabled; waiting for OpenClash nftables chains" "已开启，正在等待 OpenClash 创建 nftables 链" po/zh_Hans/tailscale.po
assert_po_entry "Disabled; Tailscale traffic is handled by OpenClash" "已关闭，Tailscale 流量将由 OpenClash 处理" po/zh_Hans/tailscale.po
assert_po_entry "OpenClash is not installed; bypass is not required" "未安装 OpenClash，无需绕过" po/zh_Hans/tailscale.po
assert_po_entry "Unsupported; firewall4/nftables is required" "当前系统不支持，仅支持 firewall4/nftables" po/zh_Hans/tailscale.po
assert_po_entry "Configuration error" "配置错误" po/zh_Hans/tailscale.po
assert_po_entry "Unknown status" "未知状态" po/zh_Hans/tailscale.po
assert_po_entry "Unable to read OpenClash bypass status." "无法读取 OpenClash 绕过状态。" po/zh_Hans/tailscale.po
assert_po_entry "Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash." "开启后，Tailscale 控制连接、直连通信、Tailnet DNS 和跨子网流量不会被 OpenClash 接管。关闭后，这些流量将重新经过 OpenClash，节点在线、点对点直连、跨子网访问和 Tailnet DNS 解析不再受本功能保护；如果 OpenClash 规则接管或重定向这些流量，可能导致节点掉线、直连退化为 DERP、跨子网访问或 Tailnet DNS 中断。使用 OpenClash 时必须保持开启。" po/zh_Hans/tailscale.po
assert_po_entry "Prioritize Tailscale Routes Before mwan3" "优先让 Tailscale 路由先于 mwan3" po/zh_Hans/tailscale.po
assert_po_entry "Policy Routing Status" "策略路由状态" po/zh_Hans/tailscale.po
assert_po_entry "Enabled; mwan3 is not installed" "已开启，未安装 mwan3" po/zh_Hans/tailscale.po
assert_po_entry "Enabled; no earlier mwan3-marked rule was detected" "已开启，未检测到更早的 mwan3 标记规则" po/zh_Hans/tailscale.po
assert_po_entry "Enabled; Tailscale routes take precedence over mwan3" "已开启，Tailscale 路由优先于 mwan3" po/zh_Hans/tailscale.po
assert_po_entry "Unable to read Tailscale policy-routing status." "无法读取 Tailscale 策略路由状态。" po/zh_Hans/tailscale.po
assert_po_entry "OpenClash" "OpenClash" po/zh_Hant/tailscale.po
assert_po_entry "Protect Tailscale Traffic (Bypass OpenClash)" "保護 Tailscale 流量（繞過 OpenClash）" po/zh_Hant/tailscale.po
assert_po_entry "Status" "狀態" po/zh_Hant/tailscale.po
assert_po_entry "Checking ..." "檢查中..." po/zh_Hant/tailscale.po
assert_po_entry "Enabled; 4 bypass rules are active" "已開啟，4 條繞過規則已生效" po/zh_Hant/tailscale.po
assert_po_entry "Enabled; waiting for OpenClash nftables chains" "已開啟，正在等待 OpenClash 建立 nftables 鏈" po/zh_Hant/tailscale.po
assert_po_entry "Disabled; Tailscale traffic is handled by OpenClash" "已關閉，Tailscale 流量將由 OpenClash 處理" po/zh_Hant/tailscale.po
assert_po_entry "OpenClash is not installed; bypass is not required" "未安裝 OpenClash，無需繞過" po/zh_Hant/tailscale.po
assert_po_entry "Unsupported; firewall4/nftables is required" "目前系統不支援，僅支援 firewall4/nftables" po/zh_Hant/tailscale.po
assert_po_entry "Configuration error" "設定錯誤" po/zh_Hant/tailscale.po
assert_po_entry "Unknown status" "未知狀態" po/zh_Hant/tailscale.po
assert_po_entry "Unable to read OpenClash bypass status." "無法讀取 OpenClash 繞過狀態。" po/zh_Hant/tailscale.po
assert_po_entry "Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash." "開啟後，Tailscale 控制連線、直連通訊、Tailnet DNS 和跨子網流量不會被 OpenClash 接管。關閉後，這些流量將重新經過 OpenClash，節點在線、點對點直連、跨子網存取和 Tailnet DNS 解析不再受本功能保護；如果 OpenClash 規則接管或重新導向這些流量，可能導致節點離線、直連退化為 DERP、跨子網存取或 Tailnet DNS 中斷。使用 OpenClash 時必須保持開啟。" po/zh_Hant/tailscale.po
assert_po_entry "Prioritize Tailscale Routes Before mwan3" "優先讓 Tailscale 路由先於 mwan3" po/zh_Hant/tailscale.po
assert_po_entry "Policy Routing Status" "策略路由狀態" po/zh_Hant/tailscale.po
assert_po_entry "Enabled; mwan3 is not installed" "已開啟，未安裝 mwan3" po/zh_Hant/tailscale.po
assert_po_entry "Enabled; no earlier mwan3-marked rule was detected" "已開啟，未偵測到較早的 mwan3 標記規則" po/zh_Hant/tailscale.po
assert_po_entry "Enabled; Tailscale routes take precedence over mwan3" "已開啟，Tailscale 路由優先於 mwan3" po/zh_Hant/tailscale.po
assert_po_entry "Unable to read Tailscale policy-routing status." "無法讀取 Tailscale 策略路由狀態。" po/zh_Hant/tailscale.po
assert_po_entry_mutation_test
assert_contains 'msgid "Allow WAN Direct"' po/templates/tailscale.pot
assert_contains 'msgid "WAN Direct Source Zones"' po/templates/tailscale.pot
assert_contains 'msgid "Allow WAN Direct"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "允许 WAN 直连"' po/zh_Hans/tailscale.po
assert_contains 'msgid "WAN Direct Source Zones"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "WAN 直连来源区域"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Allow WAN Direct"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "允許 WAN 直連"' po/zh_Hant/tailscale.po
assert_contains 'msgid "WAN Direct Source Zones"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "WAN 直連來源區域"' po/zh_Hant/tailscale.po
assert_contains '"$JQ_BIN" -nc' root/usr/sbin/tailscale_peer_probe
assert_contains "--argjson ok" root/usr/sbin/tailscale_peer_probe
assert_contains "ping --c=1 --timeout=2s" root/usr/sbin/tailscale_peer_probe
assert_not_contains "json_escape()" root/usr/sbin/tailscale_peer_probe
assert_file root/etc/uci-defaults/40_luci-tailscale
assert_file tests/tailscale_legacy_adguard_migration_test.sh
assert_contains '"admin/vpn/tailscale/peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_contains '"title": "Peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_contains '"path": "tailscale/peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_before '"admin/vpn/tailscale/interface"' '"admin/vpn/tailscale/peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_before '"admin/vpn/tailscale/peers"' '"admin/vpn/tailscale/log"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_contains 'msgid "Peers"' po/templates/tailscale.pot
assert_contains 'msgid "Peers"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "对端列表"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Peers"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "對端列表"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Tailscale Peers"' po/templates/tailscale.pot
assert_contains 'msgid "Tailscale Peers"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "Tailscale 对端"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Tailscale Peers"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "Tailscale 對端"' po/zh_Hant/tailscale.po
assert_contains 'msgid "View all peers and manually probe whether traffic is direct or relayed through DERP."' po/templates/tailscale.pot
assert_contains 'msgid "View all peers and manually probe whether traffic is direct or relayed through DERP."' po/zh_Hans/tailscale.po
assert_contains 'msgstr "查看所有对端，并手动探测流量是直连还是通过 DERP 中继。"' po/zh_Hans/tailscale.po
assert_contains 'msgid "View all peers and manually probe whether traffic is direct or relayed through DERP."' po/zh_Hant/tailscale.po
assert_contains 'msgstr "查看所有對端，並手動探測流量是直連還是透過 DERP 中繼。"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Unable to load Tailscale peer status"' po/templates/tailscale.pot
assert_contains 'msgid "Unable to load Tailscale peer status"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "无法加载 Tailscale 对端状态。"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Unable to load Tailscale peer status"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "無法載入 Tailscale 對端狀態。"' po/zh_Hant/tailscale.po
assert_contains 'msgid "No peers match the selected filter."' po/templates/tailscale.pot
assert_contains 'msgid "No peers match the selected filter."' po/zh_Hans/tailscale.po
assert_contains 'msgstr "没有对端符合所选筛选条件。"' po/zh_Hans/tailscale.po
assert_contains 'msgid "No peers match the selected filter."' po/zh_Hant/tailscale.po
assert_contains 'msgstr "沒有對端符合所選篩選條件。"' po/zh_Hant/tailscale.po
assert_contains "No peers found" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains 'msgid "No peers found"' po/templates/tailscale.pot
assert_contains 'msgid "No peers found"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "没有找到对端"' po/zh_Hans/tailscale.po
assert_contains 'msgid "No peers found"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "沒有找到對端"' po/zh_Hant/tailscale.po
assert_contains 'msgid "No probe target available"' po/templates/tailscale.pot
assert_contains 'msgid "No probe target available"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "没有可用探测目标。"' po/zh_Hans/tailscale.po
assert_contains 'msgid "No probe target available"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "沒有可用探測目標。"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Probe failed"' po/templates/tailscale.pot
assert_contains 'msgid "Probe failed"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "探测失败"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Probe failed"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "探測失敗"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Not probed"' po/templates/tailscale.pot
assert_contains 'msgid "Not probed"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "未探测"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Not probed"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "未探測"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Probing..."' po/templates/tailscale.pot
assert_contains 'msgid "Probing..."' po/zh_Hans/tailscale.po
assert_contains 'msgstr "探测中..."' po/zh_Hans/tailscale.po
assert_contains 'msgid "Probing..."' po/zh_Hant/tailscale.po
assert_contains 'msgstr "探測中..."' po/zh_Hant/tailscale.po
assert_contains 'msgid "Probe"' po/templates/tailscale.pot
assert_contains 'msgid "Probe"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "探测"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Probe"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "探測"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Direct"' po/templates/tailscale.pot
assert_contains 'msgid "Direct"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "直连"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Direct"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "直連"' po/zh_Hant/tailscale.po
assert_contains 'msgid "DERP"' po/templates/tailscale.pot
assert_contains 'msgid "DERP"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "DERP 中继"' po/zh_Hans/tailscale.po
assert_contains 'msgid "DERP"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "DERP 中繼"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Failed"' po/templates/tailscale.pot
assert_contains 'msgid "Failed"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "失败"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Failed"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "失敗"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Unknown"' po/templates/tailscale.pot
assert_contains 'msgid "Unknown"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "未知"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Unknown"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "未知"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Filter"' po/templates/tailscale.pot
assert_contains 'msgid "Filter"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "筛选"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Filter"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "篩選"' po/zh_Hant/tailscale.po
assert_contains 'msgid "All"' po/templates/tailscale.pot
assert_contains 'msgid "All"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "全部"' po/zh_Hans/tailscale.po
assert_contains 'msgid "All"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "全部"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Online"' po/templates/tailscale.pot
assert_contains 'msgid "Online"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "在线"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Online"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "在線"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Offline"' po/templates/tailscale.pot
assert_contains 'msgid "Offline"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "离线"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Offline"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "離線"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Name"' po/templates/tailscale.pot
assert_contains 'msgid "Name"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "名称"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Name"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "名稱"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Tailnet IP"' po/templates/tailscale.pot
assert_contains 'msgid "Tailnet IP"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "Tailnet IP"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Tailnet IP"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "Tailnet IP"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Last Seen"' po/templates/tailscale.pot
assert_contains 'msgid "Last Seen"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "最后在线"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Last Seen"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "最後在線"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Role"' po/templates/tailscale.pot
assert_contains 'msgid "Role"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "角色"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Role"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "角色"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Exit node"' po/templates/tailscale.pot
assert_contains 'msgid "Exit node"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "出口节点"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Exit node"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "出口節點"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Advertising subnets"' po/templates/tailscale.pot
assert_contains 'msgid "Advertising subnets"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "发布网段"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Advertising subnets"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "發布網段"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Advertised Subnets"' po/templates/tailscale.pot
assert_contains 'msgid "Advertised Subnets"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "已发布网段"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Advertised Subnets"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "已發布網段"' po/zh_Hant/tailscale.po

assert_contains "Peer Keepalive" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "AdGuard DNS" htdocs/luci-static/resources/view/tailscale/setting.js
assert_before "AdGuard API URL" "_adguard_dns_status" htdocs/luci-static/resources/view/tailscale/setting.js
assert_before "AdGuard Username" "_adguard_dns_status" htdocs/luci-static/resources/view/tailscale/setting.js
assert_before "AdGuard Password" "_adguard_dns_status" htdocs/luci-static/resources/view/tailscale/setting.js
assert_before "_adguard_dns_status" "Enable AdGuard DNS Auto Switch" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "ADGUARD_PREFLIGHT_CHECKS" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "window.setTimeout(refreshAdguardPreflightStatus" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains 'msgid "Checking ..."' po/templates/tailscale.pot
assert_po_entry "Checking ..." "检查中..." po/zh_Hans/tailscale.po
assert_po_entry "Checking ..." "檢查中..." po/zh_Hant/tailscale.po
assert_not_contains "AdGuard DNS auto switch cannot be enabled until every environment status check passes." htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "keepalivePeerAliases" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "shortDnsName" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "hasSubnetRoutes" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "No subnet routes" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "s.tab('keepalive'" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "form.Value.extend" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "KeepalivePeersValue, 'keepalive_peers'" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "keepalive-peer-list" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "Only peers advertising subnet routes are shown" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "keepalive-peer-row" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "max-width:680px;width:100%" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "grid-template-columns:minmax(320px,1fr) minmax(140px,260px)" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "min-height:42px" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "keepalive-peer-main" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "keepalive-peer-check" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "display:flex;align-items:center;gap:10px;min-width:0" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "display:flex;align-items:center;justify-content:center;line-height:0;flex:0 0 24px" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "max-width:260px" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "max-width:820px" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "grid-template-columns:24px minmax(160px,1fr) auto" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "grid-template-columns:24px minmax(180px,1fr) minmax(140px,260px)" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "padding:10px 12px" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "grid-template-columns:24px 1fr" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "form.AbstractValue, 'keepalive_peers'" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "form.MultiValue, 'keepalive_peers'" htdocs/luci-static/resources/view/tailscale/setting.js
assert_file htdocs/luci-static/resources/view/tailscale/peers.js
assert_file tests/peers_pagination_test.js
assert_contains "Tailscale Peers" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "filterMode" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "buildPeerGroups" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "paginatePeerGroups" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "PEER_PAGE_SIZE_DEFAULT = 25" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "PEER_PAGE_SIZE_OPTIONS" htdocs/luci-static/resources/view/tailscale/peers.js
assert_peer_pagination_after_table htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "peer-pagination-summary" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "peer-pagination-controls" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "justify-content:flex-end" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "margin-left:auto" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "split oversized groups into dedicated pages" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "pageSize === 0" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "pageIndex = 0" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "peer.userKey" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "peer-group-header" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "peer-group-title" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "border-left:4px solid #64748b" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "font-size:16px" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "peer.online ? '' : 'opacity:0.62'" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Offline peers cannot be probed" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "type: 'button'" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "disabled: probing || !peer.online ? 'disabled' : null" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "preventDefault" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "stopPropagation" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "window.scrollTo" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "querySelector('.main-right')" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "restoreScrollState" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "scrollElement.scrollTop" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "renderRows(true)" htdocs/luci-static/resources/view/tailscale/peers.js
assert_not_contains "disabled: probing," htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "PROBE_MAX_ATTEMPTS = 5" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "PROBE_RETRY_DELAY_MS" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Continuing probe %d/%d" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "%d probes; direct connection not established" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains 'msgid "Continuing probe %d/%d"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "继续探测 %d/%d"' po/zh_Hans/tailscale.po
assert_contains 'msgid "%d probes; direct connection not established"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "%d 次探测后仍未建立直连"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Continuing probe %d/%d"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "繼續探測 %d/%d"' po/zh_Hant/tailscale.po
assert_contains 'msgid "%d probes; direct connection not established"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "%d 次探測後仍未建立直連"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Items per page"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "每页数量"' po/zh_Hans/tailscale.po
assert_contains 'msgid "All peers"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "全部对端"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Showing %d-%d of %d peers"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "显示第 %d-%d 台，共 %d 台"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Page %d / %d"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "第 %d / %d 页"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Previous"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "上一页"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Next"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "下一页"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Offline peers cannot be probed"' po/templates/tailscale.pot
assert_contains 'msgid "Offline peers cannot be probed"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "离线设备不可探测"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Offline peers cannot be probed"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "離線設備不可探測"' po/zh_Hant/tailscale.po
assert_contains 'msgid "Unknown user"' po/templates/tailscale.pot
assert_contains 'msgid "Unknown user"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "未知用户"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Unknown user"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "未知使用者"' po/zh_Hant/tailscale.po
assert_contains "peer.isSelf" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Current device" htdocs/luci-static/resources/view/tailscale/peers.js
assert_po_entry "Current device" "当前设备" po/zh_Hans/tailscale.po
assert_po_entry "Current device" "目前設備" po/zh_Hant/tailscale.po
assert_contains "Advertising subnets" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "tailscale_peer_probe" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Probe" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "DERP" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Direct" htdocs/luci-static/resources/view/tailscale/peers.js
assert_not_contains "Probe all" htdocs/luci-static/resources/view/tailscale/peers.js
assert_file tests/log_view_test.js
assert_contains "formatLogLines" htdocs/luci-static/resources/view/tailscale/log.js
assert_contains "formatLogError" htdocs/luci-static/resources/view/tailscale/log.js
assert_contains "Log is empty." po/zh_Hans/tailscale.po
assert_contains "日志为空。" po/zh_Hans/tailscale.po
assert_contains "logread command not found" po/zh_Hans/tailscale.po
assert_contains "未找到 logread 命令" po/zh_Hans/tailscale.po
assert_contains 'msgid "Keepalive"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "保活"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Peer Keepalive"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "启用"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Peer Keepalive"' po/zh_Hant/tailscale.po
assert_contains 'msgstr "啟用"' po/zh_Hant/tailscale.po
assert_not_contains 'msgstr "对端保活"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Subnets"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "子网"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Only peers advertising subnet routes are shown. Selected peers are periodically pinged to keep cross-subnet paths active."' po/zh_Hans/tailscale.po
assert_contains 'msgstr "仅显示对端也发布了网段的设备；选中的设备会被定时 Tailscale ping，用于保持跨网段路径活跃。"' po/zh_Hans/tailscale.po
assert_not_contains "子网路由" po/zh_Hans/tailscale.po
assert_not_contains "子網路由" po/zh_Hant/tailscale.po
assert_contains 'msgid "AdGuard DNS"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "AdGuard DNS"' po/zh_Hans/tailscale.po
assert_contains 'msgid "AdGuard Username"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "AdGuard 用户名"' po/zh_Hans/tailscale.po
assert_contains "Expected Internal IPs" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains 'msgid "Expected Internal IPs"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "预期内网 IP"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "啟用 AdGuard DNS 自動切換前至少需要填寫一個預期內網 IP。"' po/zh_Hant/tailscale.po
assert_not_contains "Expected Health IPs" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "预期健康 IP" po/zh_Hans/tailscale.po
assert_not_contains "預期健康 IP" po/zh_Hant/tailscale.po
assert_contains "100.100.100.100" root/usr/sbin/tailscale_adguard_dns_switch
assert_contains "100.100.100.100" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "'subnet_routes'" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "Subnet Routes" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "No Available Subnet Routes" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "config_get subnet_routes" root/etc/init.d/tailscale
assert_not_contains 'SUBNET_ROUTES="$subnet_routes"' root/etc/init.d/tailscale
assert_not_contains "list subnet_routes" root/etc/config/tailscale
assert_not_contains 'msgid "Subnet Routes"' po/templates/tailscale.pot
assert_not_contains 'msgid "No Available Subnet Routes"' po/templates/tailscale.pot
assert_not_contains 'msgid "Subnet Routes"' po/zh_Hans/tailscale.po
assert_not_contains 'msgid "No Available Subnet Routes"' po/zh_Hans/tailscale.po
assert_not_contains 'msgid "Subnet Routes"' po/zh_Hant/tailscale.po
assert_not_contains 'msgid "No Available Subnet Routes"' po/zh_Hant/tailscale.po
assert_not_contains "Tailscale Accept DNS" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "Accept DNS must be enabled before enabling AdGuard DNS auto switch." htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains 'msgid "Tailscale Accept DNS"' po/zh_Hans/tailscale.po
assert_not_contains 'msgid "Accept DNS must be enabled before enabling AdGuard DNS auto switch."' po/zh_Hans/tailscale.po
assert_contains "PROGA=/usr/sbin/tailscale_adguard_dns_switch" root/etc/init.d/tailscale
assert_contains 'tailscale_adguard_dns "$cfg"' root/etc/init.d/tailscale
assert_contains "service_stopped()" root/etc/init.d/tailscale
assert_contains "config_foreach tailscale_adguard_dns_apply_down 'tailscale'" root/etc/init.d/tailscale
assert_contains "--apply-profile down" root/etc/init.d/tailscale
assert_not_contains "adguard_health_dns" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "Health Check DNS Server" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "adguard_health_dns" root/etc/config/tailscale
assert_not_contains "adguard_clear_cache" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "Clear AdGuard Cache After Switch" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "adguard_clear_cache" root/etc/config/tailscale
assert_not_contains 'msgid "Health Check DNS Server"' po/zh_Hans/tailscale.po
assert_not_contains 'msgid "Clear AdGuard Cache After Switch"' po/zh_Hans/tailscale.po
assert_contains "placeholder = hasAdguardPassword ? _('Configured') : ''" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "placeholder = hasAuthKey ? _('Configured') : ''" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "Leave blank to keep the existing AdGuard password; enter a new value to replace it." htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains "Used once for first-time enrollment or explicit re-enrollment, then removed after a successful connection. Leave blank for normal restarts." htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "placeholder = hasAdguardPassword ? _('Configured; leave blank to keep existing value.') : ''" htdocs/luci-static/resources/view/tailscale/setting.js
assert_not_contains "placeholder = hasAuthKey ? _('Configured; leave blank to keep existing value.') : ''" htdocs/luci-static/resources/view/tailscale/setting.js
assert_contains 'msgid "Configured"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "已配置"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Leave blank to keep the existing AdGuard password; enter a new value to replace it."' po/zh_Hans/tailscale.po
assert_contains 'msgstr "留空则保留现有 AdGuard 密码；填写新值则覆盖。"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Used once for first-time enrollment or explicit re-enrollment, then removed after a successful connection. Leave blank for normal restarts."' po/zh_Hans/tailscale.po
assert_contains 'msgstr "仅用于首次注册或明确重新注册，连接成功后自动删除；正常重启请留空。"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Failed to stage protected credentials."' po/zh_Hans/tailscale.po
assert_contains 'msgstr "暂存受保护凭证失败。"' po/zh_Hans/tailscale.po
assert_contains '"luci.tailscale": [ "adguard_preflight", "set_secrets" ]' root/usr/share/rpcd/acl.d/luci-app-tailscale.json
acl_file=root/usr/share/rpcd/acl.d/luci-app-tailscale.json
assert_jq '.["luci-app-tailscale"].read.uci == ["tailscale", "tailscale_openclash", "tailscale_policy_routing"]' "$acl_file" 'ACL read UCI access must include the isolated policy-routing package'
assert_jq '.["luci-app-tailscale"].write.uci == ["tailscale", "tailscale_openclash", "tailscale_policy_routing"]' "$acl_file" 'ACL write UCI access must include the isolated policy-routing package'
assert_jq '.["luci-app-tailscale"].read.ubus["luci.tailscale"] == ["secret_status", "openclash_bypass_status", "policy_routing_status"]' "$acl_file" 'ACL read ubus access must include the policy-routing status method'
assert_jq '.["luci-app-tailscale"].read.file | has("/usr/sbin/tailscale_openclash_bypass") | not' "$acl_file" 'ACL must not grant file-exec access to the OpenClash helper'
assert_not_contains '"set_secret"' root/usr/share/rpcd/acl.d/luci-app-tailscale.json
assert_not_contains '"luci.tailscale": [ "adguard_preflight" ]' root/usr/share/rpcd/acl.d/luci-app-tailscale.json
assert_not_contains "/usr/sbin/tailscale_adguard_dns_switch --preflight" root/usr/share/rpcd/acl.d/luci-app-tailscale.json
assert_contains '"/usr/sbin/tailscale_peer_probe": [ "exec" ]' root/usr/share/rpcd/acl.d/luci-app-tailscale.json
assert_not_contains "config_get authkey" root/etc/init.d/tailscale
assert_not_contains "get authkey" root/etc/init.d/tailscale
assert_not_contains "--authkey=" root/etc/init.d/tailscale
assert_contains 'procd_set_param command $PROG --run' root/etc/init.d/tailscale
assert_contains 'TAILSCALE_SECRETS_BIN' root/usr/sbin/tailscale_helper
assert_not_contains 'TAILSCALE_INIT' root/usr/sbin/tailscale_helper
assert_contains 'Unsupported tailscale_helper mode' root/usr/sbin/tailscale_helper
assert_contains '"$TAILSCALE_SECRETS_BIN" migrate' root/etc/uci-defaults/40_luci-tailscale
assert_contains 'cleanup_legacy_adguard_dns_service' root/etc/uci-defaults/40_luci-tailscale
assert_contains 'tailscale-adguard-dns.disabled' root/etc/uci-defaults/40_luci-tailscale
assert_before 'cleanup_legacy_adguard_dns_service' '"$TAILSCALE_SECRETS_BIN" migrate' root/etc/uci-defaults/40_luci-tailscale
assert_contains 'disable_legacy_hotplug' Makefile
assert_contains '40-tailscale.disabled' Makefile
assert_contains 'rm -f "$${legacy_hotplug}" || chmod 000 "$${legacy_hotplug}" || return 1' Makefile
assert_before 'disable_legacy_hotplug || exit 1' '[ -f /etc/config/tailscale ] || exit 0' Makefile
assert_not_contains 'ucitrack.@tailscale' root/etc/uci-defaults/40_luci-tailscale
assert_not_contains 'uci -q batch' root/etc/uci-defaults/40_luci-tailscale
assert_contains 'openclash_bypass_enabled="$("$UCI_BIN" -q get tailscale_openclash.settings.enabled' root/etc/uci-defaults/40_luci-tailscale
assert_contains '"$OPENCLASH_BYPASS_INIT" enable' root/etc/uci-defaults/40_luci-tailscale
assert_contains '"$OPENCLASH_BYPASS_INIT" start' root/etc/uci-defaults/40_luci-tailscale
assert_before '"$TAILSCALE_SECRETS_BIN" migrate' '"$OPENCLASH_BYPASS_INIT" enable' root/etc/uci-defaults/40_luci-tailscale
assert_before '"$OPENCLASH_BYPASS_INIT" enable' '"$OPENCLASH_BYPASS_INIT" start' root/etc/uci-defaults/40_luci-tailscale
assert_contains 'POLICY_ROUTING_INIT=' root/etc/uci-defaults/40_luci-tailscale
assert_contains '"$POLICY_ROUTING_INIT" enable' root/etc/uci-defaults/40_luci-tailscale
assert_contains '"$POLICY_ROUTING_INIT" start' root/etc/uci-defaults/40_luci-tailscale
assert_not_contains "option adguard_password" root/etc/config/tailscale
assert_not_contains "option authkey" root/etc/config/tailscale
assert_contains "--cleanup-managed-firewall" root/etc/init.d/tailscale
assert_contains "TAILSCALE_INTERNAL_RELOAD" root/etc/init.d/tailscale
assert_not_contains "RELOAD_MARKER_FILE" root/etc/init.d/tailscale
assert_contains 'activate "$secrets_ref"' root/etc/init.d/tailscale
assert_contains "Package/luci-app-tailscale/prerm" Makefile
assert_contains "Package/luci-app-tailscale/preinst" Makefile
assert_not_contains "Package/luci-app-tailscale/conffiles" Makefile
assert_contains "/etc/config/tailscale" Makefile
assert_contains "/etc/config/tailscale_openclash" Makefile
assert_contains "/etc/config/tailscale_policy_routing" Makefile
assert_not_contains "Package/luci-app-tailscale/postinst" Makefile
assert_contains "state_dir=/etc/.luci-app-tailscale-upgrade" Makefile
assert_contains 'state_pending="$${state_dir}.pending"' Makefile
assert_contains 'clear_state_dir()' Makefile
assert_contains "cp /etc/config/tailscale \"\$\${state_pending}/tailscale\"" Makefile
assert_not_contains "/tmp/luci-app-tailscale-upgrade" Makefile
assert_contains "restore_upgrade_config" root/etc/uci-defaults/40_luci-tailscale
assert_contains "cleanup_upgrade_state()" root/etc/uci-defaults/40_luci-tailscale
assert_contains 'UPGRADE_STATE_DIR="${UPGRADE_STATE_DIR:-/etc/.luci-app-tailscale-upgrade}"' root/etc/uci-defaults/40_luci-tailscale
assert_contains "chmod 700 \"\$\${state_pending}\"" Makefile
assert_before "restore_upgrade_config" '"$TAILSCALE_SECRETS_BIN" migrate' root/etc/uci-defaults/40_luci-tailscale
assert_not_contains "/etc/init.d/tailscale-openclash-bypass enable" Makefile
assert_not_contains "/etc/init.d/tailscale-openclash-bypass start" Makefile
assert_contains '/etc/init.d/tailscale-openclash-bypass disable >/dev/null 2>&1 || true' Makefile
assert_contains '[ -z "$${IPKG_INSTROOT}" ] && [ -x /usr/sbin/tailscale_openclash_bypass ]; then' Makefile
assert_contains "/usr/sbin/tailscale_openclash_bypass cleanup >/dev/null 2>&1 || true" Makefile
assert_contains "/usr/sbin/tailscale_policy_routing cleanup >/dev/null 2>&1 || exit 1" Makefile
assert_contains 'case "$${2:-}" in' Makefile
assert_contains 'remove|[0-9]*) ;;' Makefile
assert_contains 'case "$${1:-}" in' Makefile
assert_contains '"$${cleanup_dir}/tailscale_openclash.absent" "$${cleanup_dir}/tailscale_policy_routing"' Makefile
assert_contains '"$${cleanup_dir}/.complete"' Makefile
assert_not_contains 'APK_SCRIPT' Makefile
assert_before "/usr/sbin/tailscale_openclash_bypass cleanup" "/etc/init.d/tailscale stop" Makefile
assert_before "/etc/init.d/tailscale-openclash-bypass disable" "/etc/init.d/tailscale stop" Makefile
assert_before "/usr/sbin/tailscale_policy_routing cleanup" "/etc/init.d/tailscale stop" Makefile
assert_before "/etc/init.d/tailscale-policy-routing disable" "/etc/init.d/tailscale stop" Makefile
assert_contains "/etc/init.d/tailscale stop" Makefile
assert_not_contains "/etc/init.d/tailscale stop >/dev/null 2>&1 || true" Makefile
assert_not_contains "grep -b" root/usr/sbin/tailscale_openclash_bypass
assert_contains '"$PROG" sync' root/etc/init.d/tailscale-openclash-bypass
assert_not_contains "config_get_bool" root/etc/init.d/tailscale-openclash-bypass
assert_contains 'Status states: `active`, `waiting`, `disabled`, `absent`, `unsupported`, and `error`.' README.md
assert_contains 'Cleanup removes only the managed hook block and the four `luci-app-tailscale:` rules.' README.md

assert_not_exists root/lib/netifd/proto/tailscale.sh
assert_not_exists htdocs/luci-static/resources/protocol/tailscale.js
assert_not_exists root/etc/init.d/tailscale-adguard-dns
assert_not_exists root/etc/hotplug.d/iface/40-tailscale

echo "package release tests passed"

reload_service() {
	restart
}
