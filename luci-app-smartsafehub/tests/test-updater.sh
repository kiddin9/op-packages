#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export SMARTSAFEHUB_COMMON_LIB="$ROOT_DIR/root/usr/lib/smartsafehub/common.sh"
UPDATER="$ROOT_DIR/root/usr/libexec/smartsafehub-updater"
MAKEFILE="$ROOT_DIR/Makefile"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	file="$1"
	needle="$2"
	grep -F -- "$needle" "$file" >/dev/null 2>&1 || fail "$file does not contain: $needle"
}

assert_not_contains() {
	file="$1"
	needle="$2"
	if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
		fail "$file unexpectedly contains: $needle"
	fi
}

assert_contains "$MAKEFILE" 'LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +ucode +ucode-mod-ubus +ucode-mod-fs +ucode-mod-uci +procd +uclient-fetch +jsonfilter +igmpproxy +safeshield'
SAFESHIELD_MIN_VERSION="$(sed -n 's/^LUCI_EXTRA_DEPENDS:=safeshield (>=\([^)]*\))$/\1/p' "$MAKEFILE")"
[ -n "$SAFESHIELD_MIN_VERSION" ] || fail 'unable to read safeshield minimum version from LUCI_EXTRA_DEPENDS'
PKG_VERSION="$(awk -F ':=' '$1 == "PKG_VERSION" { print $2; exit }' "$MAKEFILE")"
PKG_RELEASE="$(awk -F ':=' '$1 == "PKG_RELEASE" { print $2; exit }' "$MAKEFILE")"
RELEASE_VERSION="${PKG_VERSION}-r${PKG_RELEASE}"

mkdir -p "$TMP/bin" "$TMP/repos" "$TMP/pkg" "$TMP/releases"
printf '%s\n' 'luci-app-smartsafehub' > "$TMP/world"
printf '%s\n' 'https://repo.smartsafehub.com/stable/packages/x86_64/smartsafehub/packages.adb' > "$TMP/repos/smartsafehub.list"

cat > "$TMP/bin/uci" <<'MOCKUCI'
#!/bin/sh
[ "${1:-}" = '-q' ] && shift
[ "${1:-}" = 'get' ] || exit 1
case "${2:-}" in
	smartsafehub.updates.check_enabled) echo 1 ;;
	smartsafehub.updates.check_interval_s) echo 21600 ;;
	smartsafehub.updates.auto_install) echo 0 ;;
	smartsafehub.updates.auto_install_time) echo '03:00' ;;
	smartsafehub.updates.repository_host) echo 'repo.smartsafehub.com' ;;
	*) exit 1 ;;
esac
MOCKUCI
chmod +x "$TMP/bin/uci"

cat > "$TMP/pkg/safeshield.installed" <<EOF2
0.0.0
EOF2
cat > "$TMP/pkg/safeshield.available" <<EOF2
$SAFESHIELD_MIN_VERSION
EOF2
cat > "$TMP/pkg/luci-app-smartsafehub.installed" <<EOF2
0.2.1-r1
EOF2
cat > "$TMP/pkg/luci-app-smartsafehub.available" <<EOF2
$RELEASE_VERSION
EOF2
cat > "$TMP/releases/index.json" <<EOF2
{
  "schema_version": 1,
  "package": "luci-app-smartsafehub",
  "releases": [
    { "version": "$RELEASE_VERSION", "date": "2026-08-28" },
    { "version": "0.2.3-r1", "date": "2026-08-28" },
    { "version": "0.2.2-r1", "date": "2026-08-28" },
    { "version": "0.2.1-r1", "date": "2026-08-28" },
    { "version": "0.2.0-r1", "date": "2026-08-21" }
  ]
}
EOF2

for version in "$RELEASE_VERSION" 0.2.3-r1 0.2.2-r1; do
  cat > "$TMP/releases/$version.json" <<EOF2
{
  "schema_version": 1,
  "package": "luci-app-smartsafehub",
  "version": "$version",
  "date": "2026-08-28",
  "summary": "SmartSafeHub release note test for $version",
  "sections": [
    { "title": "Test", "items": ["Release metadata is display-only."] }
  ]
}
EOF2
done

cat > "$TMP/bin/uclient-fetch" <<'MOCKFETCH'
#!/bin/sh
set -eu
output=''
url=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		-T) shift 2 ;;
		-O) output="$2"; shift 2 ;;
		*) url="$1"; shift ;;
	esac
