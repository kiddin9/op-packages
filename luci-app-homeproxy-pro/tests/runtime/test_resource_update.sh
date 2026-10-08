#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# update_resources.sh: the content-verification path.
#
# The download URL is pinned to a commit, and the script now refuses to install
# a file whose git blob id does not match the one GitHub reports for that path
# and commit. The whole point of the check is that it *refuses*, so a driver
# that only walks the happy path would keep passing with the check deleted -
# this one drives the four outcomes and asserts what each leaves behind:
#
#   1. digest matches        -> installed, .ver advanced
#   2. digest differs        -> NOT installed, previous file and .ver intact
#   3. no digest from the API-> NOT installed (fail closed)
#   4. no local digest       -> NOT installed (fail closed)
#   plus: already up to date -> no download at all
#
# Everything external is stubbed (uclient-fetch, jsonfilter, ucode, uci, flock) and the
# script's absolute paths are rewritten into a sandbox, so this is pure shell
# and runs on a laptop, in CI and on a target. The ucode stub answers with a
# fixed digest: what the *shipped* helper computes is
# tests/ucode/test_resource_blob_sha.sh's job, which checks it against git.
#
# Usage: sh tests/runtime/test_resource_update.sh <repo-root> [work-dir]

set -u

ROOT="$(cd "${1:-.}" && pwd)"
WORK="${2:-/tmp/hp-resource-update-test}"

rm -rf "$WORK"
mkdir -p "$WORK/scripts" "$WORK/resources" "$WORK/run" "$WORK/bin"

FAILED=0
CHECKS=0
FAILURES=0

expect() {
	# expect <name> <actual> <expected>
	CHECKS=$((CHECKS + 1))
	if [ "$2" = "$3" ]; then
		echo "PASS: $1"
	else
		echo "FAIL: $1 (expected '$3', got '$2')"
		FAILED=1
		FAILURES=$((FAILURES + 1))
	fi
}

# --- stage the script and its helper ----------------------------------------
cp "$ROOT/root/etc/homeproxy-pro/scripts/update_resources.sh" "$WORK/scripts/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/resource_blob_sha.uc" "$WORK/scripts/"

# Rewrite the two absolute runtime paths. The anchors are asserted below: a sed
# that quietly stopped matching would leave the test writing to /etc.
sed -e "s|^RESOURCES_DIR=\"/etc/\$NAME/resources\"|RESOURCES_DIR=\"$WORK/resources\"|" \
    -e "s|^RUN_DIR=\"/var/run/\$NAME\"|RUN_DIR=\"$WORK/run\"|" \
    "$WORK/scripts/update_resources.sh" > "$WORK/scripts/update_resources.sh.new"
mv -f "$WORK/scripts/update_resources.sh.new" "$WORK/scripts/update_resources.sh"
for anchor in "RESOURCES_DIR=\"$WORK/resources\"" "RUN_DIR=\"$WORK/run\""; do
	grep -qF "$anchor" "$WORK/scripts/update_resources.sh" || {
		echo "FAIL: could not sandbox update_resources.sh - missing anchor: $anchor"
		exit 1
	}
done

# --- stubs ------------------------------------------------------------------
# uclient-fetch serves three shapes, chosen by the URL: the commit list, the
# contents metadata, and the file itself. What the contents API reports and what
# the file contains are control files, so each case can make them agree or not.
#
# It replaced a wget stub, and the option handling is the point rather than an
# afterthought: this is the only thing that would have noticed the real
# regression, where the script passed GNU-only flags (--timeout= --spider)
# that a busybox-wget target rejects outright. A permissive stub ("ignore what
# you do not recognise") cannot catch that, so unknown options are a hard
# failure here - the same way the applet behaves.
cat > "$WORK/bin/uclient-fetch" <<'EOF'
#!/bin/sh
url=""
out=""
probe=0
while [ $# -gt 0 ]; do
	case "$1" in
	-O) out="$2"; shift 2 ;;
	-O*) out="${1#-O}"; shift ;;
	--user-agent=*) shift ;;
	--header=*) shift ;;
	--timeout=*) shift ;;
	-T) shift 2 ;;
	-s|--spider) probe=1; shift ;;
	-q|--quiet|-4|-6) shift ;;
	-*) printf 'uclient-fetch: unrecognized option: %s\n' "${1#-}" >&2
	    printf 'Usage: uclient-fetch [options] <URL>\n' >&2
	    exit 1 ;;
	*) url="$1"; shift ;;
	esac
