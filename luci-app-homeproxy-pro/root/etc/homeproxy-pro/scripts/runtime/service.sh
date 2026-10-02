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

# hp_crontab_drop <crontab>
# Remove the auto-update entry from <crontab>.
#
# Not `sed -i`: the bare `-i` form is a busybox/GNU extension, and on a host with
# BSD sed it fails ("invalid command code"), which silently left the stale entry
# behind with only a warning in the log.  Editing through a temporary file
# behaves identically on busybox, GNU and BSD sed, and it is what lets this
# module be exercised off-target at all
# (tests/runtime/test_runtime_extraction.sh stages and drives it).
hp_crontab_drop() {
	local crontab="$1"
	local tmp="${crontab}.hp-new"

	sed "/#${CONF}_autosetup/d" "$crontab" > "$tmp" 2>"/dev/null" || { rm -f "$tmp"; return 1; }
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

	hp_crontab_drop "/etc/crontabs/root" \
		|| log "Warning: failed to drop the previous auto-update cron entry."
	printf '0 %s * * * %s/scripts/update_crond.sh #%s_autosetup\n' \
		"$auto_update_time" "$HP_DIR" "$CONF" >> "/etc/crontabs/root" \
		|| log "Warning: failed to install the auto-update cron entry."
	/etc/init.d/cron restart >"/dev/null" 2>&1 || log "Warning: failed to restart cron."
}

# hp_clear_autoupdate_cron
# Drop the auto-update cron entry and restart cron.  Used by stop_service.
hp_clear_autoupdate_cron() {
	hp_crontab_drop "/etc/crontabs/root" \
		|| log "Warning: failed to drop the auto-update cron entry."
	/etc/init.d/cron restart >"/dev/null" 2>&1 || log "Warning: failed to restart cron."
}

# hp_prepare_runtime_files <hp-dir> <run-dir> <routing-mode> <client> <server>
# Create the mode-specific working files, truncate the instance logs and hand
# every runtime file to the sing-box user.  <client>/<server> are "1"/"0".
hp_prepare_runtime_files() {
	local hp_dir="$1"
	local run_dir="$2"
	local routing_mode="$3"
	local client_enabled="$4"
	local server_enabled="$5"

	# The route rules that keep mainland destinations direct match a local
	# rule-set generated from china_ip4.txt, the same list the firewall
	# renders its nft set from, so both sides decide from one source.  It is
	# regenerated here as well as by the resource updater: an install that
	# predates this file (or a list replaced while the service was stopped)
	# must still get one, or the client config would reference a missing
	# file and sing-box would refuse to start.  A missing source list is not
	# an error - the generator then emits no route-side rule at all.
	if [ "$client_enabled" = "1" ] && [ -f "$hp_dir/resources/china_ip4.txt" ]; then
		if ucode -S "$hp_dir/scripts/runtime/china_ip_ruleset.uc" \
			"$hp_dir/resources/china_ip4.txt" "$hp_dir/resources/china_ip4.json" >>"$LOG_PATH" 2>&1; then
			chown sing-box:sing-box "$hp_dir/resources/china_ip4.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china_ip4.json to sing-box."
		else
			log "Warning: could not generate ${hp_dir}/resources/china_ip4.json; the route side keeps the previous list."
		fi
	fi

	# IPv6 half of the same arrangement, and the only place the "IPv6 is on
	# but cannot be classified" condition is reported in a place a user reads
	# without tcpdump.  geoip-cn.srs and china_ip4.json are both IPv4-only, so
	# without a v6 rule-set a mainland destination reached over IPv6 matches
	# no route rule at all and falls through to `final` - i.e. to the proxy.
	# The firewall would normally have returned it first, but that set is
	# filled from the same china_ip6.txt, so a list that is missing or has no
	# usable prefix leaves neither side able to classify it.  Say so plainly
	# instead: the generated ruleset also carries the same text as a rule
	# comment, so `nft list ruleset` shows the degraded state too.
	local ipv6_support cn_ipv6
	config_get_bool ipv6_support "config" "ipv6_support" "0"
	cn_ipv6=0
	if [ -f "$hp_dir/resources/china_ip6.txt" ]; then
		cn_ipv6="$(grep -cE '^[0-9a-fA-F:]+:[0-9a-fA-F:]*(/[0-9]{1,3})?[[:space:]]*$' \
			"$hp_dir/resources/china_ip6.txt" 2>"/dev/null")"
		[ -n "$cn_ipv6" ] || cn_ipv6=0
		if [ "$cn_ipv6" -gt 0 ] && ucode -S "$hp_dir/scripts/runtime/china_ip_ruleset.uc" \
			"$hp_dir/resources/china_ip6.txt" "$hp_dir/resources/china_ip6.json" >>"$LOG_PATH" 2>&1; then
			chown sing-box:sing-box "$hp_dir/resources/china_ip6.json" 2>"/dev/null" \
				|| log "Warning: failed to hand ${hp_dir}/resources/china_ip6.json to sing-box."
		else
			# Only reached when the source is unusable, which china_ip_ruleset.uc
			# reports as "no usable CIDR entries".  Keep the previous file: an
			# empty one would make the route-side set match nothing, which is the
			# same silent inversion this whole branch exists to prevent.
			log "Warning: could not generate ${hp_dir}/resources/china_ip6.json; the route side keeps the previous list."
		fi
	fi
	if [ "$ipv6_support" -eq 1 ] && [ "$cn_ipv6" -eq 0 ]; then
		log "WARNING: IPv6 support is ON but ${hp_dir}/resources/china_ip6.txt has 0 usable prefixes."
		log "WARNING: mainland IPv6 cannot be told apart from foreign IPv6, so IPv6 is passed through UNPROXIED (both sides of the split degrade). Run: ${hp_dir}/scripts/update_resources.sh china_ip6"
	fi

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
		[ -d "$hp_dir/ruleset" ] || mkdir -p "$hp_dir/ruleset" \
			|| log "Warning: failed to create ${hp_dir}/ruleset."
		# A local rule-set is opened by the client, which no longer runs as
		# root now that the jail is on for this mode too, so the files have to
		# be readable by the sing-box user.  Only the documented directory is
		# claimed here; a rule-set placed elsewhere under HP_DIR has to be
		# readable already.
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

	# The generator is transactional on its own: it writes a temporary file
	# and only renames it over the live one once `sing-box check` accepted
	# it.  A failed generation therefore leaves the previous file untouched -
	# and that is the only `sing-box check` in this path (the runtime used to
	# run a second one on the same file).
	hp_ensure_live "$live" "$good"
	case "$?" in
	0)
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
# Review 2026-09-29 (docs/review-report-20260929-full.md §1.2) found the
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