done
printf '%s\n' "$url" >> "${MOCK_FETCH_LOG:?}"
name="${url##*/}"
if [ "${MOCK_FETCH_FAIL:-0}" = '1' ] || [ "${MOCK_FETCH_FAIL_NAME:-}" = "$name" ]; then
	exit 1
fi
cp "${MOCK_RELEASE_ROOT:?}/$name" "$output"
MOCKFETCH
chmod +x "$TMP/bin/uclient-fetch"

cat > "$TMP/bin/apk" <<'MOCKAPK'
#!/bin/sh
set -eu
root="${MOCK_APK_ROOT:?}"
command="${1:-}"
shift || true
case "$command" in
	update)
		if [ "${MOCK_APK_UPDATE_FAIL:-0}" = '1' ]; then
			echo 'ERROR: temporary repository index refresh failure' >&2
			exit 1
		fi
		exit 0
		;;
	list)
		if [ "${1:-}" = '-I' ] && [ "${2:-}" = '--manifest' ]; then
			package="${3:-}"
			[ -f "$root/$package.installed" ] || exit 0
			printf '%s %s\n' "$package" "$(cat "$root/$package.installed")"
			exit 0
		fi
		if [ "${1:-}" = '-u' ]; then
			package="${2:-}"
			[ -f "$root/$package.installed" ] || exit 0
			[ -f "$root/$package.available" ] || exit 0
			installed="$(cat "$root/$package.installed")"
			available="$(cat "$root/$package.available")"
			[ "$installed" != "$available" ] || exit 0
			printf '%s-%s all {mock} (GPL) [upgradable from: %s]\n' "$package" "$available" "$installed"
			exit 0
		fi
		exit 2
		;;
	add)
		printf 'add' > "${MOCK_APK_LOG:?}"
		package=''
		for argument in "$@"; do
			printf ' %s' "$argument" >> "$MOCK_APK_LOG"
			case "$argument" in
				--*) ;;
				*) package="$argument" ;;
			esac
		done
		printf '\n' >> "$MOCK_APK_LOG"
		if [ "${MOCK_APK_ADD_FAIL:-0}" = '1' ]; then
			echo 'ERROR: unable to normalize local APK package constraint' >&2
			exit 1
		fi
		if [ -n "$package" ] && [ "${MOCK_APK_ADD_RETAIN_PIN:-0}" != '1' ] && [ -f "${MOCK_APK_WORLD_FILE:?}" ]; then
			awk -v package="$package" '
				index($0, package "><Q") == 1 { print package; next }
				{ print }
			' "$MOCK_APK_WORLD_FILE" > "$MOCK_APK_WORLD_FILE.tmp"
			mv "$MOCK_APK_WORLD_FILE.tmp" "$MOCK_APK_WORLD_FILE"
		fi
		if [ "${MOCK_APK_ADD_NOOP:-0}" != '1' ] && [ -n "$package" ] && [ -f "$root/$package.available" ]; then
			cp "$root/$package.available" "$root/$package.installed"
		fi
		if [ "${MOCK_APK_ADD_NOOP:-0}" != '1' ] && [ "$package" = 'luci-app-smartsafehub' ] && [ -f "$root/safeshield.available" ]; then
			cp "$root/safeshield.available" "$root/safeshield.installed"
		fi
		exit 0
		;;
	upgrade)
		printf 'upgrade' > "${MOCK_APK_LOG:?}"
		for package in "$@"; do
			printf ' %s' "$package" >> "$MOCK_APK_LOG"
			if [ "$package" = 'luci-app-smartsafehub' ] && \
				grep -q '^safeshield><Q' "${MOCK_APK_WORLD_FILE:?}" 2>/dev/null; then
				printf '\n' >> "$MOCK_APK_LOG"
				echo 'ERROR: unable to select packages: safeshield: breaks: world[safeshield><QmockIdentityHash=]' >&2
				exit 1
			fi
			if [ "${MOCK_APK_UPGRADE_NOOP:-0}" != '1' ] && [ -f "$root/$package.available" ]; then
				cp "$root/$package.available" "$root/$package.installed"
			fi
			if [ "${MOCK_APK_UPGRADE_NOOP:-0}" != '1' ] && [ "$package" = 'luci-app-smartsafehub' ] && [ -f "$root/safeshield.available" ]; then
				cp "$root/safeshield.available" "$root/safeshield.installed"
			fi
		done
		printf '\n' >> "$MOCK_APK_LOG"
		exit 0
		;;
	*)
		exit 2
		;;