done
# "-" means stdout, which is the applet's own convention - getting that wrong
# writes the body to a file named "-" and leaves the parser reading nothing.
emit() {
	if [ -n "$out" ] && [ "$out" != "-" ]; then
		printf '%s' "$1" > "$out"
	else
		printf '%s' "$1"
	fi
}
case "$url" in
*api.github.com/*/commits*)
	# Filtered by path, the way the real endpoint is.  Asking for a file
	# that is not at that path is not a narrower question, it is a different
	# one: it matches no commit and comes back [].  That is the whole reason
	# the in-repo path is a separate argument from the file name, and it is
	# what this branch can now catch - every list this project ships used to
	# live in the repo root, so path= and the file name were the same string
	# and nothing could tell them apart.
	case "$url" in
	*repos/MetaCubeX/*)
		case "$url" in
		*"path=geo/geoip/cn.list"*) emit "$(cat "$HP_T_API_COMMITS")" ;;
		*) emit '[]' ;;
		esac
		;;
	*) emit "$(cat "$HP_T_API_COMMITS")" ;;
	esac
	;;
*api.github.com/*/contents*) emit "$(cat "$HP_T_API_CONTENTS")" ;;
*)
	# A spider probe (-s) checks reachability only, and its stdout is captured
	# by pick_mirror into $base - so emitting a body here would splice the body
	# into the mirror name and every later URL would be nonsense.  The real
	# applet prints nothing for a probe.
	[ "$probe" = "0" ] || exit 0
	if [ -n "${HP_T_FETCH_FAIL:-}" ]; then exit 1; fi
	# The same wrong-path mistake reaches the download as a 404, and
	# pick_mirror turns that into "all mirrors unreachable" - a second
	# symptom of the one bug, reported as an unrelated-looking network
	# failure.  Scoped to this source so the other lists, whose file name is
	# their in-repo path, keep resolving.
	case "$url" in
	*MetaCubeX/meta-rules-dat*)
		case "$url" in
		*geo/geoip/cn.list*) ;;
		*) exit 1 ;;
		esac
		;;
	esac
	emit "$(cat "$HP_T_BODY")"
	;;
esac
exit 0
EOF

# jsonfilter: answer the two expressions the script actually asks for. A stub
# that simply returned "the first sha" also answered the commit-date query with
# the commit sha, which silently made the expected .ver string wrong - the real
# jsonfilter reads the expression it is handed, so this one does too.
cat > "$WORK/bin/jsonfilter" <<'EOF'
#!/bin/sh
expr=""
for a in "$@"; do expr="$a"; done
payload="$(cat)"
case "$expr" in
*commit.committer.date*)
	printf '%s' "$payload" | sed -n 's/.*"date"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
	;;
*)
	printf '%s' "$payload" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
	;;
esac
EOF

# ucode: the shipped helper's contract, answered from a control file. An empty
# control file means "cannot compute" (the helper exits 1 and prints nothing).
#
# It has to tell the two callers apart, because the china_list case below is
# about the ORDER they are called in: resource_blob_sha.uc prints a digest on
# stdout, while the rule-set generators take <source> <destination> and write a
# file.  A stub that answered both the same way could not observe whether the
# generator was handed the raw download or the normalised list, which is the
# whole point of that case.
cat > "$WORK/bin/ucode" <<'EOF'
#!/bin/sh
# -S <script> [args...]
script="$2"
case "$script" in
*resource_blob_sha.uc)
	[ -s "$HP_T_LOCAL_BLOB" ] || exit 1
	cat "$HP_T_LOCAL_BLOB"
	;;
