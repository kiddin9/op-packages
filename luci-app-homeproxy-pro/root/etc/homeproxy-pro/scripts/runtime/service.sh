# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org
#
# Service-side runtime helpers for homeproxy-pro.
#
# These are the device-side orchestration pieces that used to be inlined in
# /etc/init.d/homeproxy-pro: the sing-box version gate, the auto-update cron
# entry, the runtime-file preparation, the procd instance registrations and
# the "generate -> known-good" transaction that start_service runs for each
# side.
#
# Layering note: unlike
# runtime/config.sh and runtime/health.sh - which are deliberately pure and
# only take explicit paths - the extracted modules are device-side
# by nature.  They call `log`, `config_get` and `procd_*`, so a caller must
# have run `config_load` and must be inside a procd init context.  That is
# exactly why they were moved out of init.d and not turned into pure helpers.
#
# Sourced by /etc/init.d/homeproxy-pro.

# hp_require_singbox
# Refuse to start on a sing-box older than 1.14: the generated configuration
# uses 1.14-only fields, and an older binary would reject it at run time
# instead of failing here.  Returns 1 (and logs) when unusable.
#
# `sing-box` is looked up through PATH, exactly as the previous init script
# did - it is deliberately not PROG, so a PATH mismatch between the two is
# not silently introduced by this refactor.
hp_require_singbox() {
	local sb_ver sb_major sb_minor

	sb_ver="$(sing-box version -n 2>/dev/null)"
	if [ -z "$sb_ver" ]; then
		log "Error: cannot detect sing-box version, abort."
		return 1
	fi

	sb_major="${sb_ver%%.*}"
	sb_minor="${sb_ver#*.}"
	sb_minor="${sb_minor%%.*}"

	if [ "$sb_major" -lt 1 ] || { [ "$sb_major" -eq 1 ] && [ "$sb_minor" -lt 14 ]; }; then
		log "Error: sing-box >= 1.14.0 required, found ${sb_ver}."
		return 1
	fi

	return 0
}

# hp_require_ucode
# Refuse to start when the installed ucode cannot load this package's own
# modules at all.  Returns 1 (and logs) when the interpreter is unusable.
#
# Why a check and not a documented requirement: ucode resolves `import` when a
# module is LOADED, not when a function is called, and homeproxy-pro.uc imports
#
#     import { access, lstat, mkdtemp, open, rmdir, unlink } from 'fs';
#
# so on a ucode whose fs module has no `mkdtemp` export, *every* entry point
# into this package dies with the same one-line reference error at load time -
# the install-time migration (etc/uci-defaults/luci-homeproxy-pro-migration),
# both config generators, and the LuCI RPC module that imports homeproxy-pro.uc
# too.  The first of those to run is the migration, which is why the only
# thing an affected user ever saw was a stack trace during `apk add` /
# `opkg install` (issue #3) and never a sentence naming the requirement.
#
# `mkdtemp` entered ucode on 2025-11-07 (lib/fs.c, "fs: add mkdtemp() method
# for creating temporary directories").  It replaced `mkstemp`, which every
# older ucode does export - so this is a hard floor, not a preference, and no
# ImmortalWrt 24.10 release can satisfy it.
#
# The probe is `ucode -e`, the same form tests/ucode/run.sh uses for its
# module syntax checks.  Its own output is not discarded: if this ucode is so
# old that even the probe fails, that is exactly the information the operator
# needs, so the error goes into the log next to the requirement.
hp_require_ucode() {
	local probe_out

	probe_out="$(ucode -e "import * as fs from 'fs'; exit('mkdtemp' in keys(fs) ? 0 : 1)" 2>&1)" && return 0

	log "Error: this build needs a ucode whose fs module exports mkdtemp (added in ucode 2025-11-07, shipped in ImmortalWrt 25.12); the installed ucode does not provide it."
	log "Error: every script in this package imports it, so the service, the config generators and the LuCI RPC all fail to load on this firmware."
	[ -n "$probe_out" ] && log "Error: the capability check itself reported: ${probe_out}"
	log "Hint: this firmware's ucode is too old for this package; ImmortalWrt 25.12 or newer is required."

	return 1
}

# hp_crontab_drop <crontab> [marker]
# Remove the cron entries tagged <marker> from <crontab>.
#
# Not `sed -i`: the bare `-i` form is a busybox/GNU extension, and on a host with
# BSD sed it fails ("invalid command code"), which silently left the stale entry
# behind with only a warning in the log.  Editing through a temporary file
# behaves identically on busybox, GNU and BSD sed, and it is what lets this
# module be exercised off-target at all
# (tests/runtime/test_runtime_extraction.sh stages and drives it).
#
# The marker is a parameter because there are two independent entries now: the
# resource lists and the subscriptions.  A shared marker would let dropping one
# take the other with it.
hp_crontab_drop() {
	local crontab="$1"
	local marker="${2:-${CONF}_autosetup}"
	local tmp="${crontab}.hp-new"

	sed "/#${marker}/d" "$crontab" > "$tmp" 2>"/dev/null" || { rm -f "$tmp"; return 1; }
	mv -f "$tmp" "$crontab" 2>"/dev/null" || { rm -f "$tmp"; return 1; }

	# mv replaces the *file*, not its contents: the temporary was created by the
	# shell (0666 & ~umask = 0644) while procd creates /etc/crontabs/root as
	# 0600, so every stop/start left the root crontab world-readable - verified
	# on the device (0600 after boot, 0644 after one reload).  Only root needs
	# to read it (crond runs as root), and a root crontab can hold other jobs'
	# secrets, so set the mode rather than inherit it - which also repairs a
	# file an older version already loosened.
	chmod 600 "$crontab" 2>"/dev/null"

	return 0
}

