# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org
#
# dnsmasq integration for homeproxy-pro.
#
# homeproxy-pro does not run its own DNS front end: it points dnsmasq at the
# sing-box DNS listener and, in the list-based routing modes, feeds it the
# per-domain `server=` / `nftset=` mappings.  All of that used to live inline
# in /etc/init.d/homeproxy-pro.
#
# Layering note: this is a device-side module.  It calls `log` and, in
# hp_dnsmasq_write_snippets, relies on `config_load` having run (see
# runtime/service.sh's header for the rationale).
#
# Sourced by /etc/init.d/homeproxy-pro.

# hp_dnsmasq_resolve_dir
# Locate the directory dnsmasq reads the homeproxy-pro snippets from and store it
# in the global DNSMASQ_DIR.
#
# The UCI section name of the dnsmasq config is part of
# /tmp/etc/dnsmasq.conf.<name>, but `uci get` cannot return a section name
# (there is no `__name__`), so it is derived from the first `uci show` line.
# Either step can fail on an unusual setup; fall back to the generic
# directory and say so in the log instead of silently writing dnsmasq
# snippets nobody reads.
#
# Called ONCE, at source time.  stop_service deliberately reuses the value
# instead of recomputing it: the directory must be the one the snippets were
# written to, and a second resolution could log the warning twice or pick a
# different directory after a dnsmasq reconfiguration.
hp_dnsmasq_resolve_dir() {
	local dnsmasq_uci_config dnsmasq_conf_dir

	dnsmasq_uci_config="$(uci -q show "dhcp.@dnsmasq[0]" 2>"/dev/null" | head -n1)"
	dnsmasq_uci_config="${dnsmasq_uci_config#*.}"
	dnsmasq_uci_config="${dnsmasq_uci_config%%=*}"

	DNSMASQ_DIR=""
	if [ -n "$dnsmasq_uci_config" ] && [ -f "/tmp/etc/dnsmasq.conf.$dnsmasq_uci_config" ]; then
		dnsmasq_conf_dir="$(awk -F '=' '/^conf-dir=/ {print $2; exit}' "/tmp/etc/dnsmasq.conf.$dnsmasq_uci_config")"
		[ -n "$dnsmasq_conf_dir" ] && DNSMASQ_DIR="$dnsmasq_conf_dir/dnsmasq-homeproxy-pro.d"
	fi

	if [ -z "$DNSMASQ_DIR" ]; then
		log "WARNING: unable to derive the dnsmasq conf-dir (section '${dnsmasq_uci_config:-unknown}'), using /tmp/dnsmasq.d/dnsmasq-homeproxy-pro.d."
		DNSMASQ_DIR="/tmp/dnsmasq.d/dnsmasq-homeproxy-pro.d"
	fi
}

# hp_dnsmasq_has_nftset
# 0 when the running dnsmasq understands `nftset=`.  The base dnsmasq variant
# is built without HAVE_NFTSET, and it does not ignore the directive: it aborts
# with "recompile with HAVE_NFTSET defined", and because the snippet is read
# through conf-dir that abort takes dnsmasq itself down - the LAN loses DNS and
# DHCP, not just the domain routing.  Probe once and degrade instead.
hp_dnsmasq_has_nftset() {
	if [ -z "${HP_DNSMASQ_NFTSET:-}" ]; then
		# Look it up through PATH so the off-target harness can stand in a
		# dnsmasq of either flavour; fall back to the absolute path for an
		# init environment with a bare PATH.
		local bin
		bin="$(command -v dnsmasq 2>"/dev/null" || echo /usr/sbin/dnsmasq)"

		if "$bin" --version 2>"/dev/null" | grep -qw nftset; then
			HP_DNSMASQ_NFTSET=1
		else
			HP_DNSMASQ_NFTSET=0
		fi
	fi

	[ "$HP_DNSMASQ_NFTSET" = "1" ]
}