*)
	# A rule-set generator.  Record the CONTENT of the source it was handed,
	# not its path: the path is the same file in both the broken and the fixed
	# order, so only the content can tell them apart.  Copy rather than record
	# the name, because the generator runs after the file has been normalised
	# and re-reading it later would see the normalised bytes either way.
	cat "$3" > "$HP_T_SEEN_SOURCE" 2>/dev/null
	exit 0
	;;
esac
EOF

# uci/flock are only reached for the token and the lock; both are no-ops here.
cat > "$WORK/bin/uci" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$WORK/bin/flock" <<'EOF'
#!/bin/sh
exit 0
EOF
# utpl renders firewall_post.ut into the file named by -O-less stdout; the stub
# writes a marker line and honours a failure switch, which is all the two
# cases below need.  fw4 records that it was called and honours its own.
cat > "$WORK/bin/utpl" <<'EOF'
#!/bin/sh
[ -n "${HP_T_UTPL_FAIL:-}" ] && exit 1
printf 'rendered-from-utpl\n'
exit 0
EOF
cat > "$WORK/bin/fw4" <<'EOF'
#!/bin/sh
[ -n "$HP_T_FW4_CALLED" ] && printf 'called\n' >> "$HP_T_FW4_CALLED"
[ -n "${HP_T_FW4_FAIL:-}" ] && exit 1
exit 0
EOF
chmod +x "$WORK/bin/"*

PATH="$WORK/bin:$PATH"
export PATH

# The script's shebang is /bin/sh, so run it under the strictest /bin/sh this
# host has: dash rejects the multi-digit file descriptor and the `&>` that
# busybox ash and bash accept greedily, and "exec: 200: not found" was how that
# reached CI. On a target there is no dash and busybox ash is the real thing.
RUN_SH="sh"
if command -v dash > "/dev/null" 2>&1; then
	RUN_SH="dash"
fi
echo "running update_resources.sh under: $RUN_SH"

# --- fixtures ---------------------------------------------------------------
API_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
LOCAL_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OUTPUT_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

cat > "$WORK/api-commits.json" <<EOF
[{"sha":"$API_SHA","commit":{"committer":{"date":"2026-01-02T03:04:05Z"}}}]
EOF

write_contents_json() {
	# write_contents_json <blob-sha-or-empty>
	# The upstream file is cn.list, not ipv4.txt: it carries both address
	# families and each listtype takes one half of it (install_download).
	if [ -n "$1" ]; then
		printf '{"name":"cn.list","size":6,"sha":"%s"}' "$1" > "$WORK/api-contents.json"
	else
		printf '{"name":"cn.list","size":6}' > "$WORK/api-contents.json"
	fi
}

# Mixed on purpose: china_ip4 must end up holding only the first line, and the
# IPv6 line is what the china_ip6 cases below split out.  Keeping "fresh" as the
# single IPv4 line means the cases that only care about the blob-id handshake
# keep asserting on "fresh" unchanged.
printf 'fresh\n2001:db8::/32\n' > "$WORK/body.txt"
printf 'stale-installed-copy\n' > "$WORK/resources/china_ip4.txt"
printf 'OLDVERSION' > "$WORK/resources/china_ip4.ver"

export HP_T_API_COMMITS="$WORK/api-commits.json"
export HP_T_API_CONTENTS="$WORK/api-contents.json"
export HP_T_BODY="$WORK/body.txt"
# Where the ucode stub records the source file a rule-set generator was given.
# Not a constant inside the stub: the china_list case has to reset it between
# runs, and a run in which the generator was never called has to be visible as
# an absent file rather than as the previous run's leftover.
export HP_T_SEEN_SOURCE="$WORK/seen-source"
# The digest the ucode stub answers with.  Set here as well as inside run_case:
# run_case is invoked in a command substitution, so its own exports die with
# the subshell and any case that does not go through it would find the
# variable unset - which the stub reads as "cannot compute a digest" and the
# script reports as a refusal, i.e. a failure that has nothing to do with what
# the case is testing.
export HP_T_LOCAL_BLOB="$WORK/local-blob"
printf '%s' "$LOCAL_SHA" > "$HP_T_LOCAL_BLOB"
write_contents_json "$LOCAL_SHA"

