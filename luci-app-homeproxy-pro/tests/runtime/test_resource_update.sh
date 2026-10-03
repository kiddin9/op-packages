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
while [ $# -gt 0 ]; do
	case "$1" in
	-O) out="$2"; shift 2 ;;
	-O*) out="${1#-O}"; shift ;;
	--user-agent=*) shift ;;
	--header=*) shift ;;
	--timeout=*) shift ;;
	-T) shift 2 ;;
	-s|--spider|-q|--quiet|-4|-6) shift ;;
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
cat > "$WORK/bin/ucode" <<'EOF'
#!/bin/sh
[ -s "$HP_T_LOCAL_BLOB" ] || exit 1
cat "$HP_T_LOCAL_BLOB"
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

printf '%d checks, %d failures\n' "$CHECKS" "$FAILURES"
if [ "$FAILED" != "0" ]; then
	echo "RESOURCE UPDATE TESTS FAILED"
	echo "--- last run output ---"
	cat "$WORK/stdout"
	exit 1
fi

echo "RESOURCE UPDATE TESTS PASSED"
exit 0