# hp_sync_resource_cron <hour>
# Install the resource-list update cron entry.  Unconditional.
#
# The resource lists were previously refreshed by the same cron line as the
# subscription update, behind the *subscription's* auto_update switch.  Two
# unrelated things behind one switch, and the consequence was silent: a router
# with subscription auto-update off kept a months-old china_ip4.txt, and with it
# a months-old `homeproxy_mainland_addr_v4` nft set - the firewall was deciding
# "mainland or not" from a list nobody was maintaining.  The subscription switch
# says nothing about the user wanting stale routing data, so the two are now
# scheduled independently.
#
# The hour is a constant rather than a setting.  This is a maintenance job with
# nothing to configure, and adding an option for it is exactly the kind of
# switch that ends up defaulted and never touched.  Two hours earlier than the
# subscription default (2) so the two runs of uclient-fetch do not collide.
#
# The entry runs update_resources_cron.sh, which reloads the service only when a
# list actually changed - so a day where the upstream lists did not move costs
# one round of requests and no interruption.
HP_RESOURCE_CRON_HOUR=3
hp_sync_resource_cron() {
	hp_crontab_drop "/etc/crontabs/root" "${CONF}_resource_cron" \
		|| log "Warning: failed to drop the previous resource-update cron entry."
	printf '0 %s * * * %s/scripts/update_resources_cron.sh #%s_resource_cron\n' \
		"$HP_RESOURCE_CRON_HOUR" "$HP_DIR" "$CONF" >> "/etc/crontabs/root" \
		|| log "Warning: failed to install the resource-update cron entry."
	/etc/init.d/cron restart >"/dev/null" 2>&1 || log "Warning: failed to restart cron."
}

# hp_sync_autoupdate_cron <enabled> <hour>
# Install (or drop) the subscription auto-update cron entry.  <enabled> is a
# config_get_bool result; the entry is only touched when it is "1".
hp_sync_autoupdate_cron() {
	local auto_update="$1"
	local auto_update_time="$2"

	[ "$auto_update" = "1" ] || return 0

	# auto_update_time comes from UCI, which anything on the LAN can write, and
	# it used to be interpolated into a root crontab line verbatim: a value
	# like '2 * * * * root echo pwned #' appends a second job.  Validate it
	# before the line exists, and write it with printf rather than `echo -e`
	# so no backslash sequence is interpreted either.
	case "$auto_update_time" in
	''|*[!0-9]*)
		log "Warning: auto_update_time='$auto_update_time' is not an hour of the day, skipping the cron entry."
		return 1
		;;
	esac
	if [ "$auto_update_time" -gt 23 ]; then
		log "Warning: auto_update_time=$auto_update_time is out of range (0-23), skipping the cron entry."
		return 1
	fi

	hp_crontab_drop "/etc/crontabs/root" "${CONF}_autosetup" \
		|| log "Warning: failed to drop the previous auto-update cron entry."
	printf '0 %s * * * %s/scripts/update_crond.sh #%s_autosetup\n' \
		"$auto_update_time" "$HP_DIR" "$CONF" >> "/etc/crontabs/root" \
		|| log "Warning: failed to install the auto-update cron entry."
	/etc/init.d/cron restart >"/dev/null" 2>&1 || log "Warning: failed to restart cron."
}

# hp_clear_autoupdate_cron
# Drop both cron entries and restart cron.  Used by stop_service.
#
# Both markers: stop_service has to leave no homeproxy-pro cron entry behind, and
# the resource entry is installed unconditionally, so dropping only the
# subscription one would leak a daily job on every stop.
hp_clear_autoupdate_cron() {
	hp_crontab_drop "/etc/crontabs/root" "${CONF}_autosetup" \
		|| log "Warning: failed to drop the previous auto-update cron entry."
	hp_crontab_drop "/etc/crontabs/root" "${CONF}_resource_cron" \
		|| log "Warning: failed to drop the previous resource-update cron entry."
	/etc/init.d/cron restart >"/dev/null" 2>&1 || log "Warning: failed to restart cron."
}

# hp_prepare_ruleset_dir <hp-dir>
# Create the rule-set archive, /etc/homeproxy-pro/ruleset.
#
# Called BEFORE the client configuration is generated, not only from
# hp_prepare_runtime_files.  Generation runs `sing-box check` over the result
# and check opens every local rule_set path, so on a fresh install the most
# natural path - "switch to custom routing, add a local rule-set, point it at
# /etc/homeproxy-pro/ruleset/example.srs" - was guaranteed to fail: hp_prepare_
# runtime_files only created the directory for a custom-mode start that had
# already got that far, and it runs after the generation, not before it.  The
# user got sing-box's own
#
#   parse rule-set[0]: open /etc/homeproxy-pro/ruleset/example.srs: no such file
#
# and the reload reported only "new client configuration is invalid, reload
# aborted" - with the directory the UI points at not existing yet.
#
# The directory is also created at install time (uci-defaults/luci-homeproxy-pro)
# so a router that has never started the service still has it; this call is
# what covers an upgrade from a version that predates that, and a user who
# removed it by hand.
#
# Ownership is NOT done here.  The jailed client runs as the sing-box user and
# has to read the files, but it starts after hp_prepare_runtime_files, which is
# where the recursive chown lives; doing it here as well would only add a
# second pass over the directory on every start.
hp_prepare_ruleset_dir() {
	local hp_dir="$1"

	[ -d "$hp_dir/ruleset" ] || mkdir -p "$hp_dir/ruleset" \
		|| log "Warning: failed to create ${hp_dir}/ruleset."
}