run_case() {
	# run_case <local-blob-file-content> <contents-api-sha>
	printf '%s' "$1" > "$WORK/local-blob"
	write_contents_json "$2"
	export HP_T_LOCAL_BLOB="$WORK/local-blob"
	"$RUN_SH" "$WORK/scripts/update_resources.sh" china_ip4 > "$WORK/stdout" 2>&1
	echo $?
}

reset_state() {
	printf 'stale-installed-copy\n' > "$WORK/resources/china_ip4.txt"
	printf 'OLDVERSION' > "$WORK/resources/china_ip4.ver"
	rm -f "$WORK/run/homeproxy-pro.log" "$WORK/resources/china_ip4.updated_at"
}

echo "== case 1: the digest matches -> installed =="
reset_state
rc="$(run_case "$LOCAL_SHA" "$LOCAL_SHA")"
expect "exit status 0" "$rc" "0"
expect "the new list was installed" "$(cat "$WORK/resources/china_ip4.txt")" "fresh"
expect "the .ver was advanced to the resolved commit" \
	"$(cat "$WORK/resources/china_ip4.ver")" "2026-01-02 $API_SHA"
expect "the success is logged" \
	"$(grep -c 'Successfully updated via' "$WORK/run/homeproxy-pro.log")" "1"

echo "== case 2: the digest differs -> refused, previous state kept =="
reset_state
rc="$(run_case "$OUTPUT_SHA" "$LOCAL_SHA")"
expect "exit status non-zero" "$rc" "1"
expect "the installed list is untouched" \
	"$(cat "$WORK/resources/china_ip4.txt")" "stale-installed-copy"
expect "the .ver is untouched" "$(cat "$WORK/resources/china_ip4.ver")" "OLDVERSION"
expect "no .updated_at was written" "$([ -e "$WORK/resources/china_ip4.updated_at" ] && echo yes || echo no)" "no"
expect "the refusal is logged with both ids" \
	"$(grep -c "does not match the content of commit $API_SHA" "$WORK/run/homeproxy-pro.log")" "1"
expect "the downloaded copy was discarded" "$([ -e "$WORK/run/cn.list" ] && echo yes || echo no)" "no"

echo "== case 3: no blob id from the API -> refused =="
reset_state
rc="$(run_case "$LOCAL_SHA" "")"
expect "exit status non-zero" "$rc" "1"
expect "the installed list is untouched" \
	"$(cat "$WORK/resources/china_ip4.txt")" "stale-installed-copy"
expect "the .ver is untouched" "$(cat "$WORK/resources/china_ip4.ver")" "OLDVERSION"
expect "the reason is logged" \
	"$(grep -c 'GitHub reports no blob id' "$WORK/run/homeproxy-pro.log")" "1"
# Not merely "it refused": with the API check skipped, the comparison still
# refuses (an empty API id never equals a real one), so without this the check
# could be deleted and the case would still pass on the wrong reason.
expect "the API-missing path is the one taken" \
	"$(grep -c 'does not match the content of commit' "$WORK/run/homeproxy-pro.log")" "0"

echo "== case 4: no local digest -> refused =="
reset_state
rc="$(run_case "" "$LOCAL_SHA")"
expect "exit status non-zero" "$rc" "1"
expect "the installed list is untouched" \
	"$(cat "$WORK/resources/china_ip4.txt")" "stale-installed-copy"
expect "the reason is logged" \
	"$(grep -c 'cannot compute the blob id' "$WORK/run/homeproxy-pro.log")" "1"
expect "the local-digest path is the one taken" \
	"$(grep -c 'does not match the content of commit' "$WORK/run/homeproxy-pro.log")" "0"

