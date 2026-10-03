#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2025 ImmortalWrt.org
#
# Fetch and install one resource list (china_ip4 / china_ip6 / gfw_list /
# china_list). Each list comes from a fixed upstream repository; the current
# commit is resolved through the GitHub API, the file is downloaded from the
# first reachable mirror at that exact commit, and the result is installed only
# after its git blob id has been checked against the one the API reports for
# that path and commit (resource_blob_sha.uc). A list that fails the check is
# discarded and the installed copy is left in place.
#
# Driven by the rpcd method `resources_update` and by the auto-update cron
# entry; tests/runtime/test_resource_update.sh exercises the verification path
# off-target with stubbed wget/jsonfilter/ucode.

NAME="homeproxy-pro"

# The blob-digest helper sits next to this script and is invoked through it, so
# its location follows however the script was started (rpcd, cron, a shell).
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>"/dev/null" && pwd)"

RESOURCES_DIR="/etc/$NAME/resources"
mkdir -p "$RESOURCES_DIR"

RUN_DIR="/var/run/$NAME"
LOG_PATH="$RUN_DIR/$NAME.log"
mkdir -p "$RUN_DIR"

log() {
	printf '%s %s\n' "$(date "+%Y-%m-%d %H:%M:%S")" "$*" >> "$LOG_PATH"
}

to_upper() {
	printf '%s' "$1" | tr "[a-z]" "[A-Z]"
}

# Review M7: each entry is tried in order, success stops the loop.  Order
# matters: fastly.jsdelivr.net is the CDN edge closest to the original
# report and used to be the only mirror; gcore and cdn are sibling edges;
# raw.githubusercontent.com is the upstream fallback (the file lives in
# the same GitHub repo we just queried for the SHA, so it is reachable
# whenever the version query was reachable).  Putting the CDN edges first
# keeps the common case fast; the GitHub fallback catches the case where
# the CDN is blocked but GitHub is reachable - which is the shape of the
# `api.github.com` rate-limit problem the report calls out.
MIRRORS="fastly.jsdelivr.net gcore.jsdelivr.net cdn.jsdelivr.net raw.githubusercontent.com"

# Pick the first mirror that responds to a HEAD with HTTP 200 in 10s.
# Called with: <path-suffix>.  Echoes the chosen base URL on stdout, or
# fails the script if every mirror timed out.
pick_mirror() {
	local path_suffix="$1"
	for base in $MIRRORS; do
		if [ "$base" = "raw.githubusercontent.com" ]; then
			# GitHub raw serves paths from the repo root, not the
			# /gh/<repo>@<sha>/<file> shape jsdelivr uses. The caller
			# passes the suffix already split out, so we re-stitch it.
			local probe_url="https://$base/$listrepo/$list_sha/$listname"
		else
			local probe_url="https://$base/gh/$listrepo@$list_sha/$listname"
		fi
		# uclient-fetch, not wget.  wget is whichever implementation the
		# buildroot compiled, and the two share almost no options: on a
		# busybox-wget router every flag here is rejected with "unrecognized
		# option" before a request is made, so the resource lists silently
		# never updated - pick_mirror returns 1 and the caller carries on.
		# uclient-fetch is the fetcher OpenWrt itself uses and its option set
		# is fixed by the applet, not by the buildroot.  Read off the applet
		# on the device: --spider checks existence only, --timeout=N is
		# seconds.  -q because this probe's stderr goes nowhere anyway.
		#
		# Resolved through PATH rather than spelled /bin/..., exactly as this
		# script used to spell a bare `wget`: it keeps the name overridable in
		# the test sandbox, which is how the option list gets exercised at all.
		if uclient-fetch -q -s --timeout=10 "$probe_url" 2>"/dev/null"; then
			printf '%s\n' "$base"
			return 0
		fi
	done
	return 1
}

