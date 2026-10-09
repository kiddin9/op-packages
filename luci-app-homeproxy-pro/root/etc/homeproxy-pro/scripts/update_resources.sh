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
			local probe_url="https://$base/$listrepo/$list_sha/$api_path"
		else
			local probe_url="https://$base/gh/$listrepo@$list_sha/$api_path"
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

# Put a verified download in place as $listtype.<ext>.
#
# With a `family` set the upstream file is one combined list - cn.list carries
# both address families - and each listtype is one half of it, so the bytes are
# split rather than moved.  That also overrides the "<listtype>.<upstream
# extension>" naming: cn.list would otherwise land as china_ip4.list, while
# every reader - firewall_post.ut's nft set and china_ip_ruleset.uc's generated
# rule-set - has always read .txt.  Splitting writes $listtype.txt directly, so
# nothing downstream changes name or location.
#
# The split writes a sibling temp file and renames it, so a half-written list
# can never become the installed one.  An empty half is refused: an empty
# china_ip6.txt turns v6_handled off outright (see the comment on
# cn_ipv6_ready in firewall_post.ut), and a router that silently stops proxying
# IPv6 is worse than one that keeps the list it had.
#
# The family test is "does the address contain a colon", which is exactly what
# separates an IPv6 CIDR from an IPv4 one, and it is what the rest of the
# pipeline already keys off - see isValidCIDR() in homeproxy-pro.uc.
install_download() {
	local src="$1"
	local listtype="$2"
	local listname="$3"
	local family="$4"

	if [ -z "$family" ]; then
		mv -f "$src" "$RESOURCES_DIR/$listtype.${listname##*.}"
		return $?
	fi

	local dest="$RESOURCES_DIR/$listtype.txt"
	if ! awk -v want="$family" '
		NF == 0 { next }
		{ if ((index($1, ":") > 0) == (want == "v6")) print }
	' "$src" > "$dest.hp-new"; then
		rm -f "$dest.hp-new"
		return 1
	fi
	if [ ! -s "$dest.hp-new" ]; then
		rm -f "$dest.hp-new"
		log "[$(to_upper "$listtype")] Refusing to install: $listname carries no $family entries."
		return 1
	fi
	mv -f "$dest.hp-new" "$dest"
}

# Re-render the firewall's mainland sets from the list that just changed.
#
# The route side goes live on its own - sing-box watches the generated
# rule-set with fswatch - but homeproxy_mainland_addr_v4/v6 live in
# fw4_post.nft, which firewall_post.ut renders and only a start or a restart
# puts in place.  reload does not re-render it (measured on the device: the
# command returns 0, the file's mtime does not move, the set keeps its old
# elements).  So the two halves would read the same file on different days,
# and the gap grows with every update.
#
# The direction that matters is the one where the kernel is *ahead* of the
# file: a segment the list has since dropped still matches the set, and
# `ip daddr @homeproxy_mainland_addr_v4 counter return` returns before the
# redirect - so the connection never reaches the route side that would have
# corrected it.  The other direction (the set missing a newly added segment)
# costs one extra hop into sing-box and still routes correctly.
#
# This mirrors hp_firewall_apply() in runtime/firewall.sh minus the pre-script
# and the upnp restore: only the post-template carries these sets, and neither
# of the other two has anything to do with a resource list.  It deliberately
# does NOT test client_enabled the way start_service does - that check reads
# a routing-mode-dependent helper, and duplicating it here would let the two
# copies drift.  With no client the template renders what start would have
# rendered, so re-rendering is a no-op rather than a risk.
#
# Every failure is non-fatal on purpose.  A list that is installed but not yet
# in the firewall is the one state this script is allowed to leave behind:
# the next scheduled run, or the next service start, closes it.  Failing the
# update instead would turn a cosmetic lag into a resource that can never
# refresh.
sync_firewall_sets() {
	local dest="$RUN_DIR/fw4_post.nft"

	if ! utpl -S "$SCRIPT_DIR/firewall_post.ut" > "$dest.new" 2>"/dev/null"; then
		rm -f "$dest.new"
		log "[$(to_upper "$listtype")] Warning: could not re-render fw4_post.nft; the firewall keeps its previous ruleset. Run /etc/init.d/homeproxy-pro restart to pick this list up."
		return 1
	fi
	mv -f "$dest.new" "$dest"

	if ! fw4 reload >"/dev/null" 2>&1; then
		log "[$(to_upper "$listtype")] Warning: fw4 reload failed; the new set is rendered but the running ruleset was not updated. Run /etc/init.d/homeproxy-pro restart."
		return 1
	fi
	log "[$(to_upper "$listtype")] Firewall mainland sets re-rendered."
}