echo "== case 5: already at the resolved commit -> nothing downloaded =="
reset_state
printf '2026-01-02 %s' "$API_SHA" > "$WORK/resources/china_ip4.ver"
: > "$WORK/run/homeproxy-pro.log"
rc="$(run_case "$LOCAL_SHA" "$LOCAL_SHA")"
expect "exit status 3 (up to date)" "$rc" "3"
expect "the installed list is untouched" \
	"$(cat "$WORK/resources/china_ip4.txt")" "stale-installed-copy"
expect "it says so in the log" \
	"$(grep -c 'already at the latest version' "$WORK/run/homeproxy-pro.log")" "1"

echo "== case 6: china_list is normalised BEFORE the rule-set is generated =="
# The regression this case exists for.  Upstream ships the list with `full:`
# prefixes and the colon-carrying regexp:/keyword: forms still in it - 562 of
# 111,361 lines in the release this was measured against - and
# domain_ruleset.uc rejects every entry containing a colon.  The sed that
# strips them used to live in the `case "china_list"` arm, i.e. AFTER
# check_list_update had returned, so the generator was handed the raw download
# and 554 real domains were skipped out of the DNS split.  The only trace was a
# "skipped N malformed entries" line blaming a perfectly well-formed list.
#
# Asserting the CONTENT the generator received is the only version of this that
# works: both the broken and the fixed order call the generator exactly once
# and exit 0, so a "was it called" assertion passes either way.
reset_state
rm -f "$WORK/resources/china-domain.json" "$HP_T_SEEN_SOURCE"
printf 'stale\n' > "$WORK/resources/china_list.txt"
printf 'OLDVERSION' > "$WORK/resources/china_list.ver"
cat > "$WORK/body.txt" <<'BODY'
plain.example.com
full:prefixed.example.com
regexp:.+\.cn$
keyword:ads
BODY
: > "$WORK/run/homeproxy-pro.log"
rc="$("$RUN_SH" "$WORK/scripts/update_resources.sh" china_list > "$WORK/stdout" 2>&1; echo $?)"
expect "exit status 0" "$rc" "0"
expect "the installed list has no colon left" \
	"$(grep -c ':' "$WORK/resources/china_list.txt" || true)" "0"
expect "the bare name survived" \
	"$(grep -c '^plain.example.com$' "$WORK/resources/china_list.txt" || true)" "1"
expect "the full: prefix was stripped, not the line dropped" \
	"$(grep -c '^prefixed.example.com$' "$WORK/resources/china_list.txt" || true)" "1"
expect "the generator was given the NORMALISED list" \
	"$(grep -c 'full:' "$HP_T_SEEN_SOURCE" 2>/dev/null)" "0"
expect "and it was given the un-prefixed name" \
	"$(grep -c '^prefixed.example.com$' "$HP_T_SEEN_SOURCE" 2>/dev/null)" "1"
expect "the .ver advanced, so the next run short-circuits" \
	"$(cat "$WORK/resources/china_list.ver")" "2026-01-02 $API_SHA"

echo "== case 7: china_list surfaces the helper's failure, not success =="
# The status has to survive: the LuCI button maps rc to a message and
# update_resources_cron.sh reloads the service only on rc 0.  A run that
# neither installed nor verified anything must not report either.
reset_state
# china_list has its own installed copy, and case 6 left a real one behind -
# the fixture has to be put back or "untouched" is asserted against case 6's
# output rather than against the pre-update state.
printf 'stale\n' > "$WORK/resources/china_list.txt"
printf 'OLDVERSION' > "$WORK/resources/china_list.ver"
rm -f "$HP_T_SEEN_SOURCE"
: > "$WORK/run/homeproxy-pro.log"
# The digest has to be forced to a MISMATCH for this case: the baseline set
# above matches by default, and a matching digest would install the list and
# exit 0 - the case would then be asserting the happy path under a name that
# says it is testing the refusal.
printf '%s' "$OUTPUT_SHA" > "$HP_T_LOCAL_BLOB"
write_contents_json "$LOCAL_SHA"
expect "a digest mismatch exits non-zero" \
	"$("$RUN_SH" "$WORK/scripts/update_resources.sh" china_list > "$WORK/stdout" 2>&1; echo $?)" "1"
