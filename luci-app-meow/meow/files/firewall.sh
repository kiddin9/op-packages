#!/bin/sh
# fw4 回调入口: 由 /etc/config/firewall 的 include (type=script) 触发

MEOW_NFT=/etc/meow/gateway.nft

# 只有在“服务已启用 + 已开网关模式 + 进程在跑 + 规则文件已生成”
# 时才装载规则，
# 其余情况一律清表 —— 否则规则会指向一个没人监听的端口，
# 直接黑洞整个 LAN。
meow_rules_allowed() {
	[ "$(uci -q get meow.main.enabled)" = "1" ] || return 1
	[ "$(uci -q get meow.main.gateway)" = "1" ] || return 1
	[ -f "$MEOW_NFT" ] || return 1
	/etc/init.d/meow running 2>/dev/null || return 1

	return 0
}

if meow_rules_allowed; then
	nft -f "$MEOW_NFT" 2>/dev/null || logger -t meow-firewall "nft rules load failed"
else
	nft delete table inet meow_gateway 2>/dev/null
fi
