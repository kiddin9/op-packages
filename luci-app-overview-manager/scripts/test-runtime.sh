#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/includes"
touch \
  "$tmp/includes/00_overview-manager.js" \
  "$tmp/includes/10_system.js" \
  "$tmp/includes/20_memory.js" \
  "$tmp/includes/70_custom.js"

cat >"$tmp/uci" <<'EOF'
#!/bin/sh
while [ "${1:-}" = -q ]; do shift; done
case "${1:-}:${2:-}" in
  get:overview-manager.main.order)
    printf '%s\n' "${FAKE_ORDER:-}"
    ;;
  get:overview-manager.main.hidden)
    printf '%s\n' "${FAKE_HIDDEN:-}"
    ;;
  set:* | commit:*)
    printf '%s\n' "$*" >>"${FAKE_UCI_LOG:?}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod 755 "$tmp/uci"

run() {
  OVERVIEW_MANAGER_INCLUDE_DIR="$tmp/includes" \
    OVERVIEW_MANAGER_UCI="$tmp/uci" \
    FAKE_UCI_LOG="$tmp/uci.log" \
    FAKE_ORDER="${FAKE_ORDER:-}" \
    FAKE_HIDDEN="${FAKE_HIDDEN:-}" \
    "$root/runtime/overview-manager.sh" "$@"
}

expected_files='00_overview-manager.js
10_system.js
20_memory.js
70_custom.js'
[ "$(run files)" = "$expected_files" ]

FAKE_ORDER='70_custom.js 10_system.js' \
FAKE_HIDDEN='20_memory.js' \
  run layout >"$tmp/layout"
grep -qx 'order=70_custom.js 10_system.js' "$tmp/layout"
grep -qx 'hidden=20_memory.js' "$tmp/layout"

: >"$tmp/uci.log"
run save \
  '70_custom.js,10_system.js,20_memory.js,70_custom.js' \
  '20_memory.js'
grep -qx 'set overview-manager.main.order=70_custom.js 10_system.js 20_memory.js' \
  "$tmp/uci.log"
grep -qx 'set overview-manager.main.hidden=20_memory.js' "$tmp/uci.log"
grep -qx 'commit overview-manager' "$tmp/uci.log"

if run save '00_overview-manager.js' '' >/dev/null 2>&1; then
  printf 'self widget was accepted unexpectedly\n' >&2
  exit 1
fi
if run save '99_missing.js' '' >/dev/null 2>&1; then
  printf 'missing widget was accepted unexpectedly\n' >&2
  exit 1
fi

printf 'runtime tests OK\n'