esac
MOCKAPK
chmod +x "$TMP/bin/apk"

export MOCK_APK_ROOT="$TMP/pkg"
export MOCK_APK_LOG="$TMP/apk.log"
export MOCK_APK_WORLD_FILE="$TMP/world"
export MOCK_FETCH_LOG="$TMP/fetch.log"
export MOCK_RELEASE_ROOT="$TMP/releases"
export SMARTSAFEHUB_UPDATER_STATE_FILE="$TMP/updates.state"
export SMARTSAFEHUB_UPDATER_RELEASE_NOTES_FILE="$TMP/release-notes.json"
export SMARTSAFEHUB_UPDATER_LOCK_DIR="$TMP/updater.lock"
export SMARTSAFEHUB_UPDATER_AUTO_MARKER="$TMP/auto-date"
export SMARTSAFEHUB_UPDATER_AUTO_RETRY_MARKER="$TMP/auto-retry-at"
export SMARTSAFEHUB_UPDATER_AUTO_RETRY_COUNT_MARKER="$TMP/auto-retry-count"
export SMARTSAFEHUB_UPDATER_APK_WORLD_FILE="$TMP/world"
export SMARTSAFEHUB_UPDATER_REPOSITORY_DIR="$TMP/repos"
export SMARTSAFEHUB_UPDATER_APK_BIN="$TMP/bin/apk"
export SMARTSAFEHUB_UPDATER_UCLIENT_FETCH_BIN="$TMP/bin/uclient-fetch"
export SMARTSAFEHUB_UPDATER_UCI_BIN="$TMP/bin/uci"
export SMARTSAFEHUB_UPDATER_RPCD_INIT=''
export SMARTSAFEHUB_UPDATER_LUCI_INDEX_CACHE="$TMP/luci-indexcache"

"$UPDATER" check
TAB="$(printf '\t')"
assert_contains "$TMP/updates.state" "phase${TAB}idle"
assert_not_contains "$TMP/updates.state" "package${TAB}safeshield"
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}0.2.1-r1${TAB}${RELEASE_VERSION}${TAB}1"
assert_contains "$TMP/fetch.log" "https://repo.smartsafehub.com/stable/releases/luci-app-smartsafehub/index.json"
assert_contains "$TMP/fetch.log" "https://repo.smartsafehub.com/stable/releases/luci-app-smartsafehub/${RELEASE_VERSION}.json"
assert_contains "$TMP/fetch.log" "https://repo.smartsafehub.com/stable/releases/luci-app-smartsafehub/0.2.3-r1.json"
assert_contains "$TMP/fetch.log" "https://repo.smartsafehub.com/stable/releases/luci-app-smartsafehub/0.2.2-r1.json"
assert_contains "$TMP/release-notes.json" "\"installed_version\": \"0.2.1-r1\""
assert_contains "$TMP/release-notes.json" "\"available_version\": \"${RELEASE_VERSION}\""
assert_contains "$TMP/release-notes.json" "\"version\": \"${RELEASE_VERSION}\""
assert_contains "$TMP/release-notes.json" "\"version\": \"0.2.3-r1\""
assert_contains "$TMP/release-notes.json" "\"version\": \"0.2.2-r1\""
assert_not_contains "$TMP/release-notes.json" "\"version\": \"0.2.1-r1\""
assert_contains "$TMP/release-notes.json" '"complete": true'

# One missing intermediate note should preserve the other notes and mark the bundle incomplete.
rm -f "$TMP/release-notes.json"
MOCK_FETCH_FAIL_NAME='0.2.3-r1.json' "$UPDATER" check
assert_contains "$TMP/release-notes.json" "\"version\": \"${RELEASE_VERSION}\""
assert_not_contains "$TMP/release-notes.json" "\"version\": \"0.2.3-r1\""
assert_contains "$TMP/release-notes.json" "\"version\": \"0.2.2-r1\""
assert_contains "$TMP/release-notes.json" '"complete": false'

# Release note metadata is display-only: a temporary fetch failure must keep a matching last-known-good cache.
cp "$TMP/release-notes.json" "$TMP/release-notes.before.json"
MOCK_FETCH_FAIL=1 "$UPDATER" check
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}0.2.1-r1${TAB}${RELEASE_VERSION}${TAB}1"
cmp -s "$TMP/release-notes.before.json" "$TMP/release-notes.json" || \
	fail 'matching release note cache must survive a temporary release-note fetch failure'