check_list_update() {
	local listtype="$1"
	local listrepo="$2"
	local listref="$3"
	local listname="$4"
	# v4 / v6 when the upstream file holds both families and has to be split;
	# empty when it is already exactly what listtype wants.
	local family="${5:-}"
	# Where the file lives *inside* the repo, for the commits?path= filter.
	# Equal to the file name for every root-level list, which is all of them
	# used to be - that is why this went unnoticed until a source shipped its
	# list in a subdirectory.  MetaCubeX keeps cn.list under geo/geoip/, and
	# asking the API about "cn.list" there is not a narrower question, it is a
	# different one: it matches no commit, returns [], and the update reports
	# "Failed to get the latest version" on every run while the file itself is
	# perfectly reachable.  Downloaded as $listname regardless.
	local api_path="${6:-$listname}"
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
	# `local x="$(...)"` returns the status of `local`, not of the command
	# substitution - measured on the device: busybox ash gives 0 even when the
	# fetch failed.  That made the branch below dead and reported a network
	# failure as "Failed to get the latest version, please retry later", which
	# loses the difference between "could not fetch" and "fetched, got nothing".
	local list_info
	list_info="$($fetch ${github_header:+--header="$github_header"} -O- "https://api.github.com/repos/$listrepo/commits?sha=$listref&path=$api_path&per_page=1")"
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
		mirror_url="https://raw.githubusercontent.com/$listrepo/$list_sha/$api_path"
	else
		mirror_url="https://$mirror/gh/$listrepo@$list_sha/$api_path"
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
		"https://api.github.com/repos/$listrepo/contents/$api_path?ref=$list_sha" \
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

	if install_download "$RUN_DIR/$listname" "$listtype" "$listname" "$family"; then
		# The split path reads the download and writes the halves, so the
		# download itself is still lying in RUN_DIR; the plain move consumed
		# it.  Either way nothing may be left there for the next run.
		rm -f "$RUN_DIR/$listname"
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
			# The kernel half.  Unconditional, and deliberately outside the
			# if/else above: the nft set is rendered from the .txt, not from
			# the .json, so it can be right even when the generator failed -
			# and a failed generator is exactly when the list on disk is most
			# likely to have changed.  See sync_firewall_sets().
			sync_firewall_sets
			;;
		"china_list")
			# The DNS half of the same split.  It reads this file rather than
			# a remote geosite-geolocation-cn.srs for the same reasons
			# china_ip4.json exists: one list with two readers, and nothing for
			# a cold start to download before the inbounds bind.
			#
			# Normalise FIRST, generate second - and both inside this branch.
			# The order is load-bearing, and it was previously wrong: the sed
			# lived in the `case "china_list"` arm, i.e. after this function had
			# already returned, so the generator was handed the RAW download.
			# That is not a theoretical difference.  Upstream ships `full:`
			# prefixes and the colon-carrying `regexp:` / `keyword:` forms
			# still in the file - 562 of 111,361 lines in the release measured
			# here - and domain_ruleset.uc rejects every entry containing a
			# colon, so 554 real domains were dropped from the DNS split and
			# the only trace was a "skipped N malformed entries" line naming a
			# list that was perfectly well formed.
			#
			# Not `sed -i`: that form is a busybox/GNU extension, and the same
			# script is exercised off-device where a non-busybox sed fails it
			# with "invalid command code".  Edit through a temp file, the way
			# the crontab helper in runtime/service.sh does.
			#
			# A normalisation that fails does not undo the install - the list
			# on disk is the one the upstream commit vouched for, and the
			# firewall renders its nft set from that very file.  The generator
			# is skipped instead, so the DNS side keeps the previous rule-set
			# rather than being rebuilt from a list the sed only half-processed.
			if sed -e "s/full://g" -e "/:/d" "$RESOURCES_DIR/$listtype.txt" \
				> "$RESOURCES_DIR/$listtype.txt.hp-new" \
				&& mv -f "$RESOURCES_DIR/$listtype.txt.hp-new" "$RESOURCES_DIR/$listtype.txt"; then
				if ucode -S "$SCRIPT_DIR/runtime/domain_ruleset.uc" \
					"$RESOURCES_DIR/$listtype.txt" "$RESOURCES_DIR/china-domain.json" >>"$LOG_PATH" 2>&1; then
					log "[CHINA_LIST] DNS-side rule-set regenerated."
					chown sing-box:sing-box "$RESOURCES_DIR/china-domain.json" 2>"/dev/null"
				else
					log "[CHINA_LIST] Warning: could not regenerate china-domain.json (list has no usable domain entry?); the DNS side keeps the previous list."
				fi
			else
				rm -f "$RESOURCES_DIR/$listtype.txt.hp-new"
				log "[CHINA_LIST] Warning: could not normalise the downloaded list; it is installed as downloaded and the DNS side keeps the previous rule-set."
			fi
			;;
		esac
	else
		rm -f "$RUN_DIR/$listname"
		rm -f "$RESOURCES_DIR/$listtype.txt.hp-new"
		log "[$(to_upper "$listtype")] Failed to install update."
		return 1
	fi

	return 0
}