# hp_rule_set_current <source> <output>
# 0 when <output> is already the up-to-date rendering of <source>, 1 when it
# has to be generated.
#
# Generating china-domain.json measured 3540 ms on the x86-64 target
# (111,353 suffixes, 2.2 MB), and the source lists are replaced at most daily
# by update_resources.sh.  Regenerating unconditionally therefore spent a
# third of every reload - every Save & Apply, every node switch - rebuilding a
# byte-identical file, which is the single largest cost in a reload.
#
# The three conditions below are exactly the cases the unconditional version
# had to cover:
#
#   [ -f "$out" ]   a fresh install predates the file, or a previous run
#                  produced nothing
#   [ -s "$out" ]   the previous run was interrupted after truncating it; an
#                  empty rule-set would make the route-side set match nothing,
#                  which is the silent inversion this whole file exists to
#                  prevent
#   [ "$out" -nt "$src" ]  the list was replaced while the service was stopped
#
# A newer-but-corrupt output is deliberately NOT detected here.  It does not
# need to be: the generated config names the file, a rule-set sing-box cannot
# parse fails the start, and the health gate rolls back to the known-good
# configuration.  The check is cheap (<1 ms) and cannot mask a real failure -
# it can only skip work that would rebuild identical bytes.
hp_rule_set_current() {
	local src="$1" out="$2"

	[ -f "$out" ] && [ -s "$out" ] && [ "$out" -nt "$src" ]
}

# hp_prepare_generated_inputs <hp-dir> <client-enabled>
# Produce every rule-set the generated configuration references, BEFORE the
# generator runs.
#
# Why before: `sing-box check` opens every local rule_set path, and the client
# generator declares china-ip from china_ip4.json (route.uc, gated on
# china_ip4_ready).  When these files were produced *after* the generation step
# (they used to live at the end of hp_prepare_runtime_files), a fresh install had
# no china_ip4.json at generation time, `sing-box check` failed, and the client
# could not start at all - the reload preflight aborts before the rule-set step,
# so it could not heal itself either.  Measured on the device: generation exit=1
# with "parse rule-set[0]: open .../china_ip4.json: no such file or directory",
# and exit=0 once the three files had been produced.
#
# Cheap when nothing changed: hp_rule_set_current skips an unchanged source.
hp_prepare_generated_inputs() {
	local hp_dir="$1"
	local client_enabled="$2"

	# china-ip4: the route rule keeping mainland IPv4 destinations direct.
	if [ "$client_enabled" = "1" ] && [ -f "$hp_dir/resources/china_ip4.txt" ]; then
		if hp_rule_set_current "$hp_dir/resources/china_ip4.txt" "$hp_dir/resources/china_ip4.json"; then
			# Unchanged source: keep the file, but re-assert ownership anyway -
			# chown costs nothing and survives an install that reset it.
			chown sing-box:sing-box "$hp_dir/resources/china_ip4.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china_ip4.json to sing-box."
		elif ucode -S "$hp_dir/scripts/runtime/china_ip_ruleset.uc" \
			"$hp_dir/resources/china_ip4.txt" "$hp_dir/resources/china_ip4.json" >>"$LOG_PATH" 2>&1; then
			chown sing-box:sing-box "$hp_dir/resources/china_ip4.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china_ip4.json to sing-box."
		else
			log "Warning: could not generate ${hp_dir}/resources/china_ip4.json; the route side keeps the previous list."
		fi
	fi

	# china-ip6, plus the only user-facing report of "IPv6 is on but cannot be
	# classified".  Neither geoip-cn.srs nor china_ip4.json carries IPv6, so
	# without a v6 rule-set a mainland destination reached over IPv6 matches no
	# route rule and falls through to `final`; the firewall's v6 set is filled
	# from this same china_ip6.txt, so a missing or prefixless list leaves
	# neither side able to classify it.  cn_ipv6 counts usable prefixes first -
	# the generator needs at least one, so a zero-count list must skip straight
	# to the warning rather than call ucode and log a second failure.
	local ipv6_support cn_ipv6
	config_get_bool ipv6_support "config" "ipv6_support" "0"
	cn_ipv6=0
	if [ -f "$hp_dir/resources/china_ip6.txt" ]; then
		cn_ipv6="$(grep -cE '^[0-9a-fA-F:]+:[0-9a-fA-F:]*(/[0-9]{1,3})?[[:space:]]*$' \
			"$hp_dir/resources/china_ip6.txt" 2>"/dev/null")"
		[ -n "$cn_ipv6" ] || cn_ipv6=0
		if [ "$cn_ipv6" -gt 0 ] && hp_rule_set_current "$hp_dir/resources/china_ip6.txt" "$hp_dir/resources/china_ip6.json"; then
			chown sing-box:sing-box "$hp_dir/resources/china_ip6.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china_ip6.json to sing-box."
		elif [ "$cn_ipv6" -gt 0 ] && ucode -S "$hp_dir/scripts/runtime/china_ip_ruleset.uc" \
			"$hp_dir/resources/china_ip6.txt" "$hp_dir/resources/china_ip6.json" >>"$LOG_PATH" 2>&1; then
			chown sing-box:sing-box "$hp_dir/resources/china_ip6.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china_ip6.json to sing-box."
		else
			log "Warning: could not generate ${hp_dir}/resources/china_ip6.json; the route side keeps the previous list."
		fi
	fi
	if [ "$ipv6_support" -eq 1 ] && [ "$cn_ipv6" -eq 0 ]; then
		log "WARNING: IPv6 support is ON but ${hp_dir}/resources/china_ip6.txt has 0 usable prefixes."
		log "WARNING: mainland IPv6 cannot be told apart from foreign IPv6, so IPv6 is passed through UNPROXIED (both sides of the split degrade). Run: ${hp_dir}/scripts/update_resources.sh china_ip6"
	fi

	# china-domain: the DNS half, sending the list's domains to china-dns.
	if [ "$client_enabled" = "1" ] && [ -f "$hp_dir/resources/china_list.txt" ]; then
		if hp_rule_set_current "$hp_dir/resources/china_list.txt" "$hp_dir/resources/china-domain.json"; then
			chown sing-box:sing-box "$hp_dir/resources/china-domain.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china-domain.json to sing-box."
		elif ucode -S "$hp_dir/scripts/runtime/domain_ruleset.uc" \
			"$hp_dir/resources/china_list.txt" "$hp_dir/resources/china-domain.json" >>"$LOG_PATH" 2>&1; then
			chown sing-box:sing-box "$hp_dir/resources/china-domain.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china-domain.json to sing-box."
		else
			log "Warning: could not generate ${hp_dir}/resources/china-domain.json; the DNS side keeps the previous list."
		fi
	fi
}

