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
*api.github.com/*/commits*) emit "$(cat "$HP_T_API_COMMITS")" ;;
*api.github.com/*/contents*) emit "$(cat "$HP_T_API_CONTENTS")" ;;
*)
	# A spider probe (-s) checks reachability only, and its stdout is captured
	# by pick_mirror into $base - so emitting a body here would splice the body
	# into the mirror name and every later URL would be nonsense.  The real
	# applet prints nothing for a probe.
	[ "$probe" = "0" ] || exit 0
	if [ -n "${HP_T_FETCH_FAIL:-}" ]; then exit 1; fi
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
	if [ -n "$1" ]; then
		printf '{"name":"ipv4.txt","size":6,"sha":"%s"}' "$1" > "$WORK/api-contents.json"
	else
		printf '{"name":"ipv4.txt","size":6}' > "$WORK/api-contents.json"
	fi
}

printf 'fresh\n' > "$WORK/body.txt"
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
expect "the downloaded copy was discarded" "$([ -e "$WORK/run/ipv4.txt" ] && echo yes || echo no)" "no"

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

printf '%d checks, %d failures\n' "$CHECKS" "$FAILURES"
if [ "$FAILED" != "0" ]; then
	echo "RESOURCE UPDATE TESTS FAILED"
	echo "--- last run output ---"
	cat "$WORK/stdout"
	exit 1
fi

echo "RESOURCE UPDATE TESTS PASSED"
exit 0