expect "the previous list is untouched" \
	"$(cat "$WORK/resources/china_list.txt")" "stale"
expect "the .ver is untouched" "$(cat "$WORK/resources/china_list.ver")" "OLDVERSION"
expect "the generator was never called" \
	"$([ -e "$HP_T_SEEN_SOURCE" ] && echo yes || echo no)" "no"

echo "== case 8: cn.list is split by address family =="
# Both IP lists come out of one upstream file now (MetaCubeX cn.list), so the
# install step splits rather than moves.  What has to hold: each listtype ends
# up at its own .txt name with only its own family in it, and the combined
# download is not left lying in RUN_DIR for the next run to trip over.
reset_state
printf 'OLDVERSION' > "$WORK/resources/china_ip6.ver"
rm -f "$WORK/resources/china_ip6.txt"
# Set here rather than relying on the top-of-file fixture: case 6 overwrote
# body.txt with its own domain lines.
printf '1.0.0.0/24\n2001:db8::/32\n' > "$WORK/body.txt"
: > "$WORK/run/homeproxy-pro.log"
printf '%s' "$LOCAL_SHA" > "$HP_T_LOCAL_BLOB"
rc="$("$RUN_SH" "$WORK/scripts/update_resources.sh" china_ip6 > "$WORK/stdout" 2>&1; echo $?)"
expect "exit status 0" "$rc" "0"
expect "china_ip6.txt was created by the split" \
	"$(cat "$WORK/resources/china_ip6.txt" 2>/dev/null)" "2001:db8::/32"
expect "it holds no IPv4 entry" \
	"$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/' "$WORK/resources/china_ip6.txt" || true)" "0"
expect "its .ver advanced like the v4 one" \
	"$(cat "$WORK/resources/china_ip6.ver")" "2026-01-02 $API_SHA"
expect "the combined download was cleaned out of RUN_DIR" \
	"$([ -e "$WORK/run/cn.list" ] && echo yes || echo no)" "no"
expect "no half-written temp file survived" \
	"$([ -e "$WORK/resources/china_ip6.txt.hp-new" ] && echo yes || echo no)" "no"

echo "== case 9: a family with no entries is refused, not installed empty =="
# The failure this guards is silent: an empty china_ip6.txt makes
# firewall_post.ut count zero usable prefixes and turn v6_handled off, after
# which every mainland IPv6 connection goes to the proxy - with no error
# anywhere.  Keeping the previous list is the only acceptable outcome.
reset_state
printf 'stale-v6-copy\n' > "$WORK/resources/china_ip6.txt"
printf 'OLDVERSION' > "$WORK/resources/china_ip6.ver"
printf 'only-v4-here/24\n' > "$WORK/body.txt"
: > "$WORK/run/homeproxy-pro.log"
printf '%s' "$LOCAL_SHA" > "$HP_T_LOCAL_BLOB"
rc="$("$RUN_SH" "$WORK/scripts/update_resources.sh" china_ip6 > "$WORK/stdout" 2>&1; echo $?)"
expect "exit status non-zero" "$rc" "1"
expect "the previous v6 list is untouched" \
	"$(cat "$WORK/resources/china_ip6.txt")" "stale-v6-copy"
expect "its .ver is untouched" "$(cat "$WORK/resources/china_ip6.ver")" "OLDVERSION"
expect "the reason is logged" \
	"$(grep -c 'carries no v6 entries' "$WORK/run/homeproxy-pro.log")" "1"
expect "no empty temp file survived" \
	"$([ -e "$WORK/resources/china_ip6.txt.hp-new" ] && echo yes || echo no)" "no"

