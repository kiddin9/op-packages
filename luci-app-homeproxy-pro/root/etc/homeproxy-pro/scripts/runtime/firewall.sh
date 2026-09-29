# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org
#
# fw4 integration for homeproxy-pro.
#
# homeproxy-pro owns a fixed set of nft chains and sets inside the `fw4` table.
# They are created by the rendered template (firewall_post.ut, applied by
# `fw4 reload`) and torn down one object at a time on stop.  All of that used
# to live inline in /etc/init.d/homeproxy-pro.
#
# Layering note: this is a device-side module.  It calls `log` and, for the
# teardown, requires the HP_FW4_CHAINS / HP_FW4_SETS inventory to be in scope
# (root/etc/homeproxy-pro/scripts/fw4_names.sh, sourced by init.d).
#
# Sourced by /etc/init.d/homeproxy-pro.

# hp_restore_upnp_mappings
# fw4 reload rewrites the whole ruleset, which drops the miniupnpd mappings,
# so ask miniupnpd to reinstall them - but only when it is actually enabled
# and running.
hp_restore_upnp_mappings() {
	[ -x /etc/init.d/miniupnpd ] && /etc/init.d/miniupnpd enabled && /etc/init.d/miniupnpd running \
		&& /etc/init.d/miniupnpd restart >"/dev/null" 2>&1
}

# hp_firewall_apply <hp-dir> <run-dir> <client-enabled>
# Run the pre-script, render the post-template for the client side, reload
# fw4 and restore the upnp mappings.  <client-enabled> is "1" when a client
# outbound exists; the post-template is client-only.
hp_firewall_apply() {
	local hp_dir="$1"
	local run_dir="$2"
	local client_enabled="$3"

	local failed=0

	# Truncate the include fragments first.  firewall_pre.uc only writes them
	# when it has something to put in them, so a start that produces no
	# forward/input rules would leave the previous run's files in place and fw4
	# would keep loading them.  teardown already truncates for the same reason.
	: > "$run_dir/fw4_forward.nft"
	: > "$run_dir/fw4_input.nft"

	ucode "$hp_dir/scripts/firewall_pre.uc" 2>"/dev/null" \
		|| { log "Error: firewall pre-script failed."; failed=1; }

	if [ "$client_enabled" = "1" ]; then
		# Render to a temp file and install it only on success.  The old
		# `> "$run_dir/fw4_post.nft"` truncated the very file fw4 is about to
		# include, so a failed render left fw4 loading an empty ruleset.
		if utpl -S "$hp_dir/scripts/firewall_post.ut" > "$run_dir/fw4_post.nft.new" 2>"/dev/null"; then
			mv -f "$run_dir/fw4_post.nft.new" "$run_dir/fw4_post.nft"
		else
			rm -f "$run_dir/fw4_post.nft.new"
			log "Error: firewall post-script failed."
			failed=1
		fi
	fi

	fw4 reload >"/dev/null" 2>&1 \
		|| { log "Error: fw4 reload failed."; failed=1; }

	# The return value has to describe this function, not whatever
	# hp_restore_upnp_mappings happened to return last.
	hp_restore_upnp_mappings

	return "$failed"
}

# hp_firewall_teardown <run-dir> [keep-pre]
# Flush and delete every fw4 object homeproxy-pro owns.  Deleting one at a time
# matters: `nft -f` batches are atomic, so a single object that does not
# exist in the current proxy mode would roll back the rest.
#
# "keep-pre" leaves fw4_forward.nft / fw4_input.nft alone.  Those two are the
# firewall_pre.uc fragments - the server's inbound accepts and the TUN
# forwards - and they are not what black-holes the LAN when the client fails.
# A failed client has to release the redirect/tproxy layer without closing
# the server's ports, so that path passes keep-pre; stop_service does not.
hp_firewall_teardown() {
	local run_dir="$1"
	local keep_pre="${2:-}"
	local fw4_name

	for fw4_name in $HP_FW4_CHAINS; do
		nft flush chain inet fw4 "$fw4_name" 2>"/dev/null"
		nft delete chain inet fw4 "$fw4_name" 2>"/dev/null"
	done
	for fw4_name in $HP_FW4_SETS; do
		nft flush set inet fw4 "$fw4_name" 2>"/dev/null"
		nft delete set inet fw4 "$fw4_name" 2>"/dev/null"
	done

	if [ "$keep_pre" != "keep-pre" ]; then
		: > "$run_dir/fw4_forward.nft"
		: > "$run_dir/fw4_input.nft"
	fi
	: > "$run_dir/fw4_post.nft"

	# Stop-time fw4 reload is best-effort on purpose: every homeproxy-pro-owned
	# chain and set has already been flushed and deleted above, so the
	# live ruleset no longer references them. A reload that succeeds here
	# also re-loads /etc/config/firewall; a reload that fails leaves the
	# rest of the user's ruleset untouched, which is the safer outcome -
	# logging a Warning used to suggest the stop had lost something when
	# in fact nothing homeproxy-pro-owned was left to lose.
	fw4 reload >"/dev/null" 2>&1 || true
	hp_restore_upnp_mappings
}

reload_service() {
	restart
}