check_list_update() {
	local listtype="$1"
	local listrepo="$2"
	local listref="$3"
	local listname="$4"
	local lock="$RUN_DIR/update_resources-$listtype.lock"
	local github_token="$(uci -q get homeproxy-pro.config.github_token)"
	local fetch="uclient-fetch -q --timeout=10"

	# fd 9, not 200: POSIX only guarantees 0-9, and dash fails the whole
	# `exec 200>"$lock"` with "exec: 200: not found". busybox ash and bash
	# accept multi-digit descriptors, so this only ever showed up off-target -
	# but the shebang says /bin/sh, and the off-target driver runs it there.
	# `&>` is a bashism for the same reason; `> file 2>&1` is the POSIX form.
	exec 9>"$lock"
	if ! flock -n 9 >"/dev/null" 2>&1; then
		log "[$(to_upper "$listtype")] A task is already running."
		return 2
	fi

	# The token travels in argv, which the previous form avoided by writing it
	# to a 0600 file and passing --header-file - an option no fetch
	# implementation has, so it failed with "unrecognized option" and the
	# version query never worked at all with a token configured. uclient-fetch
	# has no file-based header option either, so argv is the only way; on a
	# single-user router that is the right trade for a feature that otherwise
	# does not function.  The header is passed only when a token is set, and
	# nothing logs the command line.
	local github_header=""
	[ -n "$github_token" ] && github_header="Authorization: Bearer $github_token"

	# --header takes '=': the space-separated form is rejected, and the value
	# has to stay ONE argv element, which the quoting around it preserves.
	local list_info="$($fetch ${github_header:+--header="$github_header"} -O- "https://api.github.com/repos/$listrepo/commits?sha=$listref&path=$listname&per_page=1")"
	local fetch_exit=$?

	if [ $fetch_exit -ne 0 ]; then
		log "[$(to_upper "$listtype")] Failed to fetch version info (fetch exit $fetch_exit)."
		return 1
	fi
	local list_sha="$(printf '%s' "$list_info" | jsonfilter -qe "@[0].sha")"
	local list_date="$(printf '%s' "$list_info" | jsonfilter -qe "@[0].commit.committer.date" | cut -d 'T' -f1)"
	if [ -z "$list_sha" ]; then
		log "[$(to_upper "$listtype")] Failed to get the latest version, please retry later."
		return 1
	fi
	local list_ver="${list_date:+$list_date }$list_sha"

	local local_list_ver="$(cat "$RESOURCES_DIR/$listtype.ver" 2>"/dev/null" || echo "NOT_FOUND")"
	local local_list_sha="${local_list_ver##* }"
	local local_list_disp="${local_list_ver%% *}"
	if [ "$local_list_sha" = "$list_sha" ]; then
		[ "$local_list_ver" = "$local_list_sha" ] && [ -n "$list_date" ] && \
			printf '%s\n' "$list_ver" > "$RESOURCES_DIR/$listtype.ver"
		log "[$(to_upper "$listtype")] Current version: ${list_ver%% *}."
		log "[$(to_upper "$listtype")] You're already at the latest version."
		return 3
	else
		log "[$(to_upper "$listtype")] Local version: $local_list_disp, latest version: ${list_ver%% *}."
	fi

	# Pick a mirror, then download. pick_mirror walks the list and uses
	# the first reachable one; raw.githubusercontent.com is a separate
	# path shape so the helper handles it.
	local mirror="$(pick_mirror)"
	if [ -z "$mirror" ]; then
		log "[$(to_upper "$listtype")] All mirrors unreachable (tried: $MIRRORS)."
		return 1
	fi
	local mirror_url
	if [ "$mirror" = "raw.githubusercontent.com" ]; then
		mirror_url="https://raw.githubusercontent.com/$listrepo/$list_sha/$listname"
	else
		mirror_url="https://$mirror/gh/$listrepo@$list_sha/$listname"
	fi
	log "[$(to_upper "$listtype")] Downloading from $mirror."

	if ! $fetch -O "$RUN_DIR/$listname" "$mirror_url" || [ ! -s "$RUN_DIR/$listname" ]; then
		rm -f "$RUN_DIR/$listname"
		log "[$(to_upper "$listtype")] Download failed ($mirror)."
		return 1
	fi

	# Integrity: the URL is pinned to $list_sha, so the mirror is *supposed* to
	# serve the bytes that commit contains. That is a statement about the URL,
	# not about the response - a mirror, a CDN edge or anything else in the
	# path can answer with different content, and the resource lists drive
	# nft sets and DNS snippets. Compare the file's git blob id against the one
	# GitHub reports for the same path and commit.
	#
	# This fails closed. The version query above already requires
	# api.github.com, so a router that cannot reach the API could not update
	# resources before this check either; the alternative - installing bytes
	# nobody vouched for - is the thing being fixed.
	local api_blob local_blob
	api_blob="$($fetch ${github_header:+--header="$github_header"} -O- \
		"https://api.github.com/repos/$listrepo/contents/$listname?ref=$list_sha" \
		| jsonfilter -qe '@.sha')"
	if [ -z "$api_blob" ]; then
		rm -f "$RUN_DIR/$listname"
		log "[$(to_upper "$listtype")] Refusing to install: GitHub reports no blob id for $listname at $list_sha."
		return 1
	fi

	local_blob="$(ucode -S "$SCRIPT_DIR/resource_blob_sha.uc" "$RUN_DIR/$listname" 2>"/dev/null")"
	if [ -z "$local_blob" ]; then
		rm -f "$RUN_DIR/$listname"
		log "[$(to_upper "$listtype")] Refusing to install: cannot compute the blob id of the downloaded $listname."
		return 1
	fi

	if [ "$local_blob" != "$api_blob" ]; then
		rm -f "$RUN_DIR/$listname"
		log "[$(to_upper "$listtype")] Refusing to install: $listname from $mirror does not match the content of commit $list_sha (expected $api_blob, got $local_blob)."
		return 1
	fi

	if mv -f "$RUN_DIR/$listname" "$RESOURCES_DIR/$listtype.${listname##*.}"; then
		printf '%s\n' "$list_ver" > "$RESOURCES_DIR/$listtype.ver"
		# Review M7: persist the time *this router* last succeeded.
		# $list_date is the upstream commit date and can be months old
		# even on a successful run, so it is not a stand-in.  Stored in
		# the same directory as the .ver file so resources_get_version
		# can read it.
		date -u +"%Y-%m-%dT%H:%M:%SZ" > "$RESOURCES_DIR/$listtype.updated_at"
		log "[$(to_upper "$listtype")] Successfully updated via $mirror (blob $local_blob)."
		# The route side reads the China list through a generated sing-box
		# rule-set rather than geoip-cn.srs, so the list and what the kernel
		# decides from cannot drift apart.  sing-box watches that file with
		# fswatch and reloads it in place, so regenerating it here is the
		# whole update path - no service restart.  A failure is logged and
		# not fatal: the previous rule-set is still valid and the firewall
		# has already switched to the new list, which is exactly the state
		# the next run (or the next service start) repairs.
		#
		# china_ip6 is in the same boat for the same reason: geoip-cn.srs and
		# china_ip4.json carry no IPv6 at all, so a mainland destination
		# reached over v6 matches no route rule and falls through to `final`
		# - the proxy - unless there is a v6 rule-set of our own.
		case "$listtype" in
		"china_ip4"|"china_ip6")
			if ucode -S "$SCRIPT_DIR/runtime/china_ip_ruleset.uc" \
				"$RESOURCES_DIR/$listtype.txt" "$RESOURCES_DIR/$listtype.json" >>"$LOG_PATH" 2>&1; then
				log "[$(to_upper "$listtype")] Route-side rule-set regenerated."
				chown sing-box:sing-box "$RESOURCES_DIR/$listtype.json" 2>"/dev/null"
			else
				# The helper exits non-zero on an empty or fully malformed
				# list, and deliberately leaves the previous .json in place.
				# Writing an empty one would be worse than not writing any:
				# the rule would then match nothing, which is the silent
				# "mainland IPv6 goes through the proxy" inversion.
				log "[$(to_upper "$listtype")] Warning: could not regenerate $listtype.json (list has no usable CIDR entry?); the route side keeps the previous list."
			fi
			;;
		esac
	else
		rm -f "$RUN_DIR/$listname"
		log "[$(to_upper "$listtype")] Failed to install update (mv failed)."
		return 1
	fi

	return 0
}

