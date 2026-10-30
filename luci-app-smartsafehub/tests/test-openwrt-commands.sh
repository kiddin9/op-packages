#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CHECKER="$ROOT_DIR/tools/check_openwrt_commands.py"
POLICY="$ROOT_DIR/tools/openwrt-25.12-commands.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Never silently enlarge the allowlist to hide a build failure. These applets
# are specifically disabled by OpenWrt 25.12 stock BusyBox configuration.
for applet in od xxd realpath stat wget; do
    if grep -Eq "^${applet}$" "$POLICY"; then
        fail "$applet must not be listed as an OpenWrt 25.12 default command"
    fi
done
for applet in dd sha256sum hexdump cmp; do
    grep -Eq "^${applet}$" "$POLICY" || fail "missing default BusyBox applet: $applet"
done

python3 "$CHECKER" >/dev/null || fail 'current router sources violate the OpenWrt 25.12 command policy'

mkdir -p "$TMP/root/usr/libexec" "$TMP/root/etc/init.d"
FILE="$TMP/root/usr/libexec/smartsafehub-fixture"

check_allowed() {
    python3 "$CHECKER" --root "$TMP" >"$TMP/out" 2>"$TMP/err" || \
        fail "supported commands or quoted shell data were rejected: $(cat "$TMP/err")"
}
check_blocked() {
    applet="$1"
    if python3 "$CHECKER" --root "$TMP" >"$TMP/out" 2>"$TMP/err"; then
        fail "unsupported command $applet escaped the audit"
    fi
    grep -E "unsupported command: ${applet}|unsupported command default: [A-Z_]+=${applet}" "$TMP/err" >/dev/null || \
        fail "failed for the wrong reason (expected $applet): $(cat "$TMP/err")"
}

cat > "$FILE" <<'EOF'
#!/bin/sh
# od -An -tx1 must be ignored: comment, not a command
printf '%s\n' 'od -An -tx1' "xxd and curl are ordinary text"
dd if=/dev/urandom bs=8 count=1 2>/dev/null | sha256sum
awk 'BEGIN { print "xxd is a literal" }'
EOF
check_allowed

cat >> "$FILE" <<'EOF'
od -An -tx1 /dev/urandom
EOF
check_blocked od

cat > "$FILE" <<'EOF'
#!/bin/sh
value="$(xxd /dev/urandom)"
EOF
check_blocked xxd

cat > "$FILE" <<'EOF'
#!/bin/sh
sha256sum /dev/null | base64
EOF
check_blocked base64

cat > "$FILE" <<'EOF'
#!/bin/sh
command -v od >/dev/null || :
EOF
check_blocked od

cat > "$FILE" <<'EOF'
#!/bin/sh
if [ -e /dev/null ]; then python3 --version; fi
EOF
check_blocked python3

# Reject indirect executable defaults as well; this catches a common pattern
# used for configurable commands on production routers.
cat > "$FILE" <<'EOF'
#!/bin/sh
OD_BIN="${SMARTSAFEHUB_TEST_OD_BIN:-od}"
"$OD_BIN" -An -tx1 /dev/urandom
EOF
check_blocked od

# Commands must be audited in init.d and the other shipped shell entry points,
# not only in /usr/libexec.
cat > "$FILE" <<'EOF'
#!/bin/sh
printf 'ok\n'
EOF
cat > "$TMP/root/etc/init.d/smartsafehub-fixture" <<'EOF'
#!/bin/sh /etc/rc.common
xxd /dev/urandom
EOF
check_blocked xxd
rm "$TMP/root/etc/init.d/smartsafehub-fixture"

# `curl` is NOT a default. A single legacy guarded fallback is documented in
# the checker; a new unguarded use must fail even in that same script.
cat > "$TMP/root/usr/libexec/smartsafehub-device" <<'EOF'
#!/bin/sh
curl -fsS https://example.invalid
EOF
check_blocked curl

