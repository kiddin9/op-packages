# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org
#
# Single source of truth for every fw4 chain and set owned by homeproxy.
#
#   * root/etc/homeproxy/scripts/firewall_post.ut declares these objects and
#     decides which of them actually exist for the current proxy mode.
#   * root/etc/init.d/homeproxy flushes and deletes them on stop.
#
# When you add or remove a chain/set in firewall_post.ut, update this list in
# the same commit -- tests/ucode/test_fw4_names.sh compares both sides and
# fails when they drift.
#
# Each object is cleaned up independently: the cleanup loop deletes one at a
# time so that a chain/set which does not exist in the current mode cannot
# abort the whole batch. A single `nft -f` batch is atomic and would roll back
# every preceding command in that case.

HP_FW4_CHAINS="
	homeproxy_output_redir
	homeproxy_redirect
	homeproxy_redirect_proxy
	homeproxy_redirect_proxy_port
	homeproxy_redirect_lanac
	homeproxy_mangle_prerouting
	homeproxy_mangle_output
	homeproxy_mangle_tproxy
	homeproxy_mangle_tproxy_port
	homeproxy_mangle_lanac
	homeproxy_mangle_mark
	homeproxy_mangle_tun
	homeproxy_mangle_tun_mark
"

HP_FW4_SETS="
	homeproxy_local_addr_v4
	homeproxy_local_addr_v6
	homeproxy_gfw_list_v4
	homeproxy_gfw_list_v6
	homeproxy_mainland_addr_v4
	homeproxy_mainland_addr_v6
	homeproxy_wan_proxy_addr_v4
	homeproxy_wan_proxy_addr_v6
	homeproxy_wan_direct_addr_v4
	homeproxy_wan_direct_addr_v6
	homeproxy_routing_port
"