# A cached bundle from another installed/available range must not be reused.
printf '%s\n' '9.9.9-r1' > "$TMP/pkg/luci-app-smartsafehub.available"
"$UPDATER" check
[ ! -e "$TMP/release-notes.json" ] || fail 'release note cache from a different version range must be removed'
printf '%s\n' "$RELEASE_VERSION" > "$TMP/pkg/luci-app-smartsafehub.available"
"$UPDATER" check

# APK index refresh failures must still refresh release notes from the last known package state.
rm -f "$TMP/release-notes.json"
if MOCK_APK_UPDATE_FAIL=1 "$UPDATER" check; then
	fail 'APK index refresh failure must still report a failed update check'
fi
assert_contains "$TMP/updates.state" "phase${TAB}error"
assert_contains "$TMP/updates.state" "error_code${TAB}UPDATES_INDEX_REFRESH_FAILED"
last_attempt_at="$(awk -F '\t' '$1 == "last_attempt_at" { print $2 }' "$TMP/updates.state")"
[ "${last_attempt_at:-0}" -gt 0 ] || fail 'failed update check must record last_attempt_at for daemon throttling'
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}0.2.1-r1${TAB}${RELEASE_VERSION}${TAB}1"
assert_contains "$TMP/release-notes.json" "\"installed_version\": \"0.2.1-r1\""
assert_contains "$TMP/release-notes.json" "\"available_version\": \"${RELEASE_VERSION}\""
assert_contains "$TMP/release-notes.json" "\"version\": \"${RELEASE_VERSION}\""

# The installed version must be reconciled from the local APK database even when index refresh fails.
printf '%s\n' "$RELEASE_VERSION" > "$TMP/pkg/luci-app-smartsafehub.installed"
if MOCK_APK_UPDATE_FAIL=1 "$UPDATER" check; then
	fail 'APK index refresh failure must still report a failed update check after a local package change'
fi
assert_contains "$TMP/updates.state" "phase${TAB}error"
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}${RELEASE_VERSION}${TAB}${TAB}0"
[ ! -e "$TMP/release-notes.json" ] || fail 'release notes for the previous installed version must be removed after a local package change'

# Restore the original installed version for the remaining channel/install checks.
printf '%s\n' '0.2.1-r1' > "$TMP/pkg/luci-app-smartsafehub.installed"
"$UPDATER" check

# The channel selected in smartsafehub.list is the release-note source of truth.
# A stale/legacy stable repository elsewhere must not override a beta switch.
printf '%s\n' 'https://repo.smartsafehub.com/stable/packages/x86_64/smartsafehub/packages.adb' > "$TMP/repos/00-legacy-stable.list"
printf '%s\n' 'https://repo.smartsafehub.com/beta/packages/x86_64/smartsafehub/packages.adb' > "$TMP/repos/smartsafehub.list"
rm -f "$TMP/fetch.log" "$TMP/release-notes.json"
"$UPDATER" check
assert_contains "$TMP/fetch.log" "https://repo.smartsafehub.com/beta/releases/luci-app-smartsafehub/index.json"
assert_contains "$TMP/fetch.log" "https://repo.smartsafehub.com/beta/releases/luci-app-smartsafehub/${RELEASE_VERSION}.json"
assert_not_contains "$TMP/fetch.log" 'https://repo.smartsafehub.com/stable/releases/'
assert_contains "$TMP/release-notes.json" "\"available_version\": \"${RELEASE_VERSION}\""

"$UPDATER" install
assert_contains "$TMP/apk.log" 'upgrade luci-app-smartsafehub'
assert_not_contains "$TMP/apk.log" ' safeshield'
[ "$(cat "$TMP/pkg/safeshield.installed")" = "$SAFESHIELD_MIN_VERSION" ] || fail 'safeshield dependency did not reach the required minimum version'
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}${RELEASE_VERSION}${TAB}${TAB}0"
[ ! -e "$TMP/release-notes.json" ] || fail 'release note cache must be removed after the update is installed'

last_install_at="$(awk -F '\t' '$1 == "last_install_at" { print $2 }' "$TMP/updates.state")"
[ "${last_install_at:-0}" -gt 0 ] || fail 'last_install_at was not recorded'