case "$1" in
"china_ip4"|"china_ip6")
	# Both come out of one upstream file and are split by address family - see
	# install_download().  Upstream is MetaCubeX/meta-rules-dat's cn.list, pure
	# CIDR text, which is what keeps the whole existing design intact: it is a
	# file in a git repository, so the blob-id check above vouches for it the
	# same way it vouches for every other list, and one text file feeds both the
	# nft set and the generated route rule-set, so the two readers cannot drift.
	#
	# Why this source and not the 1715173329/IPCIDR-CHINA lists r46 shipped:
	# the old pair missed 62,927,616 CN IPv4 addresses while cn.list misses
	# 1,519,872.  The biggest of those gaps are 59.192.0.0/21 and
	# 175.48.0.0/21, Beijing Telecom backbone ranges, so the cost was not
	# theoretical: destinations resolving into them missed the mainland rule
	# and went to the proxy.
	#
	# cn.list's precision is slightly looser than the old lists' (99.22% of the
	# addresses it lists are CN, against 98.92% before - i.e. it is better on
	# both axes), because it merges neighbouring blocks a little more coarsely
	# than MaxMind does.  IPv6 goes from 1031 to 3446 entries, which also closes
	# an overlap the old ipv6.txt had.
	#
	# CORRECTION (2026-10-08).  The two paragraphs this replaces measured both
	# sources against the APNIC **delegated** statistics and called that the
	# authority - "the registration data every other list is derived from".
	# It is not.  That file's `cc` column is the registry's coarse summary and
	# loses sub-allocations: it reports 8.128.0.0/10 as SG, while the registry's
	# own RDAP object for that range says CN (ALICLOUD).  So the "0.44% missing"
	# figure was measured against a yardstick that is itself wrong, and cannot
	# be used to argue this source is accurate.  Against RDAP the two lists
	# each have errors in OPPOSITE directions - of cn.list's 6163 IPv4 CIDRs,
	# 1054 (about 100 million addresses) are CN per RDAP but absent here, while
	# e.g. 117.134.222.0/23 is PK per RDAP and is wrongly listed as CN.
	#
	# What justifies this source is therefore narrower and more honest than the
	# numbers it replaced: it measurably beats the r46 pair on both recall and
	# precision, it is a file in a git repository so the blob-id check above
	# vouches for it, and one text file feeds both readers so they cannot drift.
	# The delegated statistics were evaluated as a *replacement* source and
	# rejected - deriving the lists from them loses the ~100 million addresses
	# above.  To re-judge any source here, measure against RDAP
	# (https://rdap.apnic.net/ip/<address>), which is the registry database
	# rather than a summary of it.
	# $api_path, not $listname: the commits filter asks where the file is in
	# the repo, which for this source is not the repo root.
	check_list_update "$1" "MetaCubeX/meta-rules-dat" "meta" "cn.list" \
		"$([ "$1" = "china_ip4" ] && echo v4 || echo v6)" "geo/geoip/cn.list"
	;;
"gfw_list")
	check_list_update "$1" "Loyalsoldier/v2ray-rules-dat" "release" "gfw.txt"
	;;
"china_list")
	# The `full:` prefixes and the colon-carrying regexp:/keyword: forms are
	# stripped inside check_list_update, BEFORE the DNS-side rule-set is
	# generated from the list - domain_ruleset.uc rejects any entry containing
	# a colon, so the order decides whether 554 real domains are in the split
	# or silently skipped.  See the case branch there; this arm is only the
	# list's own upstream coordinates.
	#
	# The status has to survive the post-processing.  As one &&...|| chain it
	# did not: when check_list_update returned 3 ("already current") or 1
	# (fetch failed) the chain short-circuited into `rm -f`, whose status 0
	# became the script's - so update_resources_cron.sh counted "no change" as
	# a change and reloaded the service every single day, and the LuCI button
	# reported "Successfully updated." for a fetch that never happened.
	# Measured on the device: china_list exited 0 for both the failure and the
	# up-to-date case, while china_ip4 exited 1 / 3 correctly.
	check_list_update "$1" "Loyalsoldier/v2ray-rules-dat" "release" "direct-list.txt"
	exit $?
	;;
*)
	printf '%s\n' "Usage: $0 <china_ip4 / china_ip6 / gfw_list / china_list>"
	exit 1
	;;
esac