# hp_prepare_runtime_files <hp-dir> <run-dir> <routing-mode> <client> <server>
# Create the mode-specific working files, truncate the instance logs and hand
# every runtime file to the sing-box user.  <client>/<server> are "1"/"0".
#
# The three China rule-sets below (china-ip4, china-ip6, china-domain) share one
# arrangement, and the reasons for it are stated once here rather than three
# times in the branches:
#
#   * Each is generated locally from a .txt the resource updater maintains, not
#     downloaded as an upstream .srs (geoip-cn.srs / geosite-geolocation-cn.srs),
#     so a cold start has nothing to download before the inbounds bind.  The
#     firewall reads the same .txt for its nft set, so both halves of the split
#     decide from one source and cannot drift.
#   * Generated here as well as by the updater: an install that predates the
#     .json, or a list replaced while the service was stopped, must still get
#     one - otherwise the generated config names a file that does not exist and
#     `sing-box check` refuses the start.
#   * A missing source .txt is NOT an error.  The generator then emits no
#     route-side / DNS-side rule for it and the split degrades to the default,
#     rather than failing the start.
#   * A FAILED generation keeps the previous .json rather than writing an empty
#     one.  This is the trap all three branches exist to avoid: an empty
#     rule-set matches nothing, so a mainland destination silently falls through
#     to `final` (i.e. the proxy) and the mode does the exact opposite of what it
#     promises - an inversion that produces no error anywhere.  Both helper
#     scripts (china_ip_ruleset.uc / domain_ruleset.uc) refuse to write an empty
#     rule-set and exit non-zero, which is what the else-branches log.
#   * The generated rule-set also carries this same text as a rule comment, so
#     `nft list ruleset` shows the degraded state too.
#
# NOTE: the three China rule-sets are produced by hp_prepare_generated_inputs(),
# which runs BEFORE the generator (see init.d) - this function no longer creates
# them; it only re-asserts them for a caller that arrives here directly.
hp_prepare_runtime_files() {
	local hp_dir="$1"
	local run_dir="$2"
	local routing_mode="$3"
	local client_enabled="$4"
	local server_enabled="$5"

	# The rule-sets the generated configuration references.  Also called before
	# generation (init.d), which is what makes a fresh install work; idempotent
	# and cheap when the sources did not change.
	hp_prepare_generated_inputs "$hp_dir" "$client_enabled"

	# cache_file is enabled for bypass_mainland_china and custom alike
	# (generator/common.uc:attachExperimental).  The file has to exist before
	# the client jail binds it, or sing-box cannot create it in there.
	case "$routing_mode" in
	"bypass_mainland_china"|"custom")
		[ -e "$hp_dir/cache.db" ] || touch "$hp_dir/cache.db" \
			|| log "Warning: failed to create ${hp_dir}/cache.db."
		;;
	esac

	if [ "$routing_mode" = "custom" ]; then
		# The directory itself is created earlier - see hp_prepare_ruleset_dir()
		# for why generation cannot wait for this function.  Re-running the
		# idempotent mkdir here costs nothing and keeps this function
		# self-contained for any caller that reaches it directly.
		hp_prepare_ruleset_dir "$hp_dir"
		# A local rule-set is opened by the client, which no longer runs as
		# root now that the jail is on for this mode too, so the files have to
		# be readable by the sing-box user.  Only the documented archive is
		# claimed here, and it is the only directory validateRuleSetPath()
		# admits; a rule-set placed elsewhere under HP_DIR is not a rule-set
		# the generator will emit any more.
		chown -R sing-box:sing-box "$hp_dir/ruleset" 2>"/dev/null" \
			|| log "Warning: failed to hand ${hp_dir}/ruleset to sing-box."
	fi

	[ "$client_enabled" = "1" ] && echo > "$run_dir/sing-box-c.log"
	if [ "$server_enabled" = "1" ]; then
		echo > "$run_dir/sing-box-s.log"
		if mkdir -p "$hp_dir/certs" 2>"/dev/null"; then
			# The server runs jailed as the sing-box user and reads its
			# certificate, key and ECH config from this directory, while an
			# upload lands as root:0600 (luci.homeproxy-pro).  Hand the directory
			# and its files to that user and keep them 0700/0600: the jailed
			# server can read them and nobody else can reach the private key.
			# Without this the choice was "world-readable key" or "jailed
			# server cannot start".
			chown sing-box:sing-box "$hp_dir/certs" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/certs to sing-box."
			chmod 700 "$hp_dir/certs" 2>"/dev/null"
			for f in "$hp_dir/certs"/*.pem "$hp_dir/certs"/*.crt "$hp_dir/certs"/*.key; do
				[ -f "$f" ] || continue
				chown sing-box:sing-box "$f" 2>"/dev/null" \
					|| log "Warning: failed to hand ${f} to sing-box."
				chmod 600 "$f" 2>"/dev/null"
			done
		else
			log "Warning: failed to create ${hp_dir}/certs."
		fi
	fi

	# chown each path that is actually there.
	#
	# The old one-shot chown listed every path unconditionally.  A mode whose
	# start path does not create one of them (custom mode and cache.db, before
	# that file became shared with it) then failed and logged "failed to
	# change the ownership of the runtime files" on every single start - a
	# warning that was always there and never meant anything. A missing path is
	# not worth reporting; failing to chown a file that exists still is.
	for f in "$run_dir"/sing-box-*.json "$run_dir"/sing-box-*.log "$hp_dir"/cache.db; do
		[ -e "$f" ] || continue
		chown sing-box:sing-box "$f" 2>"/dev/null" \
			|| log "Warning: failed to change the ownership of ${f} to sing-box."
	done
}

# hp_procd_client_instance <prog> <hp-dir> <run-dir> <routing-mode> <disable-gso>
# Register the sing-box client instance.  The ujail gate is client-specific:
# a wireguard/tun outbound cannot be jailed (it needs the host network stack),
# and custom routing needs HP_DIR inside the jail because a local rule-set may
# point at any path validateHomeProxyPath() accepts.  The `procd_append_param
# command` text below is what runtime/health.sh's pgrep pattern matches -
# change both together.
hp_procd_client_instance() {
	local prog="$1"
	local hp_dir="$2"
	local run_dir="$3"
	local routing_mode="$4"
	local disable_gso="$5"

	procd_open_instance "sing-box-c"

	procd_set_param command "$prog"
	procd_append_param command run --config "$run_dir/sing-box-c.json"

	[ "$disable_gso" -eq "1" ] && procd_set_param env "QUIC_GO_DISABLE_GSO"="true"

	if [ -x "/sbin/ujail" ] && ! grep -Eq '"type": "(wireguard|tun)"' "$run_dir/sing-box-c.json"; then
		procd_add_jail "sing-box-c" log procfs
		procd_add_jail_mount "$run_dir/sing-box-c.json"
		procd_add_jail_mount_rw "$run_dir/sing-box-c.log"
		# A custom routing table may point a local rule-set anywhere under
		# HP_DIR, so the whole directory goes in read-only rather than a
		# guessed subset.  procd orders the mounts by path, so this parent is
		# bound before the read-write cache.db below and cannot shadow it.
		procd_add_jail_mount "$hp_dir/"
		# cache_file is emitted unconditionally (generator/common.uc:
		# attachExperimental takes the routing mode and never reads it), so
		# every mode's sing-box opens this file and dies with
		#   initialize cache-file: open /etc/homeproxy-pro/cache.db: read-only file system
		# if it is bound read-only - which is what the mode-gated mount here
		# did for global / gfwlist / proxy_mainland_china.  The instance then
		# failed its health gate and the intercept layer was reverted, so
		# switching to one of those modes took the whole network off the
		# proxy.
		procd_add_jail_mount_rw "$hp_dir/cache.db"
		procd_add_jail_mount "$hp_dir/certs/"
		# The certificate path gate accepts /etc/acme as well (a client TLS
		# certificate managed by acme.sh), so the client jail has to carry it
		# too - it was missing here while the server jail already had it.
		procd_add_jail_mount "/etc/acme/"
		procd_add_jail_mount "/etc/ssl/"
		# custom routing's find_neighbor resolves LAN hostnames out of the
		# dnsmasq lease file; its MAC lookups go over netlink and need no file,
		# but a `source_hostname` rule silently stops matching without this.
		procd_add_jail_mount "/tmp/dhcp.leases"
		procd_add_jail_mount "/etc/localtime"
		procd_add_jail_mount "/etc/TZ"
		procd_set_param capabilities "/etc/capabilities/homeproxy-pro.json"
		procd_set_param no_new_privs 1
		procd_set_param user sing-box
		procd_set_param group sing-box
	fi

	procd_set_param limits core="unlimited"
	procd_set_param limits nofile="1000000 1000000"
	procd_set_param stderr 1
	procd_set_param respawn

	procd_close_instance
}

# hp_procd_server_instance <prog> <hp-dir> <run-dir> <disable-gso>
# Register the sing-box server instance.  The jail only depends on ujail
# being installed, and it needs the certificate/ACME material instead of the
# client's cache.db.
hp_procd_server_instance() {
	local prog="$1"
	local hp_dir="$2"
	local run_dir="$3"
	local disable_gso="$4"

	procd_open_instance "sing-box-s"

	procd_set_param command "$prog"
	procd_append_param command run --config "$run_dir/sing-box-s.json"

	[ "$disable_gso" -eq "1" ] && procd_set_param env "QUIC_GO_DISABLE_GSO"="true"

	if [ -x "/sbin/ujail" ]; then
		procd_add_jail "sing-box-s" log procfs
		procd_add_jail_mount "$run_dir/sing-box-s.json"
		procd_add_jail_mount_rw "$run_dir/sing-box-s.log"
		procd_add_jail_mount_rw "$hp_dir/certs/"
		procd_add_jail_mount "/etc/acme/"
		procd_add_jail_mount "/etc/ssl/"
		procd_add_jail_mount "/etc/localtime"
		procd_add_jail_mount "/etc/TZ"
		procd_set_param capabilities "/etc/capabilities/homeproxy-pro.json"
		procd_set_param no_new_privs 1
		procd_set_param user sing-box
		procd_set_param group sing-box
	fi

	procd_set_param limits core="unlimited"
	procd_set_param limits nofile="1000000 1000000"
	procd_set_param stderr 1
	procd_set_param respawn

	procd_close_instance
}

# hp_procd_log_cleaner <hp-dir>
# Register the log-rotator instance.  It is unconditional: it also has to run
# when neither client nor server is enabled.
hp_procd_log_cleaner() {
	local hp_dir="$1"

	procd_open_instance "log-cleaner"
	procd_set_param command "$hp_dir/scripts/clean_log.sh"
	procd_set_param respawn
	procd_close_instance
}

# hp_capture_candidate <run-dir> <side>
# Stage the configuration the reload preflight just generated and validated.
#
# The copy is necessary because stop_service() removes $RUN_DIR/sing-box-*.json
# on its way to start_service (they are runtime state, not configuration), so
# the file the preflight validated is gone by the time the new instance would
# use it - which is exactly why the old reload regenerated it. The staged copy
# lives in $RUN_DIR/candidate/, which stop_service() does not touch, and it is
# what hp_start_generated_config() activates. Non-zero when there is nothing
# staged, and the caller aborts the reload rather than continuing without a
# validated candidate.
hp_capture_candidate() {
	local run_dir="$1"
	local side="$2"
	local live="$run_dir/sing-box-${side}.json"
	local cand_dir="$run_dir/candidate"
	local staged="$cand_dir/sing-box-${side}.json"

	[ -s "$live" ] || return 1

	mkdir -p "$cand_dir" 2>/dev/null || return 1
	cp -f "$live" "$staged" 2>/dev/null || return 1
	# The staged file carries the same credentials as the live one; the
	# generator already wrote it 0600 and this copy has to stay that way.
	chmod 600 "$staged" 2>/dev/null

	return 0
}

# hp_reload_is_noop <run-dir> <good-dir> <client-enabled> <server-enabled>
# 0 when this reload would change nothing that is currently running, so the
# caller can skip the stop;start entirely.
#
# Why this exists: reload_service used to stop and start unconditionally, and
# hp_same_file was only ever used on the rollback path.  Measured on the device,
# one reload costs about eight seconds (09:17:40 -> 09:17:48 in the log) and
# interrupts every connection, even when the generated configuration is
# byte-identical to the one already running.  That is the common case for
# "Save & Apply" with nothing edited, for a node switch that lands on the same
# node, and for the nightly resource refresh.
#
# THE COMPARISON IS AGAINST known-good, NOT AGAINST THE CANDIDATE, and getting
# that wrong silently disables the whole mechanism.  Measured on the device:
# the generator writes straight to $RUN_DIR/sing-box-c.json and
# hp_capture_candidate() copies that same file afterwards, so after a preflight
# the candidate and the live file are the SAME BYTES BY CONSTRUCTION - comparing
# them reports "unchanged" for every reload, including one that switched the main
# node.  The first version of this helper did exactly that, and the only reason
# it was caught is an on-device test that switched nodes and watched the PID.
#
# known-good is the right counterpart for the same reason the rollback path uses
# it: hp_promote_known_good writes it ONLY after the health gate has passed, so
# it is by definition "the configuration that is currently running and working".
# live vs known-good answers the question this helper is actually asking - "would
# the running configuration change?" - and a missing known-good simply falls
# through to a real reload.
#
# Every condition is a *precondition for the skip being safe*, and the default
# on any doubt is to reload:
#
#   [1] the service is actually running.  A live file left over from a crashed
#       instance is not a running service, and skipping the restart would
#       report success over a dead proxy.  Asked of ubus, the same source the
#       status page reads.
#   [2] the side has both a live file and a known-good copy to compare against.
#       A side the user just enabled has neither, and that is a change, not a
#       no-op.
#   [3] the intercept layer is installed.  A released layer (the marker
#       hp_release_stale_intercept writes) means the firewall is NOT proxying
#       right now even though sing-box is up.  Skipping the restart would leave
#       it that way and log "nothing to restart" - the exact silent state
#       hp_rearm_intercept exists to undo.  Reloading is what re-arms it.
hp_reload_is_noop() {
	local run_dir="$1"
	local good_dir="$2"
	local client_enabled="$3"
	local server_enabled="$4"
	local live good

	# [3] first, because it is the cheapest and the most dangerous to skip.
	[ ! -f "$run_dir/intercept-released" ] || return 1

	# [1] the instances.  `command -v ubus` because this module is also sourced
	# by the off-target test driver, where ubus does not exist and the honest
	# answer there is "cannot prove it is a no-op".
	#
	# The check is on `"running": true`, NOT on the instance merely appearing
	# in the list: procd keeps a stopped instance in `service list` with
	# running=false, so matching the key alone reports a dead proxy as running
	# and the skip then claims success over it.  That was not theoretical - the
	# first version of this grep did exactly that and its own test caught it.
	command -v ubus > "/dev/null" 2>&1 || return 1

	local svc_list
	svc_list="$(ubus call service list "{\"name\":\"$CONF\"}" 2>/dev/null)"

	if [ "$client_enabled" = "1" ]; then
		printf '%s' "$svc_list" \
			| grep -A 3 '"sing-box-c"' \
			| grep -q '"running"[[:space:]]*:[[:space:]]*true' || return 1
	fi

	if [ "$server_enabled" = "1" ]; then
		printf '%s' "$svc_list" \
			| grep -A 3 '"sing-box-s"' \
			| grep -q '"running"[[:space:]]*:[[:space:]]*true' || return 1
	fi

	# [2] and the byte comparison, per side.
	# [2] and the byte comparison, per side, against what is known to be running
	# rather than against the candidate (see the note at the top of this
	# function - the two are the same bytes by construction).
	if [ "$client_enabled" = "1" ]; then
		live="$run_dir/sing-box-c.json"
		good="$good_dir/sing-box-c.json"

		[ -s "$live" ] && [ -s "$good" ] || return 1
		cmp -s "$live" "$good" 2>"/dev/null" || return 1
	fi

	if [ "$server_enabled" = "1" ]; then
		live="$run_dir/sing-box-s.json"
		good="$good_dir/sing-box-s.json"

		[ -s "$live" ] && [ -s "$good" ] || return 1
		cmp -s "$live" "$good" 2>"/dev/null" || return 1
	fi

	return 0
}

# hp_start_generated_config <side> <hp-dir> <run-dir> <good-dir>
# The start-path transaction for one side ("c" or "s"):
#
#   HP_USE_KNOWN_GOOD=1 -> copy the recorded configuration over the live one
#                          instead of regenerating (a rollback: regenerating
#                          would rebuild the very file that just failed)
#   HP_CANDIDATE_<SIDE>=1 -> the reload preflight generated and `sing-box
#                          check`ed this side; activate the copy
#                          hp_capture_candidate() staged, do not generate again
#   otherwise           -> generate, then make sure a live file exists,
#                          falling back to the known-good copy when it does not
#
# Returns 1 only when there is nothing to run at all (generation failed and
# no known-good copy exists), which is what made start_service bail out.
#
# It deliberately does NOT touch the known-good copy any more.  It used to
# record the freshly generated file immediately, which meant that by the time
# the health gate ran, the "previous" configuration the rollback would need had
# already been overwritten by the candidate - so a failed reload had nothing to
# roll back to.  Promotion is now a separate step, taken only after the gate
# has passed (hp_promote_known_good, called from start_service).
#
# A3: the candidate flag exists because the generator is no longer guaranteed to
# produce the same bytes twice - its env carries the WAN resolver and the two
# domain-resource lists, either of which can change between two invocations. A
# reload that generated the config, validated it, and then let start_service
# generate it *again* would run an artifact that had never been checked:
# validate A -> discard A -> generate B -> run B. The flag makes the validated
# bytes the ones that run. It is per side, so a config_load disagreement between
# reload_service and start_service (a concurrent UCI change) generates the side
# the preflight did not cover instead of activating a stale file.
hp_start_generated_config() {
	local side="$1"
	local hp_dir="$2"
	local run_dir="$3"
	local good_dir="$4"
	local label generator live good candidate staged

	case "$side" in
	c)
		label="client"
		generator="$hp_dir/scripts/generate_client.uc"
		candidate="${HP_CANDIDATE_CLIENT:-0}"
		;;
	s)
		label="server"
		generator="$hp_dir/scripts/generate_server.uc"
		candidate="${HP_CANDIDATE_SERVER:-0}"
		;;
	*) log "Error: unknown configuration side '${side}'."; return 1 ;;
	esac

	live="$run_dir/sing-box-${side}.json"
	good="$good_dir/sing-box-${side}.json"

	if [ "${HP_USE_KNOWN_GOOD:-0}" = "1" ] && [ -s "$good" ]; then
		# Rollback path: start from the recorded configuration instead
		# of regenerating.  Regenerating would rebuild the very config
		# that just failed to come up, because the generator is a pure
		# function of UCI.
		log "Starting with the last known-good ${label} configuration."
		cp -f "$good" "$live"
		return 0
	fi

	if [ "$candidate" = "1" ]; then
		# The reload preflight's artifact is the one that passed `sing-box
		# check`. stop_service() removed the live copy on the way here, so the
		# staged copy is what gets activated - the same bytes that were
		# validated, not a second generation.
		staged="$run_dir/candidate/sing-box-${side}.json"

		if [ -s "$staged" ] && cp -f "$staged" "$live" 2>/dev/null; then
			# One shot: the staged copy must not survive to be activated by a
			# later start that never validated it.
			rm -f "$staged"
			log "Activating the ${label} configuration validated by the reload preflight."
			return 0
		fi

		# Defensive: the flag was set but nothing was staged. Generate rather
		# than activate an unvalidated or stale file.
		log "Warning: no validated ${label} candidate is staged; generating the configuration again."
	fi

	ucode -S "$generator" 2>>"$LOG_PATH"
	gen_rc=$?

	# The generator is transactional on its own: it writes a temporary file
	# and only renames it over the live one once `sing-box check` accepted
	# it.  A failed generation therefore leaves the previous file untouched -
	# and that is the only `sing-box check` in this path (the runtime used to
	# run a second one on the same file).
	hp_ensure_live "$live" "$good"
	case "$?" in
	0)
		# A live file exists, but it may be the *previous* configuration: a
		# failed generation leaves it in place.  That used to be reported as a
		# plain success with nothing in the log - `start` on a service whose
		# UCI had gone invalid returned 0 while the old file kept running.
		[ "$gen_rc" = "0" ] \
			|| log "Warning: could not regenerate the ${label} configuration (generator exit ${gen_rc}); the previous configuration stays in place."
		;;
	1)
		log "Error: failed to generate a valid ${label} configuration; falling back to the last known-good one." ;;
	*)
		log "Error: failed to generate ${label} configuration."
		return 1 ;;
	esac

	return 0
}

# The UCI keys the intercept layer reads, split by UCI type.
#
# hp_restore_known_good_uci() replays the snapshot before the rollback
# restart, so anything that steers firewall_post.ut / firewall_pre.uc /
# net.sh / dns.sh has to be in here: a key left out survives the rollback as
# the *new* (failing) value and start_service reinstalls a layer that no
# longer matches the sing-box file it just restored.
#
# The 2026-09-29 review found the
# previous five-line list covered 4 real keys out of 22, and that the fifth
# line named `infra.tun_address` - an option that exists nowhere.  The real
# keys are `tun_addr4` / `tun_addr6` (config/loader.uc:411), so that line was
# always empty and the restore was a silent no-op; the golden trace recorded
# the empty line as expected, which is how the defect survived.  tests/
# arch-guard.sh guard 43 derives the read set from the layer consumers and
# compares it against this list in both directions.
#
# The two TUN address keys are the one deliberate inclusion that no layer
# consumer reads: the address is only ever installed by the generated sing-box
# file, so leaving UCI describing the failed address would make the next
# reload regenerate the configuration that just failed.
HP_INTERCEPT_SCALARS="config.main_node
config.main_udp_node
config.proxy_mode
config.routing_mode
config.routing_port
config.ipv6_support
config.china_dns_server
infra.self_mark
infra.redirect_port
infra.tproxy_port
infra.tproxy_mark
infra.tun_mark
infra.tun_name
infra.tun_addr4
infra.tun_addr6
infra.dns_redirect
infra.dns_port
infra.common_port
infra.table_mark
routing.bypass_cn_traffic
routing.default_outbound
server.enabled
control.lan_proxy_mode"

# List options are kept apart because `uci set key=a,b` stores a *string*:
# ipv4_to_nftarr() / iface_to_nftarr() reject a non-array (they return null),
# so a snapshot replayed through `uci set` would drop every ACL rule that
# reads the list - a rollback that silently un-proxies the LAN.  The writer
# joins the elements with ',' and the replay uses `uci delete` +
# `uci add_list`.  No value in this set can contain a comma: they are IPv4 /
# IPv6 addresses, MAC addresses or interface names.
HP_INTERCEPT_LISTS="control.listen_interfaces
control.lan_direct_ipv4_ips
control.lan_direct_ipv6_ips
control.lan_direct_mac_addrs
control.lan_proxy_ipv4_ips
control.lan_proxy_ipv6_ips
control.lan_proxy_mac_addrs
control.lan_gaming_mode_ipv4_ips
control.lan_gaming_mode_ipv6_ips
control.lan_gaming_mode_mac_addrs
control.lan_global_proxy_ipv4_ips
control.lan_global_proxy_ipv6_ips
control.lan_global_proxy_mac_addrs
control.wan_proxy_ipv4_ips
control.wan_proxy_ipv6_ips
control.wan_direct_ipv4_ips
control.wan_direct_ipv6_ips"

# hp_write_uci_snapshot <snap>
# Serialise HP_INTERCEPT_SCALARS / HP_INTERCEPT_LISTS into <snap>.
#
# One line per key so a reader without uci-tools can iterate the file:
#
#   homeproxy-pro.<section>.<option>=<value>     scalar
#   list homeproxy-pro.<section>.<option>=a,b    list, ','-joined
#   list homeproxy-pro.<section>.<option>=       list that was absent or empty
#
# An absent scalar is written as an empty value, which is how the replay
# spells "remove the option again" (UCI deletes an option set to an empty
# value) - so the snapshot round-trips absence as well as presence.
hp_write_uci_snapshot() {
	local snap="$1"
	local pair sec opt val el out

	config_load "$CONF"

	{
		for pair in $HP_INTERCEPT_SCALARS; do
			sec="${pair%%.*}"
			opt="${pair#*.}"
			config_get val "$sec" "$opt"
			printf 'homeproxy-pro.%s.%s=%s\n' "$sec" "$opt" "$val"
		done

		for pair in $HP_INTERCEPT_LISTS; do
			sec="${pair%%.*}"
			opt="${pair#*.}"
			config_get val "$sec" "$opt"
			# config_get hands a UCI list over space-separated; rejoin it.
			out=""
			for el in $val; do
				[ -z "$out" ] && out="$el" || out="$out,$el"
			done
			printf 'list homeproxy-pro.%s.%s=%s\n' "$sec" "$opt" "$out"
		done
	} > "$snap.tmp" 2>"/dev/null" && mv -f "$snap.tmp" "$snap"
}

# hp_promote_known_good <side> <run-dir> <good-dir>
# Record the live configuration as the new known-good copy.  Called only after
# the health gate has proven that the configuration actually runs, so the
# rollback target is always something that came up.
#
# Also writes $good_dir/uci-snapshot.txt (see HP_INTERCEPT_SCALARS above).
# The rollback path in init.d/homeproxy-pro reads that file back BEFORE its
# stop;start, otherwise start_service reinstalls the new (failing) layer on
# top of the rolled-back sing-box bytes - the classic "rollback restored the
# config but nft is still the new chains" silent failure that took a
# real-machine repro to spot (review P1-3, 2026-09-28).  Snapshotting only
# the keys that steer the network layer keeps the rollback bounded: a stray
# key elsewhere never overwrites itself.
hp_promote_known_good() {
	local side="$1"
	local run_dir="$2"
	local good_dir="$3"
	local label

	case "$side" in
	c) label="client" ;;
	s) label="server" ;;
	*) log "Error: unknown configuration side '${side}'."; return 1 ;;
	esac

	hp_known_good "$run_dir/sing-box-${side}.json" "$good_dir/sing-box-${side}.json" \
		|| log "Warning: could not refresh the known-good ${label} configuration."

	# Written once on every successful promote.  Both sides promote the same
	# content, so the two calls cannot disagree.
	hp_write_uci_snapshot "$good_dir/uci-snapshot.txt"
}