# apk can return success without changing the installed package. Treat that as an install failure.
printf '%s\n' '0.2.1-r1' > "$TMP/pkg/luci-app-smartsafehub.installed"
printf '%s\n' '0.0.0' > "$TMP/pkg/safeshield.installed"
"$UPDATER" check
last_install_before_noop="$(awk -F '\t' '$1 == "last_install_at" { print $2 }' "$TMP/updates.state")"
if MOCK_APK_UPGRADE_NOOP=1 "$UPDATER" install; then
	fail 'an apk upgrade no-op must not be reported as a successful install'
fi
assert_contains "$TMP/apk.log" 'upgrade luci-app-smartsafehub'
assert_contains "$TMP/updates.state" "phase${TAB}error"
assert_contains "$TMP/updates.state" "error_code${TAB}UPDATES_INSTALL_VERSION_UNCHANGED"
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}0.2.1-r1${TAB}${RELEASE_VERSION}${TAB}1"
last_install_after_noop="$(awk -F '\t' '$1 == "last_install_at" { print $2 }' "$TMP/updates.state")"
[ "$last_install_after_noop" = "$last_install_before_noop" ] || fail 'last_install_at must not change after an apk no-op'

# A local APK file install pins the exact package identity in /etc/apk/world. The updater must
# rewrite only the managed world entry, then run one targeted SmartSafeHub upgrade. It must not
# invoke apk add --upgrade --latest, because that can broaden dependency resolution into
# unrelated OpenWrt packages and kernel modules.
printf '%s\n' '0.2.1-r1' > "$TMP/pkg/luci-app-smartsafehub.installed"
printf '%s\n' '0.0.0' > "$TMP/pkg/safeshield.installed"
cat > "$TMP/world" <<'EOF2'
busybox=1.37.0-r6
luci-app-smartsafehub><Q1mockLocalIdentityHash=
dropbear><Q1unrelatedLocalIdentityHash=
EOF2
"$UPDATER" check
"$UPDATER" install
assert_contains "$TMP/apk.log" 'upgrade luci-app-smartsafehub'
assert_not_contains "$TMP/apk.log" 'add --upgrade --latest'
assert_not_contains "$TMP/apk.log" '--available'
assert_contains "$TMP/world" 'busybox=1.37.0-r6'
assert_contains "$TMP/world" 'luci-app-smartsafehub'
assert_not_contains "$TMP/world" 'luci-app-smartsafehub><Q'
assert_contains "$TMP/world" 'dropbear><Q1unrelatedLocalIdentityHash='
[ "$(cat "$TMP/pkg/luci-app-smartsafehub.installed")" = "$RELEASE_VERSION" ] || fail 'identity-pinned SmartSafeHub package did not upgrade to the repository version'
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}${RELEASE_VERSION}${TAB}${TAB}0"

# SafeShield is a managed dependency. Normalize its local APK identity pin in world without
# directly upgrading SafeShield; the targeted SmartSafeHub transaction may update SafeShield
# only when its package dependency actually requires a newer version.
printf '%s\n' '0.2.1-r1' > "$TMP/pkg/luci-app-smartsafehub.installed"
printf '%s\n' '0.0.0' > "$TMP/pkg/safeshield.installed"
cat > "$TMP/world" <<'EOF2'
busybox=1.37.0-r6
luci-app-smartsafehub
safeshield><Q1mockSafeShieldIdentityHash=
dropbear><Q1unrelatedLocalIdentityHash=
EOF2
"$UPDATER" check
"$UPDATER" install
assert_contains "$TMP/apk.log" 'upgrade luci-app-smartsafehub'
assert_not_contains "$TMP/apk.log" ' safeshield'
assert_not_contains "$TMP/apk.log" 'add --upgrade --latest'
assert_contains "$TMP/world" 'busybox=1.37.0-r6'
assert_contains "$TMP/world" 'safeshield'
assert_not_contains "$TMP/world" 'safeshield><Q'
assert_contains "$TMP/world" 'dropbear><Q1unrelatedLocalIdentityHash='
[ "$(cat "$TMP/pkg/safeshield.installed")" = "$SAFESHIELD_MIN_VERSION" ] || fail 'targeted SmartSafeHub upgrade did not resolve the required SafeShield dependency'
[ "$(cat "$TMP/pkg/luci-app-smartsafehub.installed")" = "$RELEASE_VERSION" ] || fail 'SmartSafeHub did not upgrade after normalizing the SafeShield identity pin'
assert_contains "$TMP/updates.state" "package${TAB}luci-app-smartsafehub${TAB}${RELEASE_VERSION}${TAB}${TAB}0"