# hp_dnsmasq_render_snippets <stage-dir> <hp-dir> <routing-mode> <dns-port> <ipv6>
# Render the desired snippet set into <stage-dir>.  Writes nothing outside it,
# restarts nothing: the caller decides whether the result differs from what is
# already installed.
#
# The input list gates are `-s` rather than the original unconditional sed:
# when the resource file is missing the old code produced an empty snippet
# (or a stale one never got removed), which made "is this the same as last
# time" undecidable.  An empty list now means "no snippet for this mode",
# which is also what a fresh install means.
hp_dnsmasq_render_snippets() {
	local stage="$1"
	local hp_dir="$2"
	local routing_mode="$3"
	local dns_port="$4"
	local ipv6="$5"
	local gfw_nftset_v6="" wan_nftset_v6=""
	local nftset_ok=1

	# dns_port comes from `infra`, a section with no UI and no validator, and
	# it is interpolated both into the snippet text and into sed's replacement
	# below.  A value carrying a newline reaches sed as `\n` and becomes a real
	# dnsmasq directive (the generator accepts it too: int() is strtoll-based,
	# so '5333\nlog-queries' is simply 5333 there), and a value with a `/`
	# makes sed fail - while `> "$stage/x.conf"` has already truncated the
	# file, so an empty snippet used to be installed and then cached by the
	# "unchanged" comparison.  Keep the numeric prefix, refuse the rest.
	dns_port="$(printf '%s' "$dns_port" | sed -n 's/^\([0-9]\{1,\}\).*/\1/p')"
	case "$dns_port" in
	''|*[!0-9]*)
		log "Warning: infra.dns_port is not a port (${4:-}); skipping the dnsmasq snippets."
		return 1
		;;
	esac
	if [ "$dns_port" -lt 1 ] || [ "$dns_port" -gt 65535 ]; then
		log "Warning: infra.dns_port=$dns_port is out of range; skipping the dnsmasq snippets."
		return 1
	fi

	hp_dnsmasq_has_nftset || nftset_ok=0

	case "$routing_mode" in
	"bypass_mainland_china"|"custom"|"global")
		cat <<-EOF > "$stage/redirect-dns.conf" || return 1
			no-poll
			no-resolv
			server=127.0.0.1#$dns_port
		EOF
		;;
	"gfwlist")
		if [ -s "$hp_dir/resources/gfw_list.txt" ]; then
			if [ "$nftset_ok" = "1" ]; then
				[ "$ipv6" -eq "0" ] || gfw_nftset_v6=",6#inet#fw4#homeproxy_gfw_list_v6"
				sed -r -e "s/(.*)/server=\/\1\/127.0.0.1#$dns_port\nnftset=\/\1\\/4#inet#fw4#homeproxy_gfw_list_v4$gfw_nftset_v6/g" \
					"$hp_dir/resources/gfw_list.txt" > "$stage/gfw_list.conf" || return 1
			else
				log "Warning: this dnsmasq has no nftset support; gfwlist routing degrades to plain server= entries (no address sets)."
				sed -r -e "s/(.*)/server=\/\1\/127.0.0.1#$dns_port/g" \
					"$hp_dir/resources/gfw_list.txt" > "$stage/gfw_list.conf" || return 1
			fi
		fi
		;;
	"proxy_mainland_china")
		if [ -s "$hp_dir/resources/china_list.txt" ]; then
			sed -r -e "s/(.*)/server=\/\1\/127.0.0.1#$dns_port/g" \
				"$hp_dir/resources/china_list.txt" > "$stage/china_list.conf" || return 1
		fi
		;;
	esac

	if [ "$routing_mode" != "custom" ] && [ -s "$hp_dir/resources/proxy_list.txt" ]; then
		if [ "$nftset_ok" = "1" ]; then
			[ "$ipv6" -eq "0" ] || wan_nftset_v6=",6#inet#fw4#homeproxy_wan_proxy_addr_v6"
			sed -r -e '/^\s*$/d' -e "s/(.*)/server=\/\1\/127.0.0.1#$dns_port\nnftset=\/\1\\/4#inet#fw4#homeproxy_wan_proxy_addr_v4$wan_nftset_v6/g" \
				"$hp_dir/resources/proxy_list.txt" > "$stage/proxy_list.conf" || return 1
		else
			log "Warning: this dnsmasq has no nftset support; the proxy list degrades to plain server= entries."
			sed -r -e '/^\s*$/d' -e "s/(.*)/server=\/\1\/127.0.0.1#$dns_port/g" \
				"$hp_dir/resources/proxy_list.txt" > "$stage/proxy_list.conf" || return 1
		fi
	fi
}

# hp_dnsmasq_dir_differs <stage-dir> <live-dir>
# 0 when the installed snippet set is not exactly the staged one, 1 when it is
# identical.  Compares file names as well as contents, so a snippet that the
# current routing mode no longer produces (but a previous one did) counts as a
# change and gets cleaned up.
hp_dnsmasq_dir_differs() {
	local stage="$1"
	local live="$2"
	local staged installed f

	[ -d "$live" ] || return 0

	staged="$(ls -1 "$stage" 2>"/dev/null" | sort)"
	installed="$(ls -1 "$live" 2>"/dev/null" | sort)"
	[ "$staged" = "$installed" ] || return 0

	for f in $staged; do
		cmp -s "$stage/$f" "$live/$f" || return 0
	done

	return 1
}

