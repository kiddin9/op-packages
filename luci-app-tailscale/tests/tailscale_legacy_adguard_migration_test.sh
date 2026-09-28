#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/root/etc/uci-defaults/40_luci-tailscale"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-legacy-adguard-migration-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

mkdir -p "$TMP_DIR/init.d" "$TMP_DIR/rc.d" "$TMP_DIR/bin"

cat >"$TMP_DIR/init.d/tailscale-adguard-dns" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${LEGACY_SERVICE_LOG:?}"
if [ "${1:-}" = 'disable' ]; then
	rm -f "${LEGACY_ADGUARD_DNS_RC_DIR:?}"/*tailscale-adguard-dns
fi
SH
chmod +x "$TMP_DIR/init.d/tailscale-adguard-dns"
ln -s "$TMP_DIR/init.d/tailscale-adguard-dns" "$TMP_DIR/rc.d/S99tailscale-adguard-dns"

cat >"$TMP_DIR/bin/tailscale-secrets" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${SECRETS_LOG:?}"
[ "${1:-}" = 'migrate' ]
SH
chmod +x "$TMP_DIR/bin/tailscale-secrets"

cat >"$TMP_DIR/bin/uci" <<'SH'
#!/bin/sh
case "${1:-}" in
	-q) exit 1 ;;
	*) exit 1 ;;
esac
SH
chmod +x "$TMP_DIR/bin/uci"

LEGACY_SERVICE_LOG="$TMP_DIR/legacy-service.log"
SECRETS_LOG="$TMP_DIR/secrets.log"
: >"$LEGACY_SERVICE_LOG"
: >"$SECRETS_LOG"
export LEGACY_SERVICE_LOG SECRETS_LOG

run_migration() {
	UPGRADE_STATE_DIR="$TMP_DIR/upgrade" \
	TAILSCALE_SECRETS_BIN="$TMP_DIR/bin/tailscale-secrets" \
	UCI_BIN="$TMP_DIR/bin/uci" \
	OPENCLASH_BYPASS_INIT="$TMP_DIR/init.d/tailscale-openclash-bypass" \
	LEGACY_ADGUARD_DNS_INIT="$TMP_DIR/init.d/tailscale-adguard-dns" \
	LEGACY_ADGUARD_DNS_RC_DIR="$TMP_DIR/rc.d" \
	LEGACY_ADGUARD_DNS_BACKUP_DIR="$TMP_DIR/backups" \
	LUCI_INDEX_CACHE="$TMP_DIR/luci-indexcache" \
	"$SCRIPT"
}

run_migration

[ ! -e "$TMP_DIR/init.d/tailscale-adguard-dns" ] || fail "legacy AdGuard DNS init script must be removed from init.d"
[ ! -e "$TMP_DIR/rc.d/S99tailscale-adguard-dns" ] || fail "legacy AdGuard DNS init link must be removed"
expected_legacy_log="$(printf 'stop\ndisable')"
[ "$(cat "$LEGACY_SERVICE_LOG")" = "$expected_legacy_log" ] || fail "legacy AdGuard DNS service must be stopped and disabled before migration"
[ "$(cat "$SECRETS_LOG")" = 'migrate' ] || fail "credential migration must still run after legacy service cleanup"

backup_dir="$(find "$TMP_DIR/backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$backup_dir" ] || fail "legacy AdGuard DNS service must be backed up before removal"
[ -f "$backup_dir/init" ] || fail "legacy AdGuard DNS init script backup is missing"
[ -f "$backup_dir/tailscale-adguard-dns.disabled" ] || fail "disabled legacy AdGuard DNS init script backup is missing"
expected_rc_link="$(printf 'S99tailscale-adguard-dns\t%s' "$TMP_DIR/init.d/tailscale-adguard-dns")"
[ "$(cat "$backup_dir/rc-links")" = "$expected_rc_link" ] || fail "legacy rc link backup is incomplete"

run_migration
[ "$(cat "$LEGACY_SERVICE_LOG")" = "$expected_legacy_log" ] || fail "legacy service cleanup must be idempotent"
expected_secrets_log="$(printf 'migrate\nmigrate')"
[ "$(cat "$SECRETS_LOG")" = "$expected_secrets_log" ] || fail "credential migration must continue on an idempotent upgrade run"

echo "tailscale legacy AdGuard migration tests passed"