echo "== case 10: a successful IP update re-renders the firewall sets =="
# The two halves of the mainland split read the same file but go live on
# different triggers: sing-box watches the generated rule-set, while the nft
# set is rendered into fw4_post.nft and otherwise only a start/restart puts
# it in place.  Without this step the kernel's copy silently ages past the
# file's, and a segment the list has since dropped keeps matching
# `ip daddr @homeproxy_mainland_addr_v4 counter return` - which returns before
# the redirect, so the route side never gets to correct it.
reset_state
printf 'v4-here/24\n2001:db8::/32\n' > "$WORK/body.txt"
printf 'stale-rendered-ruleset\n' > "$WORK/run/fw4_post.nft"
rm -f "$WORK/run/fw4_post.nft.new"
export HP_T_FW4_CALLED="$WORK/fw4-called"
rm -f "$HP_T_FW4_CALLED"
: > "$WORK/run/homeproxy-pro.log"
rc="$("$RUN_SH" "$WORK/scripts/update_resources.sh" china_ip4 > "$WORK/stdout" 2>&1; echo $?)"
expect "exit status 0" "$rc" "0"
expect "fw4_post.nft was re-rendered from the new list" \
	"$(cat "$WORK/run/fw4_post.nft" 2>/dev/null)" "rendered-from-utpl"
expect "fw4 reload ran" \
	"$(grep -c 'called' "$HP_T_FW4_CALLED" 2>/dev/null || echo 0)" "1"
expect "no temp file left behind" \
	"$([ -e "$WORK/run/fw4_post.nft.new" ] && echo yes || echo no)" "no"
expect "the success is logged" \
	"$(grep -c 'Firewall mainland sets re-rendered' "$WORK/run/homeproxy-pro.log")" "1"

echo "== case 11: a failed render is warned about, not fatal =="
# Failing the update would be worse than the lag it is reporting: the list on
# disk is already the one the commit vouched for, and a resource that can
# never refresh is a far bigger problem than one that is briefly not in the
# firewall.  The previous ruleset has to survive, or a bad render takes the
# whole intercept layer down with it.
reset_state
printf 'v4-here/24\n2001:db8::/32\n' > "$WORK/body.txt"
printf 'known-good-ruleset\n' > "$WORK/run/fw4_post.nft"
rm -f "$WORK/run/fw4_post.nft.new"
export HP_T_UTPL_FAIL=1
: > "$WORK/run/homeproxy-pro.log"
# Cleared because the point of this case is that a failed render must not
# reach fw4 at all - inheriting case 10's record would make the assertion
# pass for the wrong reason if the branch started reloading anyway.
rm -f "$HP_T_FW4_CALLED"
rc="$("$RUN_SH" "$WORK/scripts/update_resources.sh" china_ip4 > "$WORK/stdout" 2>&1; echo $?)"
unset HP_T_UTPL_FAIL
expect "the update still succeeded" "$rc" "0"
expect "the list was still installed" \
	"$(cat "$WORK/resources/china_ip4.txt")" "v4-here/24"
expect "the previous ruleset is untouched" \
	"$(cat "$WORK/run/fw4_post.nft")" "known-good-ruleset"
expect "no half-written temp file survived" \
	"$([ -e "$WORK/run/fw4_post.nft.new" ] && echo yes || echo no)" "no"
expect "fw4 was NOT reloaded" \
	"$(grep -c 'called' "$HP_T_FW4_CALLED" 2>/dev/null || echo 0)" "0"
expect "the warning names the manual recovery" \
	"$(grep -c 'could not re-render fw4_post.nft' "$WORK/run/homeproxy-pro.log")" "1"

printf '%d checks, %d failures\n' "$CHECKS" "$FAILURES"
if [ "$FAILED" != "0" ]; then
	echo "RESOURCE UPDATE TESTS FAILED"
	echo "--- last run output ---"
	cat "$WORK/stdout"
	exit 1
fi

echo "RESOURCE UPDATE TESTS PASSED"
exit 0