# Both managed packages can be identity-pinned after local APK testing. Normalize both exact
# entries while preserving unrelated version constraints and local identity pins.
printf '%s\n' '0.2.1-r1' > "$TMP/pkg/luci-app-smartsafehub.installed"
printf '%s\n' '0.0.0' > "$TMP/pkg/safeshield.installed"
cat > "$TMP/world" <<'EOF2'
busybox=1.37.0-r6
luci-app-smartsafehub><Q1mockHubIdentityHash=
safeshield><Q1mockSafeShieldIdentityHash=
dropbear><Q1unrelatedLocalIdentityHash=
EOF2
"$UPDATER" check
"$UPDATER" install
assert_contains "$TMP/apk.log" 'upgrade luci-app-smartsafehub'
assert_not_contains "$TMP/apk.log" 'add --upgrade --latest'
assert_contains "$TMP/world" 'busybox=1.37.0-r6'
assert_contains "$TMP/world" 'luci-app-smartsafehub'
assert_contains "$TMP/world" 'safeshield'
assert_not_contains "$TMP/world" 'luci-app-smartsafehub><Q'
assert_not_contains "$TMP/world" 'safeshield><Q'
assert_contains "$TMP/world" 'dropbear><Q1unrelatedLocalIdentityHash='

printf '%s\n' 'luci-app-smartsafehub' > "$TMP/world"
assert_contains "$UPDATER" 'APK_WORLD_FILE="${SMARTSAFEHUB_UPDATER_APK_WORLD_FILE:-/etc/apk/world}"'
assert_contains "$UPDATER" 'SAFESHIELD_PACKAGE="safeshield"'
assert_contains "$UPDATER" 'package_has_identity_pin() {'
assert_contains "$UPDATER" 'normalize_package_identity_pin() {'
assert_contains "$UPDATER" 'index($0, package "><Q") == 1 { print package; next }'
assert_contains "$UPDATER" 'normalize_package_identity_pin "$SAFESHIELD_PACKAGE" '
assert_contains "$UPDATER" 'normalize_package_identity_pin "$UPDATE_PACKAGE" '
assert_contains "$UPDATER" '"$APK_BIN" upgrade "$UPDATE_PACKAGE"'
assert_not_contains "$UPDATER" '"$APK_BIN" add --upgrade --latest'
assert_not_contains "$UPDATER" 'upgrade --available'

assert_contains "$UPDATER" '( sleep 2; "$RPCD_INIT" reload >/dev/null 2>&1 ) &'
assert_not_contains "$UPDATER" '"$RPCD_INIT" restart'

# Automatic installs must mark the date only after perform_install succeeds, throttle retries,
# and stop after three real failed attempts on the same day. Lock contention does not consume an attempt.
assert_contains "$UPDATER" 'AUTO_INSTALL_RETRY_S=900'
assert_contains "$UPDATER" 'AUTO_INSTALL_MAX_ATTEMPTS=3'
assert_contains "$UPDATER" 'AUTO_RETRY_COUNT_MARKER='
assert_contains "$UPDATER" 'retry_count="$(read_auto_retry_count "$today")"'
assert_contains "$UPDATER" '[ "$retry_count" -lt "$AUTO_INSTALL_MAX_ATTEMPTS" ] || return 0'
assert_contains "$UPDATER" 'if [ "$result" -eq 0 ]; then'
assert_contains "$UPDATER" "printf '%s\\n' \"\$today\" > \"\$AUTO_MARKER\""
assert_contains "$UPDATER" 'elif [ "$result" -ne 75 ]; then'
assert_contains "$UPDATER" 'retry_count=$((retry_count + 1))'
assert_contains "$UPDATER" "printf '%s %s\\n' \"\$today\" \"\$retry_count\" > \"\$AUTO_RETRY_COUNT_MARKER\""
assert_contains "$UPDATER" 'if [ "$retry_count" -lt "$AUTO_INSTALL_MAX_ATTEMPTS" ]; then'
assert_contains "$UPDATER" "printf '%s\\n' \"\$current_epoch\" > \"\$AUTO_RETRY_MARKER\""
assert_contains "$UPDATER" 'log_message "automatic update failed after $retry_count attempts; retrying tomorrow"'