# An extra unguarded call must not be allowed merely because the same script
# contains the previously reviewed guarded curl fallback.
cat > "$TMP/root/usr/libexec/smartsafehub-device" <<'EOF'
#!/bin/sh
post_json() {
 if command -v curl >/dev/null 2>&1; then
  curl -fsS https://example.invalid
 fi
}
curl -fsS https://example.invalid
EOF
check_blocked curl
rm "$TMP/root/usr/libexec/smartsafehub-device"

cat > "$TMP/root/usr/libexec/smartsafehub-bad-interpreter" <<'EOF'
#!/bin/bash
echo hello
EOF
if python3 "$CHECKER" --root "$TMP" >"$TMP/out" 2>"$TMP/err"; then
    fail 'bash interpreter escaped the audit'
fi
grep -F 'unsupported interpreter' "$TMP/err" >/dev/null || \
    fail 'bash interpreter was not identified correctly'
rm "$TMP/root/usr/libexec/smartsafehub-bad-interpreter"

# Performance mutations use the SAME checker/CI entry point as the BusyBox
# applet audit. A newly added high-cost router command must fail at build time.
check_slow() {
    label="$1"
    if python3 "$CHECKER" --root "$TMP" >"$TMP/out" 2>"$TMP/err"; then
        fail "high-cost router operation escaped the audit: $label"
    fi
    grep -F 'performance risk:' "$TMP/err" >/dev/null || \
        fail "failed for an unrelated reason ($label): $(cat "$TMP/err")"
}

cat > "$FILE" <<'EOF'
#!/bin/sh
# Quoted strings and heredoc content do not execute high-cost commands.
printf '%s\n' 'find /' 'grep -R /' 'while true; do :; done'
cat <<'DATA'
find / -type f
grep -R word /tmp
while true; do echo spin; done
DATA
find /etc/config -maxdepth 1 -type f
while :; do
    [ -r /tmp/done ] && break
    sleep 1
done
EOF
check_allowed

cat > "$FILE" <<'EOF'
#!/bin/sh
find / -type f
EOF
check_slow 'unbounded find /'

cat > "$FILE" <<'EOF'
#!/bin/sh
find "/" -type f
EOF
check_slow 'quoted root scan'

cat > "$FILE" <<'EOF'
#!/bin/sh
LC_ALL=C grep -Rn 'password' /etc
EOF
check_slow 'recursive grep through env prefix'

cat > "$FILE" <<'EOF'
#!/bin/sh
if grep --recursive 'key' /tmp/config; then echo found; fi
EOF
check_slow 'recursive grep long option'

cat > "$FILE" <<'EOF'
#!/bin/sh
du -a /tmp
EOF
check_slow 'per-file du traversal'

cat > "$FILE" <<'EOF'
#!/bin/sh
ls -lR /tmp
EOF
check_slow 'recursive ls'

cat > "$FILE" <<'EOF'
#!/bin/sh
dd if=/dev/urandom bs=1024 of=/tmp/random
EOF
check_slow 'unbounded random read'

cat > "$FILE" <<'EOF'
#!/bin/sh
printf 'x\n' | xargs -P 0 echo
EOF
check_slow 'unbounded xargs parallelism'

cat > "$FILE" <<'EOF'
#!/bin/sh
sleep 0
EOF
check_slow 'zero-delay sleep'

cat > "$FILE" <<'EOF'
#!/bin/sh
while true; do
  echo spin
  :
done
EOF
check_slow 'infinite loop without sleep/break'

cat > "$FILE" <<'EOF'
#!/bin/sh
while true; do printf '%s\n' busy; done
EOF
check_slow 'inline infinite loop without delay'

# A finite, explicitly bounded batch and a throttled daemon are legitimate.
cat > "$FILE" <<'EOF'
#!/bin/sh
dd if=/dev/urandom bs=8 count=1 2>/dev/null | sha256sum
du -s /tmp/smartsafehub
find /etc/smartsafehub -maxdepth 1 -type f
n=0
while :; do
    n=$((n + 1))
    [ "$n" -le 32 ] || break
done
while true; do
    echo periodic
    sleep "$TICK_S"
done
EOF
check_allowed

printf 'PASS: OpenWrt 25.12 BusyBox and performance command audit\n'
