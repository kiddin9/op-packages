#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UCI_DEFAULTS="$ROOT_DIR/root/etc/uci-defaults/40_luci-tailscale"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-openclash-install-test.$$"
CONFIG_DIR="$TMP_DIR/etc/config"
UPGRADE_STATE_DIR="$TMP_DIR/luci-app-tailscale-upgrade"
LEGACY_TAILSCALE_HOTPLUG="$TMP_DIR/40-tailscale"
LEGACY_TAILSCALE_HOTPLUG_BACKUP_DIR="$TMP_DIR/legacy-backup"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -f "$UCI_DEFAULTS" ] || fail "missing package UCI defaults script"
mkdir -p "$TMP_DIR/bin" "$CONFIG_DIR"

cat >"$TMP_DIR/tailscale_secrets" <<'SH'
#!/bin/sh
printf 'secrets %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale_secrets"

cat >"$TMP_DIR/tailscale-openclash-bypass" <<'SH'
#!/bin/sh
printf 'bypass %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale-openclash-bypass"

cat >"$TMP_DIR/tailscale-policy-routing" <<'SH'
#!/bin/sh
printf 'policy %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale-policy-routing"

cat >"$TMP_DIR/bin/uci" <<'SH'
#!/bin/sh
case "$*" in
	'-q get tailscale.settings.enabled')
		printf '%s\n' "${TAILSCALE_ENABLED:-0}"
		exit 0
		;;
	'-q get tailscale_openclash.settings.enabled')
		printf '%s\n' "${OPENCLASH_BYPASS_ENABLED:-1}"
		exit 0
		;;
esac
printf 'uci %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
cat >/dev/null
SH
chmod +x "$TMP_DIR/bin/uci"

cat >"$TMP_DIR/tailscale" <<'SH'
#!/bin/sh
printf 'tailscale %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale"

run_defaults() {
	mode="$1"
	: >"$TMP_DIR/lifecycle.log"
	if [ "$mode" = "without-bypass" ]; then
		rm -f "$TMP_DIR/tailscale-openclash-bypass"
	fi
	# Run an isolated copy so the package script's production absolute paths use
	# the test fixtures without adding test-only hooks to the package itself.
	sed \
		-e "s#/usr/sbin/tailscale_secrets#$TMP_DIR/tailscale_secrets#g" \
		-e "s#/etc/init.d/tailscale-openclash-bypass#$TMP_DIR/tailscale-openclash-bypass#g" \
		-e "s#/etc/init.d/tailscale-policy-routing#$TMP_DIR/tailscale-policy-routing#g" \
		-e "s#/etc/config/tailscale#$CONFIG_DIR/tailscale#g" \
		-e "s#/etc/.luci-app-tailscale-upgrade#$UPGRADE_STATE_DIR#g" \
		"$UCI_DEFAULTS" >"$TMP_DIR/uci-defaults"
	chmod +x "$TMP_DIR/uci-defaults"

	PATH="$TMP_DIR/bin:$PATH" \
	LIFECYCLE_LOG="$TMP_DIR/lifecycle.log" \
	sh "$TMP_DIR/uci-defaults"

	cat "$TMP_DIR/lifecycle.log"
}

enabled_log="$(run_defaults enabled)"
expected_enabled='secrets migrate
bypass enable
bypass start
policy enable
policy start'
[ "$enabled_log" = "$expected_enabled" ] || fail "package defaults must migrate credentials, then enable and start managed helpers\nactual:\n$enabled_log"
cat >"$TMP_DIR/tailscale-openclash-bypass" <<'SH'
#!/bin/sh
printf 'bypass %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale-openclash-bypass"

absent_log="$(run_defaults without-bypass)"
expected_absent='secrets migrate
policy enable
policy start'
[ "$absent_log" = "$expected_absent" ] || fail "missing bypass init script must not prevent policy-routing initialization\nactual:\n$absent_log"

cat >"$TMP_DIR/tailscale-openclash-bypass" <<'SH'
#!/bin/sh
printf 'bypass %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale-openclash-bypass"