# Daemon startup checks are intentionally staggered behind firmware and retry transient failures only
# three times before the normal interval throttles future package-index refreshes.
assert_contains "$UPDATER" 'DAEMON_INITIAL_DELAY_S=20'
assert_contains "$UPDATER" 'BOOT_CHECK_RETRY_S=60'
assert_contains "$UPDATER" 'BOOT_CHECK_MAX_ATTEMPTS=3'
assert_contains "$UPDATER" 'last_attempt="$(state_value last_attempt_at)"'
assert_contains "$UPDATER" 'boot_check_with_retry || true'

# Exercise the daemon boot retry and automatic install state machines directly without entering
# the infinite daemon loop.
sed '/^case "${1:-}" in$/,$d' "$UPDATER" > "$TMP/updater-lib.sh"
# shellcheck disable=SC1090
. "$TMP/updater-lib.sh"

MOCK_BOOT_CHECK_CALLS=0
MOCK_BOOT_CHECK_SUCCESS_AT=2
MOCK_BOOT_SLEEP_LOG="$TMP/updater-boot-sleep.log"
: > "$MOCK_BOOT_SLEEP_LOG"

execute_check() {
	MOCK_BOOT_CHECK_CALLS=$((MOCK_BOOT_CHECK_CALLS + 1))
	[ "$MOCK_BOOT_CHECK_CALLS" -ge "$MOCK_BOOT_CHECK_SUCCESS_AT" ]
}

sleep() {
	printf '%s\n' "$1" >> "$MOCK_BOOT_SLEEP_LOG"
}

log_message() {
	:
}

boot_check_with_retry
[ "$MOCK_BOOT_CHECK_CALLS" -eq 2 ] || fail 'management software boot check did not stop after the first successful retry'
[ "$(wc -l < "$MOCK_BOOT_SLEEP_LOG" | tr -d '[:space:]')" -eq 1 ] || fail 'management software boot check must sleep only between failed attempts'
assert_contains "$MOCK_BOOT_SLEEP_LOG" '60'

MOCK_BOOT_CHECK_CALLS=0
MOCK_BOOT_CHECK_SUCCESS_AT=99
: > "$MOCK_BOOT_SLEEP_LOG"
if boot_check_with_retry; then
	fail 'management software boot check must report failure after exhausting retries'
fi
[ "$MOCK_BOOT_CHECK_CALLS" -eq 3 ] || fail 'management software boot check must stop after three failed attempts'
[ "$(wc -l < "$MOCK_BOOT_SLEEP_LOG" | tr -d '[:space:]')" -eq 2 ] || fail 'management software boot retry must wait only between the three attempts'

# A failed check has no successful last_check_at, but last_attempt_at must still keep the normal
# daemon loop from refreshing APK indexes every minute while the repository/network is unavailable.
STATE_FILE="$TMP/periodic-updates.state"
cat > "$STATE_FILE" <<EOF2
version	1
phase	error
last_check_at	0
last_attempt_at	100000
last_install_at	0
last_error_at	100000
error_code	UPDATES_INDEX_REFRESH_FAILED
error_message	temporary failure
EOF2
CHECK_ENABLED=1
CHECK_INTERVAL_S=21600
MOCK_PERIODIC_EPOCH=100060
MOCK_PERIODIC_CHECK_CALLS=0

date() {
	case "${1:-}" in
		+%s) printf '%s\n' "$MOCK_PERIODIC_EPOCH" ;;
		*) command date "$@" ;;
	esac
}

execute_check() {
	MOCK_PERIODIC_CHECK_CALLS=$((MOCK_PERIODIC_CHECK_CALLS + 1))
	return 0
}

periodic_check_if_due
[ "$MOCK_PERIODIC_CHECK_CALLS" -eq 0 ] || fail 'failed management software check retried before the configured interval elapsed'
MOCK_PERIODIC_EPOCH=$((100000 + CHECK_INTERVAL_S))
periodic_check_if_due
[ "$MOCK_PERIODIC_CHECK_CALLS" -eq 1 ] || fail 'management software check did not resume after the configured interval elapsed'
STATE_FILE="$TMP/updates.state"

# The production updater intentionally does not use set -e; mirror that behavior for failed-install paths.
set +e

AUTO_INSTALL=1
AUTO_INSTALL_TIME='03:00'
AUTO_MARKER="$TMP/auto-date-behavior"
AUTO_RETRY_MARKER="$TMP/auto-retry-at-behavior"
AUTO_RETRY_COUNT_MARKER="$TMP/auto-retry-count-behavior"
MOCK_AUTO_DATE='2026-09-08'
MOCK_AUTO_TIME='03:00'
MOCK_AUTO_EPOCH=100000
MOCK_INSTALL_RESULT=1
MOCK_INSTALL_CALLS=0