# hp_dnsmasq_write_snippets <dns-dir> <hp-dir> <routing-mode>
# Write the include file plus the mode-specific snippet, then restart
# dnsmasq.  Requires config_load (reads ipv6_support and dns_port).
#
# The snippets are rendered into a staging directory first and compared with
# what is installed.  dnsmasq restart drops every client's DNS cache, and the
# list files it feeds on change once a day at most while the routing mode and
# the port stay the same - so the previous unconditional rewrite-and-restart
# flushed the LAN's DNS cache on every reload for no reason.
hp_dnsmasq_write_snippets() {
	local dnsmasq_dir="$1"
	local hp_dir="$2"
	local routing_mode="$3"
	local ipv6_support dns_port
	local include="$dnsmasq_dir/../dnsmasq-homeproxy-pro.conf"
	local stage changed=0

	config_get_bool ipv6_support "config" "ipv6_support" "0"
	config_get dns_port "infra" "dns_port" "5333"

	stage="$(mktemp -d "${TMPDIR:-/tmp}/hp-dnsmasq.XXXXXX")" || {
		log "Warning: failed to create a staging directory for the dnsmasq snippets."
		return 1
	}

	# A refused render (an unusable dns_port, or sed failing) must leave the
	# installed snippet set untouched: the staged directory is discarded, so
	# the caller keeps the snippets that are already in place instead of
	# installing a truncated one.
	if ! hp_dnsmasq_render_snippets "$stage" "$hp_dir" "$routing_mode" "$dns_port" "$ipv6_support"; then
		rm -rf "$stage"
		return 1
	fi

	if [ ! -f "$include" ] || [ "$(cat "$include" 2>"/dev/null")" != "conf-dir=$dnsmasq_dir" ]; then
		changed=1
	fi
	if hp_dnsmasq_dir_differs "$stage" "$dnsmasq_dir"; then
		changed=1
	fi

	if [ "$changed" -eq 0 ]; then
		rm -rf "$stage"
		log "dnsmasq snippets unchanged, skipping the restart."
		return 0
	fi

	mkdir -p "$(dirname "$dnsmasq_dir")" 2>"/dev/null" \
		|| log "Warning: failed to create the dnsmasq conf-dir parent."
	rm -rf "$dnsmasq_dir"
	if ! mv "$stage" "$dnsmasq_dir"; then
		log "Warning: failed to install the dnsmasq snippets into ${dnsmasq_dir}."
		rm -rf "$stage"
		return 1
	fi
	# printf, not `echo -e`: busybox ash honours -e but a POSIX sh does not,
	# and on one the file would start with a literal "-e " and dnsmasq would
	# refuse to parse it.  The file is one line of conf-dir= either way.
	printf 'conf-dir=%s\n' "$dnsmasq_dir" > "$include" \
		|| log "Warning: failed to write the dnsmasq conf-dir file."

	/etc/init.d/dnsmasq restart >"/dev/null" 2>&1 \
		|| log "Warning: failed to restart dnsmasq, DNS-based routing may be stale."
}

# hp_dnsmasq_remove_snippets <dns-dir>
# Remove the include file and the snippet directory, then restart dnsmasq.
# The snippets are removed rather than restored: nothing ever captures the
# pre-existing state, so there is no original to put back.
hp_dnsmasq_remove_snippets() {
	local dnsmasq_dir="$1"
	local include="$dnsmasq_dir/../dnsmasq-homeproxy-pro.conf"

	# Nothing to undo when nothing was written - which is the normal case on a
	# router whose outbound node is 'nil', or one that never started. Removing
	# paths that do not exist is not an error, and restarting dnsmasq for it is
	# pure noise (it drops every client's DNS cache for no reason).
	if [ ! -e "$include" ] && [ ! -d "$dnsmasq_dir" ]; then
		return 0
	fi

	rm -rf "$include" "$dnsmasq_dir"
	/etc/init.d/dnsmasq restart >"/dev/null" 2>&1 \
		|| log "Warning: failed to restart dnsmasq after removing the homeproxy-pro snippets."
}

reload_service() {
	restart
}