case "$1" in
"china_ip4")
	check_list_update "$1" "1715173329/IPCIDR-CHINA" "master" "ipv4.txt"
	;;
"china_ip6")
	check_list_update "$1" "1715173329/IPCIDR-CHINA" "master" "ipv6.txt"
	;;
"gfw_list")
	check_list_update "$1" "Loyalsoldier/v2ray-rules-dat" "release" "gfw.txt"
	;;
"china_list")
	# Not `sed -i`: the bare -i form is a busybox/GNU extension, and the same
	# script is exercised off-device where a non-busybox sed fails it with
	# "invalid command code".  Edit through a temp file, the way the crontab
	# helper in runtime/service.sh does.
	check_list_update "$1" "Loyalsoldier/v2ray-rules-dat" "release" "direct-list.txt" && \
		sed -e "s/full://g" -e "/:/d" "$RESOURCES_DIR/china_list.txt" > "$RESOURCES_DIR/china_list.txt.hp-new" && \
		mv -f "$RESOURCES_DIR/china_list.txt.hp-new" "$RESOURCES_DIR/china_list.txt" || \
		rm -f "$RESOURCES_DIR/china_list.txt.hp-new"
	;;
*)
	printf '%s\n' "Usage: $0 <china_ip4 / china_ip6 / gfw_list / china_list>"
	exit 1
	;;
esac