date() {
	case "${1:-}" in
		+%Y-%m-%d) printf '%s\n' "$MOCK_AUTO_DATE" ;;
		+%H:%M) printf '%s\n' "$MOCK_AUTO_TIME" ;;
		+%s) printf '%s\n' "$MOCK_AUTO_EPOCH" ;;
		*) command date "$@" ;;
	esac
}

perform_install() {
	MOCK_INSTALL_CALLS=$((MOCK_INSTALL_CALLS + 1))
	return "$MOCK_INSTALL_RESULT"
}

log_message() {
	:
}

rm -f "$AUTO_MARKER" "$AUTO_RETRY_MARKER" "$AUTO_RETRY_COUNT_MARKER"
auto_install_if_due
[ "$MOCK_INSTALL_CALLS" -eq 1 ] || fail 'first failed automatic install was not attempted'
[ "$(cat "$AUTO_RETRY_COUNT_MARKER")" = '2026-09-08 1' ] || fail 'first failed automatic install was not counted'

MOCK_AUTO_EPOCH=$((MOCK_AUTO_EPOCH + AUTO_INSTALL_RETRY_S))
auto_install_if_due
[ "$MOCK_INSTALL_CALLS" -eq 2 ] || fail 'second automatic install was not attempted after the retry cooldown'
[ "$(cat "$AUTO_RETRY_COUNT_MARKER")" = '2026-09-08 2' ] || fail 'second failed automatic install was not counted'

MOCK_AUTO_EPOCH=$((MOCK_AUTO_EPOCH + AUTO_INSTALL_RETRY_S))
auto_install_if_due
[ "$MOCK_INSTALL_CALLS" -eq 3 ] || fail 'third automatic install was not attempted after the retry cooldown'
[ "$(cat "$AUTO_RETRY_COUNT_MARKER")" = '2026-09-08 3' ] || fail 'third failed automatic install was not counted'
[ ! -e "$AUTO_RETRY_MARKER" ] || fail 'retry cooldown marker must be removed after the daily attempt limit is exhausted'

MOCK_AUTO_EPOCH=$((MOCK_AUTO_EPOCH + AUTO_INSTALL_RETRY_S))
auto_install_if_due
[ "$MOCK_INSTALL_CALLS" -eq 3 ] || fail 'automatic install retried more than three times on the same day'

MOCK_AUTO_DATE='2026-09-09'
MOCK_AUTO_EPOCH=$((MOCK_AUTO_EPOCH + 86400))
auto_install_if_due
[ "$MOCK_INSTALL_CALLS" -eq 4 ] || fail 'automatic install attempt count did not reset on the next day'
[ "$(cat "$AUTO_RETRY_COUNT_MARKER")" = '2026-09-09 1' ] || fail 'next-day automatic retry state was not reset to the first attempt'

# Lock contention is not an installation attempt and must not consume the daily limit.
rm -f "$AUTO_MARKER" "$AUTO_RETRY_MARKER" "$AUTO_RETRY_COUNT_MARKER"
MOCK_INSTALL_CALLS=0
MOCK_INSTALL_RESULT=75
auto_install_if_due
[ "$MOCK_INSTALL_CALLS" -eq 1 ] || fail 'lock-contention path did not call perform_install'
[ ! -e "$AUTO_RETRY_COUNT_MARKER" ] || fail 'lock contention consumed an automatic install attempt'

# A successful retry must complete the day and clean all retry state.
MOCK_INSTALL_RESULT=1
auto_install_if_due
[ "$(cat "$AUTO_RETRY_COUNT_MARKER")" = '2026-09-09 1' ] || fail 'failed automatic install before recovery was not counted'
MOCK_AUTO_EPOCH=$((MOCK_AUTO_EPOCH + AUTO_INSTALL_RETRY_S))
MOCK_INSTALL_RESULT=0
auto_install_if_due
[ "$(cat "$AUTO_MARKER")" = '2026-09-09' ] || fail 'successful automatic install did not mark the day complete'
[ ! -e "$AUTO_RETRY_MARKER" ] || fail 'successful automatic install did not clear the retry cooldown marker'
[ ! -e "$AUTO_RETRY_COUNT_MARKER" ] || fail 'successful automatic install did not clear the retry count marker'

set -e

echo "PASS: updater handles repository upgrades and local APK identity pins, verifies installed versions, limits automatic retries, and preserves targeted package scope"