run_preinst() {
	awk '
		/^define Package\/luci-app-tailscale\/preinst$/ { in_preinst = 1; next }
		in_preinst && /^endef$/ { exit }
		in_preinst { print }
	' "$ROOT_DIR/Makefile" \
	| sed \
		-e 's/\$\${/${/g' \
		-e "s#/etc/hotplug.d/iface/40-tailscale#$LEGACY_TAILSCALE_HOTPLUG#g" \
		-e "s#/etc/tailscale/luci-app-tailscale-legacy#$LEGACY_TAILSCALE_HOTPLUG_BACKUP_DIR#g" \
		-e "s#/etc/config/tailscale#$CONFIG_DIR/tailscale#g" \
		-e "s#/etc/.luci-app-tailscale-upgrade#$UPGRADE_STATE_DIR#g" \
		>"$TMP_DIR/preinst"
	[ -s "$TMP_DIR/preinst" ] || fail "missing package pre-install configuration snapshot"
	chmod +x "$TMP_DIR/preinst"
	PATH="${PREINST_PATH:-$PATH}" IPKG_INSTROOT='' sh "$TMP_DIR/preinst"
}

cat >"$LEGACY_TAILSCALE_HOTPLUG" <<'EOF'
#!/bin/sh
/etc/init.d/tailscale start &
EOF
cp "$LEGACY_TAILSCALE_HOTPLUG" "$TMP_DIR/40-tailscale.before"

cat >"$CONFIG_DIR/tailscale" <<'EOF'
config tailscale 'settings'
	option enabled '1'
	option hostname 'upgrade-preserved'
EOF
cat >"$CONFIG_DIR/tailscale_openclash" <<'EOF'
config openclash 'settings'
	option enabled '1'
EOF
cat >"$CONFIG_DIR/tailscale_policy_routing" <<'EOF'
config settings 'settings'
	option enabled '1'
EOF
cp "$CONFIG_DIR/tailscale" "$TMP_DIR/tailscale-before-upgrade"
cp "$CONFIG_DIR/tailscale_openclash" "$TMP_DIR/tailscale-openclash-before-upgrade"
cp "$CONFIG_DIR/tailscale_policy_routing" "$TMP_DIR/tailscale-policy-routing-before-upgrade"

run_preinst
[ ! -e "$LEGACY_TAILSCALE_HOTPLUG" ] || fail "pre-install hook must disable the legacy Tailscale interface hotplug starter before extraction"
legacy_hotplug_backup="$(find "$LEGACY_TAILSCALE_HOTPLUG_BACKUP_DIR" -type f -name '40-tailscale.disabled.*' -print)"
[ -n "$legacy_hotplug_backup" ] || fail "pre-install hook must preserve a backup of the disabled legacy Tailscale hotplug starter"
cmp -s "$TMP_DIR/40-tailscale.before" "$legacy_hotplug_backup" || fail "legacy Tailscale hotplug backup must preserve the original script"
[ -f "$UPGRADE_STATE_DIR/tailscale" ] || fail "pre-install hook must snapshot the existing Tailscale UCI config"
[ -f "$UPGRADE_STATE_DIR/tailscale_openclash" ] || fail "pre-install hook must snapshot the existing OpenClash bypass UCI config"
[ -f "$UPGRADE_STATE_DIR/tailscale_policy_routing" ] || fail "pre-install hook must snapshot the existing policy-routing UCI config"
[ -f "$UPGRADE_STATE_DIR/.complete" ] || fail "pre-install hook must only publish a completed configuration snapshot"

# Backup failure must not leave the duplicate hotplug starter executable.
rm -rf "$LEGACY_TAILSCALE_HOTPLUG_BACKUP_DIR"
printf 'not a directory\n' >"$LEGACY_TAILSCALE_HOTPLUG_BACKUP_DIR"
cp "$TMP_DIR/40-tailscale.before" "$LEGACY_TAILSCALE_HOTPLUG"
run_preinst
[ ! -e "$LEGACY_TAILSCALE_HOTPLUG" ] || fail "pre-install hook must disable the legacy starter even when its backup cannot be created"
rm -f "$LEGACY_TAILSCALE_HOTPLUG_BACKUP_DIR"

# If removing the obsolete path itself fails transiently, preinst must make the
# script non-executable before package extraction continues.
mkdir -p "$TMP_DIR/fail-bin" "$LEGACY_TAILSCALE_HOTPLUG_BACKUP_DIR"
cat >"$TMP_DIR/fail-bin/rm" <<EOF
#!/bin/sh
if [ "\$*" = "-f $LEGACY_TAILSCALE_HOTPLUG" ]; then
	exit 1
fi
exec /bin/rm "\$@"
EOF
chmod +x "$TMP_DIR/fail-bin/rm"
cp "$TMP_DIR/40-tailscale.before" "$LEGACY_TAILSCALE_HOTPLUG"
PREINST_PATH="$TMP_DIR/fail-bin:$PATH" run_preinst
[ -e "$LEGACY_TAILSCALE_HOTPLUG" ] || fail "remove-failure fixture must leave the legacy hook path in place"
[ ! -x "$LEGACY_TAILSCALE_HOTPLUG" ] || fail "pre-install hook must make the legacy starter non-executable when removal fails"
chmod 755 "$LEGACY_TAILSCALE_HOTPLUG"
rm -f "$LEGACY_TAILSCALE_HOTPLUG"

# Model package extraction replacing non-conffile files before the new package's
# standard UCI-defaults phase runs.
cat >"$CONFIG_DIR/tailscale" <<'EOF'
config tailscale 'settings'
	option enabled '0'
EOF
cat >"$CONFIG_DIR/tailscale_openclash" <<'EOF'
config openclash 'settings'
	option enabled '0'
EOF
cat >"$CONFIG_DIR/tailscale_policy_routing" <<'EOF'
config settings 'settings'
	option enabled '0'
EOF

# A failed package install can be retried after the new data files have already
# replaced the old config. The second pre-install hook must retain the first
# snapshot instead of replacing it with those defaults.
run_preinst
cmp -s "$TMP_DIR/tailscale-before-upgrade" "$UPGRADE_STATE_DIR/tailscale" || \
	fail "retrying an interrupted upgrade must retain the first Tailscale configuration snapshot"
cmp -s "$TMP_DIR/tailscale-openclash-before-upgrade" "$UPGRADE_STATE_DIR/tailscale_openclash" || \
	fail "retrying an interrupted upgrade must retain the first OpenClash bypass configuration snapshot"
cmp -s "$TMP_DIR/tailscale-policy-routing-before-upgrade" "$UPGRADE_STATE_DIR/tailscale_policy_routing" || \
	fail "retrying an interrupted upgrade must retain the first policy-routing configuration snapshot"

upgrade_defaults_log="$(run_defaults enabled)"
[ "$upgrade_defaults_log" = "$expected_enabled" ] || fail "upgrade defaults must restore configuration before reconciling the bypass\nactual:\n$upgrade_defaults_log"
cmp -s "$TMP_DIR/tailscale-before-upgrade" "$CONFIG_DIR/tailscale" || \
	fail "upgrade must preserve the existing Tailscale UCI configuration"
cmp -s "$TMP_DIR/tailscale-openclash-before-upgrade" "$CONFIG_DIR/tailscale_openclash" || \
	fail "upgrade must preserve the existing OpenClash bypass UCI configuration"
cmp -s "$TMP_DIR/tailscale-policy-routing-before-upgrade" "$CONFIG_DIR/tailscale_policy_routing" || \
	fail "upgrade must preserve the existing policy-routing UCI configuration"
[ ! -e "$UPGRADE_STATE_DIR/tailscale" ] || fail "successful configuration restore must remove the Tailscale snapshot"
[ ! -e "$UPGRADE_STATE_DIR/tailscale_openclash" ] || fail "successful configuration restore must remove the OpenClash bypass snapshot"
[ ! -e "$UPGRADE_STATE_DIR/tailscale_policy_routing" ] || fail "successful configuration restore must remove the policy-routing snapshot"
[ ! -d "$UPGRADE_STATE_DIR" ] || fail "successful configuration restore must remove the private snapshot directory"

: >"$TMP_DIR/lifecycle.log"
LIFECYCLE_LOG="$TMP_DIR/lifecycle.log" "$TMP_DIR/tailscale-openclash-bypass" start
LIFECYCLE_LOG="$TMP_DIR/lifecycle.log" "$TMP_DIR/tailscale" start
upgrade_restart_log="$(cat "$TMP_DIR/lifecycle.log")"
expected_restart_log='bypass start
tailscale start'
[ "$upgrade_restart_log" = "$expected_restart_log" ] || fail "standard package restart must bring the bypass and enabled Tailscale service back after upgrade\nactual:\n$upgrade_restart_log"

disabled_bypass_log="$(OPENCLASH_BYPASS_ENABLED=0 run_defaults enabled)"
[ "$disabled_bypass_log" = "$expected_absent" ] || fail "package lifecycle must not re-enable a bypass the user disabled\nactual:\n$disabled_bypass_log"

# Model a pre-install interruption after a partial state directory was written.
# The next attempt must discard that partial data and publish a complete snapshot.
mkdir -p "$UPGRADE_STATE_DIR"
printf 'partial configuration\n' >"$UPGRADE_STATE_DIR/tailscale"
run_preinst
cmp -s "$TMP_DIR/tailscale-before-upgrade" "$UPGRADE_STATE_DIR/tailscale" || \
	fail "retrying after an interrupted snapshot must replace partial Tailscale data"
cmp -s "$TMP_DIR/tailscale-openclash-before-upgrade" "$UPGRADE_STATE_DIR/tailscale_openclash" || \
	fail "retrying after an interrupted snapshot must replace partial OpenClash data"
cmp -s "$TMP_DIR/tailscale-policy-routing-before-upgrade" "$UPGRADE_STATE_DIR/tailscale_policy_routing" || \
	fail "retrying after an interrupted snapshot must replace partial policy-routing data"
[ -f "$UPGRADE_STATE_DIR/.complete" ] || fail "retrying after an interrupted snapshot must publish a completion marker"
run_defaults enabled >/dev/null
[ ! -d "$UPGRADE_STATE_DIR" ] || fail "restoring a retried snapshot must remove the private state directory"

run_prerm() {
	mode="$1"
	style="${2:-ipk}"
	awk '
		/^define Package\/luci-app-tailscale\/prerm$/ { in_prerm = 1; next }
		in_prerm && /^endef$/ { exit }
		in_prerm { print }
	' "$ROOT_DIR/Makefile" \
	| sed \
		-e 's/\$\${/${/g' \
		-e "s#/usr/sbin/tailscale_openclash_bypass#$TMP_DIR/tailscale_openclash_bypass#g" \
		-e "s#/etc/init.d/tailscale-openclash-bypass#$TMP_DIR/tailscale-openclash-bypass#g" \
		-e "s#/usr/sbin/tailscale_policy_routing#$TMP_DIR/tailscale_policy_routing_helper#g" \
		-e "s#/etc/init.d/tailscale-policy-routing#$TMP_DIR/tailscale-policy-routing#g" \
		-e "s#/etc/init.d/tailscale#$TMP_DIR/tailscale#g" \
		-e "s#/etc/config/tailscale#$CONFIG_DIR/tailscale#g" \
		-e "s#/etc/.luci-app-tailscale-upgrade#$UPGRADE_STATE_DIR#g" \
		>"$TMP_DIR/prerm"
	chmod +x "$TMP_DIR/prerm"

	cat >"$TMP_DIR/tailscale_openclash_bypass" <<'SH'
#!/bin/sh
printf 'helper %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
	chmod +x "$TMP_DIR/tailscale_openclash_bypass"

	cat >"$TMP_DIR/tailscale-openclash-bypass" <<'SH'
#!/bin/sh
printf 'bypass %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
	chmod +x "$TMP_DIR/tailscale-openclash-bypass"

	cat >"$TMP_DIR/tailscale_policy_routing_helper" <<'SH'
#!/bin/sh
printf 'policy-helper %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
[ "${POLICY_CLEANUP_FAIL:-0}" = 1 ] && [ "${1:-}" = cleanup ] && exit 1
exit 0
SH
	chmod +x "$TMP_DIR/tailscale_policy_routing_helper"

	cat >"$TMP_DIR/tailscale-policy-routing" <<'SH'
#!/bin/sh
printf 'policy %s\n' "$*" >>"${LIFECYCLE_LOG:?}"
SH
	chmod +x "$TMP_DIR/tailscale-policy-routing"

	: >"$TMP_DIR/lifecycle.log"
	if [ "$style" = 'apk' ]; then
		IPKG_INSTROOT='' LIFECYCLE_LOG="$TMP_DIR/lifecycle.log" POLICY_CLEANUP_FAIL="${POLICY_CLEANUP_FAIL:-0}" sh "$TMP_DIR/prerm" "$mode" || return 1
	else
		IPKG_INSTROOT='' LIFECYCLE_LOG="$TMP_DIR/lifecycle.log" POLICY_CLEANUP_FAIL="${POLICY_CLEANUP_FAIL:-0}" sh "$TMP_DIR/prerm" "$TMP_DIR/prerm-wrapper" "$mode" || return 1
	fi
	cat "$TMP_DIR/lifecycle.log"
}

upgrade_prerm_log="$(run_prerm upgrade)"
[ -z "$upgrade_prerm_log" ] || fail "package upgrade must preserve helper rules, bypass startup, and Tailscale\nactual:\n$upgrade_prerm_log"
[ ! -d "$UPGRADE_STATE_DIR" ] || fail "package upgrade must not leave removal state or replace the pre-install snapshot"

mkdir -p "$UPGRADE_STATE_DIR" "$UPGRADE_STATE_DIR.pending"
: >"$UPGRADE_STATE_DIR/tailscale"
: >"$UPGRADE_STATE_DIR/tailscale_openclash"
: >"$UPGRADE_STATE_DIR/tailscale_openclash.absent"
: >"$UPGRADE_STATE_DIR/tailscale_policy_routing"
: >"$UPGRADE_STATE_DIR/.complete"
: >"$UPGRADE_STATE_DIR.pending/tailscale"
: >"$UPGRADE_STATE_DIR.pending/tailscale_openclash"
: >"$UPGRADE_STATE_DIR.pending/tailscale_openclash.absent"
: >"$UPGRADE_STATE_DIR.pending/tailscale_policy_routing"
: >"$UPGRADE_STATE_DIR.pending/.complete"

prerm_log="$(run_prerm remove)"
expected_prerm='policy-helper cleanup
policy disable
helper cleanup
bypass disable
tailscale stop'
[ "$prerm_log" = "$expected_prerm" ] || fail "package removal must clean helper rules, disable bypass boot startup, then stop Tailscale\nactual:\n$prerm_log"
[ ! -d "$UPGRADE_STATE_DIR" ] || fail "package removal must remove completed upgrade state"
[ ! -d "$UPGRADE_STATE_DIR.pending" ] || fail "package removal must remove pending upgrade state"

apk_prerm_log="$(run_prerm 1.2.10 apk)"
[ "$apk_prerm_log" = "$expected_prerm" ] || fail "OpenWrt APK pre-deinstall must perform package removal cleanup\nactual:\n$apk_prerm_log"

if POLICY_CLEANUP_FAIL=1 run_prerm remove >/dev/null; then
	fail 'package removal must stop when policy-routing cleanup fails'
fi
[ "$(cat "$TMP_DIR/lifecycle.log")" = 'policy-helper cleanup' ] || \
	fail 'failed policy-routing cleanup must not disable services or stop Tailscale'

echo "tailscale OpenClash install lifecycle tests passed"
