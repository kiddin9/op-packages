#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/root/usr/sbin/tailscale_openclash_bypass"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-openclash-test.$$"
REAL_CHOWN="$(command -v chown)"
REAL_CHMOD="$(command -v chmod)"
REAL_DD="$(command -v dd)"
REAL_GREP="$(command -v grep)"
SYNC_ENABLE_PID=
SYNC_DISABLE_PID=

cleanup() {
	[ -z "$SYNC_ENABLE_PID" ] || kill "$SYNC_ENABLE_PID" >/dev/null 2>&1 || true
	[ -z "$SYNC_DISABLE_PID" ] || kill "$SYNC_DISABLE_PID" >/dev/null 2>&1 || true
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
file_mode() {
	stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}
file_owner() {
	stat -c '%u:%g' "$1" 2>/dev/null || stat -f '%u:%g' "$1"
}
file_permissions() {
	LC_ALL=C ls -ld "$1" | awk '{ print substr($1, 1, 10) }'
}
assert_count() {
	expected="$1"; needle="$2"; file="$3"
	actual="$(grep -cF -- "$needle" "$file" || true)"
	[ "$actual" = "$expected" ] || fail "$file expected $expected occurrences of $needle, got $actual"
}
assert_line_count() {
	expected="$1"; line="$2"; file="$3"
	actual="$(grep -Fxc -- "$line" "$file" || true)"
	[ "$actual" = "$expected" ] || fail "$file expected $expected exact occurrences of $line, got $actual"
}
assert_chown_owner() {
	owner="$1"
	grep -F -- "$owner " "$CHOWN_LOG" >/dev/null || fail "chown did not receive numeric owner/group $owner"
}
managed_hook_present() {
	grep -Fx '# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash' "$1" >/dev/null 2>&1
}
assert_owner_before_mode() {
	owner_line="$(grep -n '^chown ' "$REPLACEMENT_LOG" | tail -n 1 | cut -d: -f1)"
	mode_line="$(grep -n '^chmod ' "$REPLACEMENT_LOG" | tail -n 1 | cut -d: -f1)"
	[ -n "$owner_line" ] || fail 'replacement did not restore hook ownership'
	[ -n "$mode_line" ] || fail 'replacement did not restore hook mode'
	[ "$owner_line" -lt "$mode_line" ] || fail 'replacement must restore owner before mode'
}

if grep -E 'grep[[:space:]]+-[^[:space:]]*b' "$SCRIPT" >/dev/null; then
	fail 'OpenClash helper must not use grep -b on BusyBox 1.36'
fi

mkdir -p "$TMP_DIR/openclash/custom" "$TMP_DIR/bin" "$TMP_DIR/tmp"
cat >"$TMP_DIR/bin/flock" <<'PL'
#!/usr/bin/perl
use strict;
use warnings;
use Fcntl qw(LOCK_EX);

@ARGV == 2 && $ARGV[0] eq '-x' && $ARGV[1] =~ /^\d+$/ or die "unsupported flock arguments\n";
open my $lock_fh, "<&=$ARGV[1]" or die "cannot inherit lock fd: $!\n";
flock($lock_fh, LOCK_EX) or die "cannot acquire lock: $!\n";
PL
chmod +x "$TMP_DIR/bin/flock"
cat >"$TMP_DIR/bin/grep" <<'SH'
#!/bin/sh
for arg in "$@"; do
	case "$arg" in
		--byte-offset|-*b*)
			printf 'fake grep rejects byte offsets: %s\n' "$arg" >&2
			exit 64
			;;
	esac
done
exec "${REAL_GREP:?}" "$@"
SH
chmod +x "$TMP_DIR/bin/grep"
cat >"$TMP_DIR/bin/stat" <<'SH'
#!/bin/sh
printf 'stat is unavailable on the target OpenWrt image\n' >&2
exit 127
SH
chmod +x "$TMP_DIR/bin/stat"
cat >"$TMP_DIR/bin/od" <<'SH'
#!/bin/sh
printf 'od is unavailable on the target OpenWrt image\n' >&2
exit 127
SH
chmod +x "$TMP_DIR/bin/od"
cat >"$TMP_DIR/bin/chown" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${CHOWN_LOG:?}"
printf 'chown %s\n' "$*" >>"${REPLACEMENT_LOG:?}"
exec "${REAL_CHOWN:?}" "$@"
SH
chmod +x "$TMP_DIR/bin/chown"
cat >"$TMP_DIR/bin/chmod" <<'SH'
#!/bin/sh
printf 'chmod %s\n' "$*" >>"${REPLACEMENT_LOG:?}"
exec "${REAL_CHMOD:?}" "$@"
SH
chmod +x "$TMP_DIR/bin/chmod"
cat >"$TMP_DIR/bin/dd" <<'SH'
#!/bin/sh
has_count=0
has_skip=0
for arg in "$@"; do
	case "$arg" in
		count=*) has_count=1 ;;
		skip=*) has_skip=1 ;;
	esac
done
if [ "${DD_FAIL_PREFIX:-0}" = 1 ] && [ "$has_count" = 1 ] && [ "$has_skip" = 0 ]; then
	printf 'failed: %s\n' "$*" >>"${DD_LOG:?}"
	exit 1
fi
if [ "${DD_FAIL_PROBE:-0}" = 1 ] && [ "$has_count" = 1 ] && [ "$has_skip" = 1 ]; then
	printf 'probe-failed: %s\n' "$*" >>"${DD_LOG:?}"
	exit 1
fi
if [ "${DD_SIGNAL_PARENT:-0}" = 1 ] && [ "$has_count" = 1 ] && [ "$has_skip" = 0 ]; then
	printf 'signalled: %s\n' "$*" >>"${DD_LOG:?}"
	kill -TERM "$PPID"
	exit 1
fi
printf 'passed: %s\n' "$*" >>"${DD_LOG:?}"
exec "${REAL_DD:?}" "$@"
SH
chmod +x "$TMP_DIR/bin/dd"
cat >"$TMP_DIR/bin/uci" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${UCI_LOG:?}"
case "$*" in
	'-q show tailscale_openclash.settings')
		case "${UCI_SECTION_MODE:-present}" in
			present)
				printf '%s\n' 'tailscale_openclash.settings=openclash'
				[ -z "${FEATURE_ENABLED:-}" ] || \
					printf "tailscale_openclash.settings.enabled='%s'\n" "$FEATURE_ENABLED"
				;;
			missing) exit 1 ;;
			error) exit 74 ;;
			malformed) printf '%s\n' 'malformed uci section output' ;;
			*) exit 99 ;;
		esac
		;;
	'-q get tailscale_openclash.settings.enabled')
		printf 'value:%s\n' "${FEATURE_ENABLED:-default}" >>"${UCI_LOG:?}"
		[ "${UCI_SECTION_MODE:-present}" = present ] || exit 1
		[ "${UCI_OPTION_GET_FAIL:-0}" = 0 ] || exit 75
		if [ -n "${UCI_READY_FILE:-}" ]; then
			: >"$UCI_READY_FILE"
			while [ ! -e "${UCI_RELEASE_FILE:?}" ]; do sleep 0.05; done
		fi
		[ -n "${FEATURE_ENABLED:-}" ] || exit 1
		printf '%s\n' "$FEATURE_ENABLED"
		;;
	*)
		printf 'unsupported fake uci command: %s\n' "$*" >&2
		exit 99
		;;
esac
SH
chmod +x "$TMP_DIR/bin/uci"
cat >"$TMP_DIR/bin/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${LOGGER_LOG:?}"
SH
chmod +x "$TMP_DIR/bin/logger"
cat >"$TMP_DIR/bin/nft" <<'SH'
#!/bin/sh
set -eu

state="${NFT_STATE:?}"
guard_state="${NFT_GUARD_STATE:?}"
batch_log="${NFT_BATCH_LOG:?}"
call_log="${NFT_CALL_LOG:?}"
table_state="${NFT_TABLE_STATE:-PRESENT}"

printf '%s\n' "$*" >>"$call_log"

print_rule_json() {
	handle="$1"
	rule="$2"
	rest="${rule#insert rule inet fw4 }"
	rule_chain="${rest%% *}"
	comment="$(printf '%s\n' "$rule" | sed -n 's/.* return comment "\(.*\)"$/\1/p')"
	[ -n "$comment" ] || return 0
	json_chain="$rule_chain"
	case "$rule" in
		*' meta mark & 0x00ff0000 == 0x00080000 counter return comment '*)
			match_json='{"match":{"op":"==","left":{"&":[{"meta":{"key":"mark"}},16711680]},"right":524288}}'
			;;
		*' iifname "tailscale0" counter return comment '*)
			match_json='{"match":{"op":"==","left":{"meta":{"key":"iifname"}},"right":"tailscale0"}}'
			;;
		*)
			match_json='{"match":{"op":"==","left":{"meta":{"key":"iifname"}},"right":"unrelated0"}}'
			;;
	esac
	counter_json="{\"counter\":{\"packets\":${NFT_COUNTER_PACKETS:-0},\"bytes\":${NFT_COUNTER_BYTES:-0}}}"
	verdict_json='{"return":null}'
	handle_json=",\"handle\":$handle"
	case "$comment" in
		luci-app-tailscale:*)
			case "${NFT_RULE_JSON_MODE:-canonical}" in
				altered-match)
					match_json='{"match":{"op":"==","left":{"meta":{"key":"mark"}},"right":0}}'
					;;
				overbroad) match_json= ;;
				incomplete) verdict_json= ;;
				altered-verdict) verdict_json='{"accept":null}' ;;
				wrong-chain) json_chain='wrong_chain' ;;
			esac
			if [ "${NFT_CHAIN_JSON_TARGET:-}" = "$rule_chain" ]; then
				case "${NFT_CHAIN_JSON_MODE:-canonical}" in
					wrong-rule-chain) json_chain='wrong_chain' ;;
					missing-owned-handle) handle_json= ;;
				esac
			fi
			;;
	esac
	if [ -n "$match_json" ] && [ -n "$verdict_json" ]; then
		expr_json="[$match_json,$counter_json,$verdict_json]"
	elif [ -n "$match_json" ]; then
		expr_json="[$match_json,$counter_json]"
	else
		expr_json="[$counter_json,$verdict_json]"
	fi
	printf ',{"rule":{"family":"inet","table":"fw4","chain":"%s"%s,"expr":%s,"comment":"%s"}}' \
		"$json_chain" "$handle_json" "$expr_json" "$comment"
}

print_chain_json() {
	chain="$1"
	chain_json_mode=canonical
	[ "${NFT_CHAIN_JSON_TARGET:-}" != "$chain" ] || chain_json_mode="${NFT_CHAIN_JSON_MODE:-canonical}"
	[ "$chain_json_mode" != empty ] || {
		printf '%s\n' '{"nftables":[]}'
		return
	}
	json_chain_name="$chain"
	[ "$chain_json_mode" != wrong-chain-object ] || json_chain_name=wrong_chain
	printf '{"nftables":[{"metainfo":{"version":"1.1.1","release_name":"Commodore Bullmoose #2","json_schema_version":1}},{"chain":{"family":"inet","table":"fw4","name":"%s","handle":1075}}' "$json_chain_name"
	while IFS='|' read -r handle rule || [ -n "${handle:-}" ]; do
		case "$rule" in
			"insert rule inet fw4 $chain "*) ;;
			*) continue ;;
		esac
		print_rule_json "$handle" "$rule"
	done <"$state"
	printf ']}\n'
}

target_chain() {
	case "$1" in
		openclash_mangle_output|openclash_output|openclash_mangle|openclash) return 0 ;;
		*) return 1 ;;
	esac
}

delete_rule_from_state() {
	state_file="$1"
	chain="$2"
	handle="$3"
	temp_file="$(mktemp "${state_file}.XXXXXX")"
	found=0
	while IFS='|' read -r stored_handle stored_rule || [ -n "${stored_handle:-}" ]; do
		if [ "$stored_handle" = "$handle" ]; then
			case "$stored_rule" in
				"insert rule inet fw4 $chain "*) found=1; continue ;;
			esac
		fi
		printf '%s|%s\n' "$stored_handle" "$stored_rule" >>"$temp_file"
	done <"$state_file"
	if [ "$found" -ne 1 ]; then
		printf 'nonexistent nft handle: %s/%s\n' "$chain" "$handle" >&2
		rm -f "$temp_file"
		return 1
	fi
	mv "$temp_file" "$state_file"
}

delete_counter_from_state() {
	state_file="$1"
	counter="$2"
	temp_file="$(mktemp "${state_file}.XXXXXX")"
	found=0
	while IFS= read -r stored_counter || [ -n "$stored_counter" ]; do
		if [ "$stored_counter" = "$counter" ]; then
			found=$((found + 1))
			continue
		fi
		printf '%s\n' "$stored_counter" >>"$temp_file"
	done <"$state_file"
	if [ "$found" -ne 1 ]; then
		printf 'nonexistent nft counter: %s\n' "$counter" >&2
		rm -f "$temp_file"
		return 1
	fi
	mv "$temp_file" "$state_file"
}

replace_table_generation() {
	batch="$1"
	replacement="$(mktemp "${state}.replacement.XXXXXX")"
	while IFS= read -r statement || [ -n "$statement" ]; do
		case "$statement" in
			'delete rule inet fw4 '*)
				rest="${statement#delete rule inet fw4 }"
				chain="${rest%% handle *}"
				handle="${rest##* handle }"
				printf '%s|insert rule inet fw4 %s counter return comment "unrelated-generation-rule-%s"\n' \
					"$handle" "$chain" "$handle" >>"$replacement"
				;;
		esac
	done <"$batch"
	mv "$replacement" "$state"
	: >"$guard_state"
}

apply_batch() {
	batch="$1"
	next_state="$(mktemp "${state}.next.XXXXXX")"
	next_guard_state="$(mktemp "${guard_state}.next.XXXXXX")"
	cp "$state" "$next_state"
	cp "$guard_state" "$next_guard_state"
	operation=0
	while IFS= read -r statement || [ -n "$statement" ]; do
		operation=$((operation + 1))
		case "$statement" in
			'delete counter inet fw4 '*)
				counter="${statement#delete counter inet fw4 }"
				if ! delete_counter_from_state "$next_guard_state" "$counter"; then
					rm -f "$next_state" "$next_guard_state"
					return 1
				fi
				;;
			'delete rule inet fw4 '*)
				rest="${statement#delete rule inet fw4 }"
				chain="${rest%% handle *}"
				handle="${rest##* handle }"
				if ! delete_rule_from_state "$next_state" "$chain" "$handle"; then
					rm -f "$next_state" "$next_guard_state"
					return 1
				fi
				;;
			'insert rule inet fw4 '*)
				next_handle="$(awk -F '|' 'BEGIN { max = 0 } $1 + 0 > max { max = $1 + 0 } END { print max + 1 }' "$next_state")"
				printf '%s|%s\n' "$next_handle" "$statement" >>"$next_state"
				;;
			*)
				printf 'unsupported fake nft statement: %s\n' "$statement" >&2
				rm -f "$next_state" "$next_guard_state"
				exit 99
				;;
		esac
		if [ "${NFT_BATCH_FAIL_AFTER:-0}" = "$operation" ]; then
			rm -f "$next_state" "$next_guard_state"
			exit 1
		fi
	done <"$batch"
	mv "$next_state" "$state"
	mv "$next_guard_state" "$guard_state"
}

print_table_json() {
	printf '{"nftables":[{"table":{"family":"inet","name":"fw4"}}'
	for chain in openclash_mangle_output openclash_output openclash_mangle openclash; do
		[ "${MISSING_CHAIN:-}" = "$chain" ] && continue
		if [ -s "${NFT_DISAPPEARED_FILE:?}" ] && grep -Fx "$chain" "$NFT_DISAPPEARED_FILE" >/dev/null; then
			continue
		fi
		printf ',{"chain":{"family":"inet","table":"fw4","name":"%s"}}' "$chain"
	done
	while IFS='|' read -r handle rule || [ -n "${handle:-}" ]; do
		rest="${rule#insert rule inet fw4 }"
		chain="${rest%% *}"
		[ "${MISSING_CHAIN:-}" = "$chain" ] && continue
		if [ -s "${NFT_DISAPPEARED_FILE:?}" ] && grep -Fx "$chain" "$NFT_DISAPPEARED_FILE" >/dev/null; then
			continue
		fi
		print_rule_json "$handle" "$rule"
	done <"$state"
	printf ']}\n'
}

print_table_inventory_json() {
	case "$table_state" in
		TABLE_ABSENT)
			printf '%s\n' '{"nftables":[{"table":{"family":"inet","name":"other"}}]}'
			;;
		*)
			printf '%s\n' '{"nftables":[{"table":{"family":"inet","name":"fw4"}}]}'
			;;
	esac
}

if [ "$#" = 3 ] && [ "$1" = '-j' ] && [ "$2" = 'list' ] && [ "$3" = 'tables' ]; then
	case "$table_state" in
		INVENTORY_READ_ERROR) exit 73 ;;
		INVENTORY_MALFORMED) printf '%s\n' 'not-json'; exit 0 ;;
	esac
	if [ "${REFRESH_INVENTORY_ERROR:-0}" = 1 ] && \
		[ "$(grep -Fxc -- '-j list tables' "$call_log")" -gt 1 ]; then
		exit 73
	fi
	print_table_inventory_json
	exit 0
fi

if [ "$#" = 5 ] && [ "$1" = '-j' ] && [ "$2" = 'list' ] && [ "$3" = 'table' ] && \
	[ "$4" = 'inet' ] && [ "$5" = 'fw4' ]; then
	case "$table_state" in
		TABLE_ABSENT|TABLE_READ_ERROR|INVENTORY_READ_ERROR|INVENTORY_MALFORMED) exit 72 ;;
		TABLE_MALFORMED) printf '%s\n' 'not-json'; exit 0 ;;
	esac
	if [ "${NFT_JSON_UNSUPPORTED:-0}" = 1 ]; then
		printf 'not-json\n'
	else
		print_table_json
	fi
	exit 0
fi

if [ "$#" = 7 ] && [ "$1" = '-j' ] && [ "$2" = '-a' ] && [ "$3" = 'list' ] && \
	[ "$4" = 'chain' ] && [ "$5" = 'inet' ] && [ "$6" = 'fw4' ]; then
	chain="$7"
	[ "$table_state" = PRESENT ] || exit 72
	target_chain "$chain" || {
		printf 'unsupported fake nft chain: %s\n' "$chain" >&2
		exit 99
	}
	[ "${MISSING_CHAIN:-}" = "$chain" ] && exit 1
	if [ "${DISAPPEAR_CHAIN:-}" = "$chain" ] && ! grep -Fx "$chain" "${NFT_DISAPPEARED_FILE:?}" >/dev/null 2>&1; then
		printf '%s\n' "$chain" >"$NFT_DISAPPEARED_FILE"
		exit 1
	fi
	grep -Fx "$chain" "${NFT_DISAPPEARED_FILE:?}" >/dev/null 2>&1 && exit 1
	[ "${LIST_CHAIN_FAIL:-}" = "$chain" ] && exit 1
	if [ "${NFT_JSON_UNSUPPORTED:-0}" = 1 ]; then
		printf 'not-json\n'
	else
		print_chain_json "$chain"
	fi
	exit 0
fi

if [ "$#" = 5 ] && [ "$1" = 'add' ] && [ "$2" = 'counter' ] && \
	[ "$3" = 'inet' ] && [ "$4" = 'fw4' ]; then
	[ "$table_state" = PRESENT ] || exit 72
	grep -Fx "$5" "$guard_state" >/dev/null 2>&1 && exit 1
	printf '%s\n' "$5" >>"$guard_state"
	exit 0
fi

if [ "$#" = 5 ] && [ "$1" = 'delete' ] && [ "$2" = 'counter' ] && \
	[ "$3" = 'inet' ] && [ "$4" = 'fw4' ]; then
	[ "$table_state" = PRESENT ] || exit 72
	if [ "${NFT_GUARD_DELETE_FAIL_ONCE:-0}" = 1 ] && \
		[ ! -e "${NFT_GUARD_DELETE_FAIL_ONCE_FILE:?}" ]; then
		: >"$NFT_GUARD_DELETE_FAIL_ONCE_FILE"
		exit 71
	fi
	if [ "${NFT_GUARD_DELETE_SIGNAL_ONCE:-0}" = 1 ] && \
		[ ! -e "${NFT_GUARD_DELETE_SIGNAL_ONCE_FILE:?}" ]; then
		: >"$NFT_GUARD_DELETE_SIGNAL_ONCE_FILE"
		kill -TERM "$PPID"
		exit 1
	fi
	delete_counter_from_state "$guard_state" "$5"
	exit $?
fi

if [ "$#" = 2 ] && [ "$1" = '-f' ]; then
	cat "$2" >"$batch_log"
	[ "${NFT_BATCH_FAIL:-0}" = 1 ] && exit 1
	if [ "${NFT_SIGNAL_PARENT:-0}" = 1 ]; then
		kill -TERM "$PPID"
		exit 1
	fi
	if [ "${NFT_GENERATION_REPLACE:-0}" = 1 ]; then
		replace_table_generation "$2"
	fi
	apply_batch "$2"
	exit 0
fi

printf 'unsupported fake nft command: %s\n' "$*" >&2
exit 99
SH
chmod +x "$TMP_DIR/bin/nft"
touch "$TMP_DIR/openclash-init"
chmod +x "$TMP_DIR/openclash-init"
HOOK="$TMP_DIR/openclash/custom/openclash_custom_firewall_rules.sh"
cat >"$HOOK" <<'EOF'
#!/bin/sh
printf user-before
printf '%s\n' 'user text mentions # BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash without owning it'
printf user-after
EOF
chmod 6750 "$HOOK"
original_owner="$(file_owner "$HOOK")"
original_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
CHOWN_LOG="$TMP_DIR/chown.log"
REPLACEMENT_LOG="$TMP_DIR/replacement.log"
DD_LOG="$TMP_DIR/dd.log"
NFT_STATE="$TMP_DIR/nft.state"
NFT_GUARD_STATE="$TMP_DIR/nft.guards"
NFT_BATCH_LOG="$TMP_DIR/nft.batch"
NFT_CALL_LOG="$TMP_DIR/nft.calls"
NFT_DISAPPEARED_FILE="$TMP_DIR/nft.disappeared"
NFT_GUARD_DELETE_FAIL_ONCE_FILE="$TMP_DIR/nft.guard-delete-fail-once"
NFT_GUARD_DELETE_SIGNAL_ONCE_FILE="$TMP_DIR/nft.guard-delete-signal-once"
UCI_LOG="$TMP_DIR/uci.log"
LOGGER_LOG="$TMP_DIR/logger.log"
: >"$NFT_STATE"
: >"$NFT_GUARD_STATE"
: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
: >"$NFT_DISAPPEARED_FILE"
: >"$UCI_LOG"
: >"$LOGGER_LOG"
export CHOWN_LOG REPLACEMENT_LOG DD_LOG REAL_CHOWN REAL_CHMOD REAL_DD REAL_GREP
export NFT_STATE NFT_GUARD_STATE NFT_BATCH_LOG NFT_CALL_LOG NFT_DISAPPEARED_FILE UCI_LOG LOGGER_LOG
export NFT_GUARD_DELETE_FAIL_ONCE_FILE NFT_GUARD_DELETE_SIGNAL_ONCE_FILE

run_helper() {
	OPENCLASH_INIT="$TMP_DIR/openclash-init" \
	OPENCLASH_HOOK_FILE="$HOOK" \
	LOCK_FILE="$TMP_DIR/lock" \
	UCI_BIN="$TMP_DIR/bin/uci" \
	NFT_BIN="$TMP_DIR/bin/nft" \
	JQ_BIN=jq \
	LOGGER_CMD="$TMP_DIR/bin/logger" \
	TMPDIR="$TMP_DIR/tmp" \
	DD_FAIL_PREFIX="${DD_FAIL_PREFIX:-0}" \
	DD_FAIL_PROBE="${DD_FAIL_PROBE:-0}" \
	DD_SIGNAL_PARENT="${DD_SIGNAL_PARENT:-0}" \
	FEATURE_ENABLED="${FEATURE_ENABLED:-}" \
	UCI_SECTION_MODE="${UCI_SECTION_MODE:-present}" \
	UCI_OPTION_GET_FAIL="${UCI_OPTION_GET_FAIL:-0}" \
	NFT_TABLE_STATE="${NFT_TABLE_STATE:-PRESENT}" \
	REFRESH_INVENTORY_ERROR="${REFRESH_INVENTORY_ERROR:-0}" \
	NFT_RULE_JSON_MODE="${NFT_RULE_JSON_MODE:-canonical}" \
	NFT_CHAIN_JSON_MODE="${NFT_CHAIN_JSON_MODE:-canonical}" \
	NFT_CHAIN_JSON_TARGET="${NFT_CHAIN_JSON_TARGET:-}" \
	NFT_GUARD_DELETE_FAIL_ONCE="${NFT_GUARD_DELETE_FAIL_ONCE:-0}" \
	NFT_GUARD_DELETE_SIGNAL_ONCE="${NFT_GUARD_DELETE_SIGNAL_ONCE:-0}" \
	NFT_COUNTER_PACKETS="${NFT_COUNTER_PACKETS:-0}" \
	NFT_COUNTER_BYTES="${NFT_COUNTER_BYTES:-0}" \
	PATH="$TMP_DIR/bin:$PATH" \
	"$SCRIPT" "$@"
}

failed_reconcile_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
failed_reconcile_mode="$(file_mode "$HOOK")"
failed_reconcile_owner="$(file_owner "$HOOK")"
failed_reconcile_permissions="$(file_permissions "$HOOK")"
: >"$DD_LOG"
if DD_FAIL_PREFIX=1 run_helper reconcile-hook; then
	fail 'reconcile-hook must fail when prefix copy fails'
fi
DD_FAIL_PREFIX=0
grep -F 'failed:' "$DD_LOG" >/dev/null || fail 'reconcile-hook did not execute the failing prefix copy'
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$failed_reconcile_hash" ] || \
	fail 'reconcile-hook changed hook after prefix copy failure'
[ "$(file_mode "$HOOK")" = "$failed_reconcile_mode" ] || \
	fail 'reconcile-hook changed hook mode after prefix copy failure'
[ "$(file_owner "$HOOK")" = "$failed_reconcile_owner" ] || \
	fail 'reconcile-hook changed hook ownership after prefix copy failure'
[ "$(file_permissions "$HOOK")" = "$failed_reconcile_permissions" ] || \
	fail 'reconcile-hook changed special permission bits after prefix copy failure'

run_helper reconcile-hook
assert_line_count 1 '# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash' "$HOOK"
assert_line_count 1 '# END luci-app-tailscale 托管：Tailscale 绕过 OpenClash' "$HOOK"
grep -F 'printf user-before' "$HOOK" >/dev/null || fail 'hook insertion removed user content before the block'
grep -F 'printf user-after' "$HOOK" >/dev/null || fail 'hook insertion removed user content after the block'
[ "$(file_permissions "$HOOK")" = '-rwsr-s---' ] || \
	fail 'hook mode changed, including special permission bits'
grep -F 'chmod 6750 ' "$REPLACEMENT_LOG" >/dev/null || \
	fail 'replacement did not restore special permission bits numerically'
[ "$(file_owner "$HOOK")" = "$original_owner" ] || fail 'hook ownership changed'

first_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
run_helper reconcile-hook
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$first_hash" ] || fail 'reconcile-hook is not idempotent'

probe_reconcile_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
probe_reconcile_permissions="$(file_permissions "$HOOK")"
: >"$DD_LOG"
if DD_FAIL_PROBE=1 run_helper reconcile-hook; then
	fail 'reconcile-hook must fail when the optional-newline probe cannot be read'
fi
DD_FAIL_PROBE=0
grep -F 'probe-failed:' "$DD_LOG" >/dev/null || fail 'reconcile-hook did not execute the failing newline probe'
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$probe_reconcile_hash" ] || \
	fail 'reconcile-hook changed hook after newline probe failure'
[ "$(file_permissions "$HOOK")" = "$probe_reconcile_permissions" ] || \
	fail 'reconcile-hook changed hook mode after newline probe failure'

sed 's#^[[:space:]]*/usr/sbin/tailscale_openclash_bypass apply$#\tprintf stale-managed-body#' "$HOOK" >"$TMP_DIR/stale-hook"
chmod 750 "$TMP_DIR/stale-hook"
mv "$TMP_DIR/stale-hook" "$HOOK"
run_helper reconcile-hook
grep -Fx '	/usr/sbin/tailscale_openclash_bypass apply' "$HOOK" >/dev/null || \
	fail 'reconcile-hook did not restore the canonical managed command'
grep -F 'stale-managed-body' "$HOOK" >/dev/null && \
	fail 'reconcile-hook retained a stale managed body'
grep -F 'user text mentions # BEGIN luci-app-tailscale' "$HOOK" >/dev/null || \
	fail 'reconcile-hook removed marker-like user text'

cp "$HOOK" "$TMP_DIR/hook-before-malformed"
printf '%s\n' '# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash' >>"$HOOK"
malformed_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
if run_helper reconcile-hook >/dev/null 2>&1; then
	fail 'duplicate managed markers must fail'
fi
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$malformed_hash" ] || fail 'malformed hook changed after rejection'

cp "$TMP_DIR/hook-before-malformed" "$HOOK"
probe_cleanup_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
probe_cleanup_permissions="$(file_permissions "$HOOK")"
: >"$DD_LOG"
if DD_FAIL_PROBE=1 run_helper cleanup; then
	fail 'cleanup must fail when the optional-newline probe cannot be read'
fi
DD_FAIL_PROBE=0
grep -F 'probe-failed:' "$DD_LOG" >/dev/null || fail 'cleanup did not execute the failing newline probe'
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$probe_cleanup_hash" ] || \
	fail 'cleanup changed hook after newline probe failure'
[ "$(file_permissions "$HOOK")" = "$probe_cleanup_permissions" ] || \
	fail 'cleanup changed hook mode after newline probe failure'

failed_cleanup_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
failed_cleanup_mode="$(file_mode "$HOOK")"
failed_cleanup_owner="$(file_owner "$HOOK")"
: >"$DD_LOG"
if DD_FAIL_PREFIX=1 run_helper cleanup; then
	fail 'cleanup must fail when prefix copy fails'
fi
DD_FAIL_PREFIX=0
grep -F 'failed:' "$DD_LOG" >/dev/null || fail 'cleanup did not execute the failing prefix copy'
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$failed_cleanup_hash" ] || \
	fail 'cleanup changed hook after prefix copy failure'
[ "$(file_mode "$HOOK")" = "$failed_cleanup_mode" ] || \
	fail 'cleanup changed hook mode after prefix copy failure'
[ "$(file_owner "$HOOK")" = "$failed_cleanup_owner" ] || \
	fail 'cleanup changed hook ownership after prefix copy failure'

: >"$CHOWN_LOG"
: >"$REPLACEMENT_LOG"
run_helper cleanup
assert_chown_owner "$original_owner"
assert_owner_before_mode
managed_hook_present "$HOOK" && fail 'cleanup left the managed hook block'
grep -F 'printf user-before' "$HOOK" >/dev/null || fail 'cleanup removed user content'
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$original_hash" ] || \
	fail 'hook cleanup did not restore every original byte'
[ "$(file_mode "$HOOK")" = 750 ] || fail 'cleanup changed hook mode'
[ "$(file_owner "$HOOK")" = "$original_owner" ] || fail 'cleanup changed hook ownership'

: >"$DD_LOG"
if DD_SIGNAL_PARENT=1 run_helper reconcile-hook >/dev/null 2>&1; then
	fail 'reconcile-hook must fail when terminated during replacement'
fi
DD_SIGNAL_PARENT=0
find "$TMP_DIR/openclash/custom" -name '.tailscale-openclash-hook.*' -print | grep . >/dev/null && \
	fail 'terminated hook replacement left a tracked temporary file'
grep -F 'signalled:' "$DD_LOG" >/dev/null || fail 'termination test did not reach hook replacement'

printf '#!/bin/sh\nprintf user-without-trailing-newline' >"$HOOK"
chmod 740 "$HOOK"
no_newline_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
run_helper reconcile-hook
run_helper cleanup
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$no_newline_hash" ] || \
	fail 'cleanup did not restore a hook without a trailing newline'

for special_mode in 4640 1750 1751 7777; do
	printf '#!/bin/sh\nprintf user-special-mode-%s\n' "$special_mode" >"$HOOK"
	chmod "$special_mode" "$HOOK"
	special_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
	special_permissions="$(file_permissions "$HOOK")"
	run_helper reconcile-hook
	[ "$(file_permissions "$HOOK")" = "$special_permissions" ] || \
		fail "reconcile-hook changed special permission mode $special_mode"
	run_helper cleanup
	[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$special_hash" ] || \
		fail "cleanup did not restore bytes for special permission mode $special_mode"
	[ "$(file_permissions "$HOOK")" = "$special_permissions" ] || \
		fail "cleanup changed special permission mode $special_mode"
done

rm -f "$TMP_DIR/openclash-init" "$HOOK"
run_helper reconcile-hook
[ ! -e "$HOOK" ] || fail 'OpenClash-absent reconciliation created a custom script'

touch "$TMP_DIR/openclash-init"
chmod +x "$TMP_DIR/openclash-init"
run_helper reconcile-hook
[ -x "$HOOK" ] || fail 'missing OpenClash custom script was not created executable'
sh -n "$HOOK" || fail 'created hook is not valid shell'

absent_cleanup_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
absent_cleanup_mode="$(file_mode "$HOOK")"
absent_cleanup_owner="$(file_owner "$HOOK")"
rm -f "$TMP_DIR/openclash-init"
: >"$CHOWN_LOG"
run_helper cleanup
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$absent_cleanup_hash" ] || \
	fail 'cleanup when OpenClash is absent rewrote the managed hook'
[ "$(file_mode "$HOOK")" = "$absent_cleanup_mode" ] || \
	fail 'cleanup when OpenClash is absent changed hook mode'
[ "$(file_owner "$HOOK")" = "$absent_cleanup_owner" ] || \
	fail 'cleanup when OpenClash is absent changed hook ownership'
[ ! -s "$CHOWN_LOG" ] || fail 'cleanup when OpenClash is absent invoked chown'

touch "$TMP_DIR/openclash-init"
chmod +x "$TMP_DIR/openclash-init"
: >"$NFT_STATE"
: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
: >"$UCI_LOG"

run_helper apply
assert_count 1 'insert rule inet fw4 openclash_mangle_output ' "$NFT_BATCH_LOG"
assert_count 1 'insert rule inet fw4 openclash_output ' "$NFT_BATCH_LOG"
assert_count 1 'insert rule inet fw4 openclash_mangle iifname "tailscale0"' "$NFT_BATCH_LOG"
assert_count 1 'insert rule inet fw4 openclash iifname "tailscale0"' "$NFT_BATCH_LOG"
assert_count 1 '-j list tables' "$NFT_CALL_LOG"
assert_count 1 '-j list table inet fw4' "$NFT_CALL_LOG"
assert_line_count 1 '-j -a list chain inet fw4 openclash_mangle_output' "$NFT_CALL_LOG"
assert_line_count 1 '-j -a list chain inet fw4 openclash_output' "$NFT_CALL_LOG"
assert_line_count 1 '-j -a list chain inet fw4 openclash_mangle' "$NFT_CALL_LOG"
assert_line_count 1 '-j -a list chain inet fw4 openclash' "$NFT_CALL_LOG"
assert_count 1 '-f ' "$NFT_CALL_LOG"
guard_name="$(sed -n 's/^add counter inet fw4 //p' "$NFT_CALL_LOG")"
[ -n "$guard_name" ] || fail 'apply must create a named counter before caching owned handles'
[ "$(sed -n '1p' "$NFT_BATCH_LOG")" = "delete counter inet fw4 $guard_name" ] || \
	fail 'the guard deletion must be the first statement in the reconciliation batch'
[ ! -s "$NFT_GUARD_STATE" ] || fail 'successful reconciliation leaked its table-generation guard'
guard_add_line="$(grep -nFx "add counter inet fw4 $guard_name" "$NFT_CALL_LOG" | cut -d: -f1)"
first_chain_line="$(grep -nF -- '-j -a list chain inet fw4 ' "$NFT_CALL_LOG" | head -n 1 | cut -d: -f1)"
[ "$guard_add_line" -lt "$first_chain_line" ] || fail 'apply cached rule handles before creating its table-generation guard'
grep -F 'counter return comment "luci-app-tailscale: Tailscale 标记流量绕过 OpenClash（mangle output）"' "$NFT_BATCH_LOG" >/dev/null || \
	fail 'mangle output rule comment is not exact'
grep -F 'counter return comment "luci-app-tailscale: Tailscale 标记流量绕过 OpenClash（output）"' "$NFT_BATCH_LOG" >/dev/null || \
	fail 'output rule comment is not exact'
grep -F 'counter return comment "luci-app-tailscale: tailscale0 入站流量绕过 OpenClash（mangle）"' "$NFT_BATCH_LOG" >/dev/null || \
	fail 'mangle ingress rule comment is not exact'
grep -F 'counter return comment "luci-app-tailscale: tailscale0 入站流量绕过 OpenClash（filter）"' "$NFT_BATCH_LOG" >/dev/null || \
	fail 'filter ingress rule comment is not exact'

run_helper apply
[ "$(grep -c 'insert rule inet fw4' "$NFT_STATE")" = 4 ] || fail 'repeated apply duplicated owned rules'

hook_before_status="$(sha256sum "$HOOK" | awk '{print $1}')"
state_before_status="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
: >"$NFT_BATCH_LOG"
printf '%s' "$(run_helper status)" | jq -e '
	.state == "active" and .enabled == true and .openclash_present == true and
	.firewall4_supported == true and .hook == "managed" and .rules_present == 4 and
	.message == "OpenClash bypass is active."
' >/dev/null || fail 'complete managed state did not report active'
[ ! -s "$NFT_BATCH_LOG" ] || fail 'status mutated nftables state'
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$hook_before_status" ] || fail 'status rewrote the hook'
[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$state_before_status" ] || fail 'status rewrote nftables state'

sed 's#^[[:space:]]*/usr/sbin/tailscale_openclash_bypass apply$#\tprintf stale-status-hook#' "$HOOK" >"$TMP_DIR/stale-status-hook"
chmod 750 "$TMP_DIR/stale-status-hook"
mv "$TMP_DIR/stale-status-hook" "$HOOK"
printf '%s' "$(run_helper status)" | jq -e '.state == "error" and .hook == "error"' >/dev/null || \
	fail 'status accepted a noncanonical managed hook body'
run_helper reconcile-hook

for invalid_rule_mode in altered-match overbroad incomplete altered-verdict wrong-chain; do
	printf '%s' "$(NFT_RULE_JSON_MODE="$invalid_rule_mode" run_helper status)" | \
		jq -e '.state == "error" and .rules_present == 4' >/dev/null || \
		fail "status accepted noncanonical owned rule JSON mode $invalid_rule_mode"
done
NFT_RULE_JSON_MODE=canonical

printf '%s' "$(NFT_COUNTER_PACKETS=123456 NFT_COUNTER_BYTES=987654321 run_helper status)" | \
	jq -e '.state == "active" and .rules_present == 4' >/dev/null || \
	fail 'dynamic counter values changed canonical rule validation'
NFT_COUNTER_PACKETS=0
NFT_COUNTER_BYTES=0

cp "$NFT_STATE" "$TMP_DIR/nft-before-duplicate-status"
printf '%s\n' '901|insert rule inet fw4 openclash_mangle_output meta mark & 0x00ff0000 == 0x00080000 counter return comment "luci-app-tailscale: Tailscale 标记流量绕过 OpenClash（mangle output）"' >>"$NFT_STATE"
printf '%s' "$(run_helper status)" | jq -e '.state == "error" and .rules_present == 5' >/dev/null || \
	fail 'status accepted a duplicated canonical owned rule'
mv "$TMP_DIR/nft-before-duplicate-status" "$NFT_STATE"

cp "$NFT_STATE" "$TMP_DIR/nft-before-unexpected-status"
printf '%s\n' '902|insert rule inet fw4 openclash iifname "tailscale0" counter return comment "luci-app-tailscale: unexpected owned rule"' >>"$NFT_STATE"
printf '%s' "$(run_helper status)" | jq -e '.state == "error" and .rules_present == 5' >/dev/null || \
	fail 'status ignored an unexpected package-owned rule'
mv "$TMP_DIR/nft-before-unexpected-status" "$NFT_STATE"

for malformed_chain_mode in empty wrong-chain-object wrong-rule-chain missing-owned-handle; do
	: >"$NFT_BATCH_LOG"
	malformed_chain_state_hash="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
	malformed_chain_hook_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
	if NFT_CHAIN_JSON_TARGET=openclash_output NFT_CHAIN_JSON_MODE="$malformed_chain_mode" run_helper apply; then
		fail "apply accepted structurally invalid chain JSON mode $malformed_chain_mode"
	fi
	[ ! -s "$NFT_BATCH_LOG" ] || fail "invalid chain JSON mode $malformed_chain_mode submitted an apply batch"
	[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$malformed_chain_state_hash" ] || \
		fail "invalid chain JSON mode $malformed_chain_mode changed nft state during apply"
	printf '%s' "$(NFT_CHAIN_JSON_TARGET=openclash_output NFT_CHAIN_JSON_MODE="$malformed_chain_mode" run_helper status)" | \
		jq -e '.state == "error"' >/dev/null || \
		fail "status accepted structurally invalid chain JSON mode $malformed_chain_mode"
	if NFT_CHAIN_JSON_TARGET=openclash_output NFT_CHAIN_JSON_MODE="$malformed_chain_mode" run_helper cleanup; then
		fail "cleanup accepted structurally invalid chain JSON mode $malformed_chain_mode"
	fi
	[ ! -s "$NFT_BATCH_LOG" ] || fail "invalid chain JSON mode $malformed_chain_mode submitted a cleanup batch"
	[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$malformed_chain_state_hash" ] || \
		fail "invalid chain JSON mode $malformed_chain_mode changed nft state during cleanup"
	[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$malformed_chain_hook_hash" ] || \
		fail "invalid chain JSON mode $malformed_chain_mode removed the retry hook"
done
NFT_CHAIN_JSON_MODE=canonical
NFT_CHAIN_JSON_TARGET=

awk '!/insert rule inet fw4 openclash_output /' "$NFT_STATE" >"$TMP_DIR/nft-partial-before-missing-chain"
mv "$TMP_DIR/nft-partial-before-missing-chain" "$NFT_STATE"
: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
MISSING_CHAIN=openclash_output run_helper apply
[ -s "$NFT_BATCH_LOG" ] || fail 'missing target chain did not remove partial owned rules'
grep -F 'insert rule inet fw4' "$NFT_BATCH_LOG" >/dev/null && \
	fail 'missing target chain attempted to install a partial owned rule set'
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null && \
	fail 'missing target chain left partial owned rules in surviving chains'
printf '%s' "$(MISSING_CHAIN=openclash_output run_helper status)" | \
	jq -e '.state == "waiting" and .hook == "managed" and .rules_present == 0' >/dev/null || \
	fail 'missing chain did not report a residue-free waiting state'
MISSING_CHAIN=
run_helper apply
[ "$(grep -c 'comment "luci-app-tailscale:' "$NFT_STATE")" = 4 ] || \
	fail 'apply did not restore the complete rule set after the missing chain returned'

: >"$NFT_DISAPPEARED_FILE"
: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
DISAPPEAR_CHAIN=openclash_output run_helper apply
[ -s "$NFT_BATCH_LOG" ] || \
	fail 'apply did not clean surviving owned rules after a target chain disappeared during inspection'
grep -F 'luci-app-tailscale:' "$NFT_STATE" | grep -Fv 'openclash_output ' >/dev/null && \
	fail 'apply left a partial owned rule set after a target chain disappeared during inspection'
printf '%s' "$(DISAPPEAR_CHAIN=openclash_output run_helper status)" | \
	jq -e '.state == "waiting" and .hook == "managed" and .rules_present == 0' >/dev/null || \
	fail 'apply-time chain disappearance did not report a residue-free waiting state'
DISAPPEAR_CHAIN=
: >"$NFT_DISAPPEARED_FILE"
: >"$NFT_STATE"
run_helper apply
[ "$(grep -c 'comment "luci-app-tailscale:' "$NFT_STATE")" = 4 ] || \
	fail 'apply did not restore the complete rule set after an inspected chain returned'

: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
state_before_list_failure="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
if LIST_CHAIN_FAIL=openclash_output run_helper apply; then
	fail 'apply must fail when a table-enumerated chain cannot be listed'
fi
LIST_CHAIN_FAIL=
[ ! -s "$NFT_BATCH_LOG" ] || fail 'list-chain precheck failure wrote an nft batch'
assert_count 0 '-f ' "$NFT_CALL_LOG"
[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$state_before_list_failure" ] || \
	fail 'list-chain precheck failure changed nft state'
printf '%s' "$(LIST_CHAIN_FAIL=openclash_output run_helper status)" | jq -e '.state == "error"' >/dev/null || \
	fail 'table-enumerated list-chain failure did not report error'
LIST_CHAIN_FAIL=

: >"$NFT_GUARD_STATE"
: >"$NFT_CALL_LOG"
rm -f "$NFT_GUARD_DELETE_FAIL_ONCE_FILE"
if NFT_GUARD_DELETE_FAIL_ONCE=1 LIST_CHAIN_FAIL=openclash_output run_helper apply; then
	fail 'apply must fail when a chain read and the first independent guard deletion fail'
fi
[ ! -s "$NFT_GUARD_STATE" ] || fail 'EXIT cleanup did not retry a failed independent guard deletion'
[ "$(grep -c '^delete counter inet fw4 ' "$NFT_CALL_LOG")" -ge 2 ] || \
	fail 'failed independent guard deletion was not retried by EXIT cleanup'
NFT_GUARD_DELETE_FAIL_ONCE=0
LIST_CHAIN_FAIL=

: >"$NFT_GUARD_STATE"
: >"$NFT_CALL_LOG"
rm -f "$NFT_GUARD_DELETE_SIGNAL_ONCE_FILE"
if NFT_GUARD_DELETE_SIGNAL_ONCE=1 LIST_CHAIN_FAIL=openclash_output run_helper apply >/dev/null 2>&1; then
	fail 'apply must fail when terminated during independent guard deletion'
fi
[ ! -s "$NFT_GUARD_STATE" ] || fail 'termination during independent guard deletion leaked the tracked guard'
[ "$(grep -c '^delete counter inet fw4 ' "$NFT_CALL_LOG")" -ge 2 ] || \
	fail 'termination during independent guard deletion did not trigger EXIT cleanup'
NFT_GUARD_DELETE_SIGNAL_ONCE=0
LIST_CHAIN_FAIL=

: >"$NFT_BATCH_LOG"
state_before_failed_batch="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
if NFT_BATCH_FAIL=1 run_helper apply; then
	fail 'apply must fail when the nft batch fails'
fi
NFT_BATCH_FAIL=0
[ ! -s "$NFT_GUARD_STATE" ] || fail 'failed reconciliation leaked its table-generation guard'
[ -s "$NFT_BATCH_LOG" ] || fail 'failed apply did not submit an nft batch'
[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$state_before_failed_batch" ] || \
	fail 'failed nft batch changed state'
grep -F 'OpenClash nftables reconciliation transaction failed.' "$LOGGER_LOG" >/dev/null || \
	fail 'failed nft batch was not logged'

: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
state_before_mid_batch_failure="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
if NFT_BATCH_FAIL_AFTER=1 run_helper apply; then
	fail 'apply must fail when fake nft fails after the first batch operation'
fi
NFT_BATCH_FAIL_AFTER=0
[ -s "$NFT_BATCH_LOG" ] || fail 'mid-batch failure did not submit an nft batch'
assert_count 1 '-f ' "$NFT_CALL_LOG"
[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$state_before_mid_batch_failure" ] || \
	fail 'mid-batch fake nft failure changed the primary state'

if NFT_SIGNAL_PARENT=1 run_helper apply >/dev/null 2>&1; then
	fail 'apply must fail when terminated during nft replacement'
fi
NFT_SIGNAL_PARENT=0
find "$TMP_DIR/tmp" -name 'tailscale-openclash-nft.*' -print | grep . >/dev/null && \
	fail 'terminated nft reconciliation left a tracked temporary path'
[ ! -s "$NFT_GUARD_STATE" ] || fail 'terminated reconciliation leaked its table-generation guard'

: >"$NFT_BATCH_LOG"
if NFT_GENERATION_REPLACE=1 run_helper apply >/dev/null 2>&1; then
	fail 'apply must fail when inet fw4 is replaced after owned handles are cached'
fi
NFT_GENERATION_REPLACE=0
[ "$(grep -c 'unrelated-generation-rule-' "$NFT_STATE")" = 4 ] || \
	fail 'table replacement transaction deleted unrelated rules that reused cached handles'
[ ! -s "$NFT_GUARD_STATE" ] || fail 'table replacement failure leaked its stale guard state'
run_helper apply
[ "$(grep -c 'comment "luci-app-tailscale:' "$NFT_STATE")" = 4 ] || \
	fail 'apply did not recover after the deterministic table replacement'
[ "$(grep -c 'unrelated-generation-rule-' "$NFT_STATE")" = 4 ] || \
	fail 'recovery after table replacement removed unrelated rules'

for false_alias in 0 false off no disabled; do
	FEATURE_ENABLED=1 run_helper sync
	FEATURE_ENABLED="$false_alias" run_helper sync
	grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null && \
		fail "false alias $false_alias left owned nft rules"
	managed_hook_present "$HOOK" && \
		fail "false alias $false_alias left the managed hook"
	printf '%s' "$(FEATURE_ENABLED="$false_alias" run_helper status)" | \
		jq -e '.state == "disabled" and .enabled == false and .hook == "absent" and .rules_present == 0' >/dev/null || \
		fail "false alias $false_alias did not report disabled"
done

: >"$UCI_LOG"
FEATURE_ENABLED= UCI_SECTION_MODE=present run_helper sync
assert_line_count 1 '-q show tailscale_openclash.settings' "$UCI_LOG"
assert_line_count 0 '-q get tailscale_openclash.settings.enabled' "$UCI_LOG"
printf '%s' "$(FEATURE_ENABLED= UCI_SECTION_MODE=present run_helper status)" | \
	jq -e '.state == "active" and .enabled == true' >/dev/null || \
	fail 'a verified absent enabled option did not use the enabled default'

for uci_failure in missing error malformed; do
	printf '#!/bin/sh\nprintf user-only\n' >"$HOOK"
	: >"$NFT_STATE"
	: >"$NFT_BATCH_LOG"
	uci_failure_hook_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
	uci_failure_state_hash="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
	if UCI_SECTION_MODE="$uci_failure" FEATURE_ENABLED=1 run_helper sync; then
		fail "UCI section state $uci_failure must make sync fail"
	fi
	[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$uci_failure_hook_hash" ] || \
		fail "UCI section state $uci_failure changed the managed hook"
	[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$uci_failure_state_hash" ] || \
		fail "UCI section state $uci_failure changed nft state"
	[ ! -s "$NFT_BATCH_LOG" ] || fail "UCI section state $uci_failure submitted an nft batch"
	printf '%s' "$(UCI_SECTION_MODE="$uci_failure" FEATURE_ENABLED=1 run_helper status)" | \
		jq -e '.state == "error" and .enabled == false' >/dev/null || \
		fail "UCI section state $uci_failure did not report error"
done
UCI_SECTION_MODE=present

printf '#!/bin/sh\nprintf user-only\n' >"$HOOK"
: >"$NFT_STATE"
: >"$NFT_BATCH_LOG"
uci_get_failure_hook_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
uci_get_failure_state_hash="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
if UCI_OPTION_GET_FAIL=1 FEATURE_ENABLED=1 run_helper sync; then
	fail 'an operational failure reading a present enabled option must make sync fail'
fi
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$uci_get_failure_hook_hash" ] || \
	fail 'an enabled-option read failure changed the managed hook'
[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$uci_get_failure_state_hash" ] || \
	fail 'an enabled-option read failure changed nft state'
[ ! -s "$NFT_BATCH_LOG" ] || fail 'an enabled-option read failure submitted an nft batch'
printf '%s' "$(UCI_OPTION_GET_FAIL=1 FEATURE_ENABLED=1 run_helper status)" | \
	jq -e '.state == "error" and .enabled == false' >/dev/null || \
	fail 'an enabled-option read failure did not report error'
UCI_OPTION_GET_FAIL=0

printf '#!/bin/sh\nprintf user-only\n' >"$HOOK"
: >"$NFT_STATE"
: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
unsupported_hook_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
unsupported_state_hash="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
NFT_TABLE_STATE=TABLE_ABSENT FEATURE_ENABLED=1 run_helper sync
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$unsupported_hook_hash" ] || \
	fail 'unsupported firewall4 sync changed the OpenClash hook'
[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$unsupported_state_hash" ] || \
	fail 'unsupported firewall4 sync changed nft state'
[ ! -s "$NFT_BATCH_LOG" ] || fail 'unsupported firewall4 sync submitted an nft batch'
assert_line_count 1 '-j list tables' "$NFT_CALL_LOG"
assert_line_count 0 '-j list table inet fw4' "$NFT_CALL_LOG"
printf '%s' "$(NFT_TABLE_STATE=TABLE_ABSENT FEATURE_ENABLED=1 run_helper status)" | jq -e '.state == "unsupported"' >/dev/null || \
	fail 'missing firewall4 table did not report unsupported'

: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
NFT_TABLE_STATE=TABLE_ABSENT FEATURE_ENABLED=1 run_helper apply
[ ! -s "$NFT_BATCH_LOG" ] || fail 'verified absent firewall4 apply submitted an nft batch'
assert_line_count 1 '-j list tables' "$NFT_CALL_LOG"
assert_line_count 0 '-j list table inet fw4' "$NFT_CALL_LOG"

for table_failure in INVENTORY_READ_ERROR INVENTORY_MALFORMED TABLE_READ_ERROR TABLE_MALFORMED; do
	printf '#!/bin/sh\nprintf user-only\n' >"$HOOK"
	: >"$NFT_STATE"
	for helper_command in sync apply cleanup; do
		: >"$NFT_BATCH_LOG"
		table_failure_hook_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
		table_failure_state_hash="$(sha256sum "$NFT_STATE" | awk '{print $1}')"
		if NFT_TABLE_STATE="$table_failure" FEATURE_ENABLED=1 run_helper "$helper_command"; then
			fail "$helper_command must fail for nft table state $table_failure"
		fi
		[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$table_failure_hook_hash" ] || \
			fail "$helper_command changed the hook for nft table state $table_failure"
		[ "$(sha256sum "$NFT_STATE" | awk '{print $1}')" = "$table_failure_state_hash" ] || \
			fail "$helper_command changed nft state for nft table state $table_failure"
		[ ! -s "$NFT_BATCH_LOG" ] || \
			fail "$helper_command submitted an nft batch for nft table state $table_failure"
	done
	printf '%s' "$(NFT_TABLE_STATE="$table_failure" FEATURE_ENABLED=1 run_helper status)" | \
		jq -e '.state == "error"' >/dev/null || \
		fail "nft table state $table_failure did not report error"
done
NFT_TABLE_STATE=PRESENT

rm -f "$TMP_DIR/openclash-init"
absent_hook_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
FEATURE_ENABLED=1 run_helper sync
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$absent_hook_hash" ] || \
	fail 'OpenClash-absent sync changed the hook'
touch "$TMP_DIR/openclash-init"
chmod +x "$TMP_DIR/openclash-init"

: >"$NFT_BATCH_LOG"
MISSING_CHAIN=openclash_output FEATURE_ENABLED=1 run_helper sync
grep -Fx '# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash' "$HOOK" >/dev/null || \
	fail 'waiting sync did not install the canonical hook'
grep -Fx '	/usr/sbin/tailscale_openclash_bypass apply' "$HOOK" >/dev/null || \
	fail 'waiting sync did not install the canonical managed command'
[ ! -s "$NFT_BATCH_LOG" ] || fail 'waiting sync submitted a partial nft batch'
printf '%s' "$(MISSING_CHAIN=openclash_output FEATURE_ENABLED=1 run_helper status)" | \
	jq -e '.state == "waiting" and .hook == "managed" and .rules_present == 0' >/dev/null || \
	fail 'waiting sync did not report a canonical managed hook'
MISSING_CHAIN=

FEATURE_ENABLED=true run_helper sync
printf '%s' "$(FEATURE_ENABLED=true run_helper status)" | jq -e '.state == "active" and .rules_present == 4' >/dev/null || \
	fail 'sync did not produce active state for a true alias'

FEATURE_ENABLED=0 run_helper sync
: >"$UCI_LOG"
sync_ready="$TMP_DIR/sync-ready"
sync_release="$TMP_DIR/sync-release"
rm -f "$sync_ready" "$sync_release"
UCI_READY_FILE="$sync_ready" UCI_RELEASE_FILE="$sync_release" FEATURE_ENABLED=1 run_helper sync &
SYNC_ENABLE_PID=$!
attempt=0
while [ ! -e "$sync_ready" ]; do
	attempt=$((attempt + 1))
	[ "$attempt" -lt 100 ] || fail 'enabled sync did not reach the locked UCI read'
	sleep 0.05
done
FEATURE_ENABLED=0 run_helper sync &
SYNC_DISABLE_PID=$!
sleep 0.2
[ "$(grep -c '^-q get tailscale_openclash.settings.enabled$' "$UCI_LOG")" = 1 ] || \
	fail 'concurrent disabled sync passed the real flock before enabled sync completed'
: >"$sync_release"
wait "$SYNC_ENABLE_PID" || fail 'locked enabled sync failed'
SYNC_ENABLE_PID=
wait "$SYNC_DISABLE_PID" || fail 'serialized disabled sync failed'
SYNC_DISABLE_PID=
[ "$(grep -c '^-q get tailscale_openclash.settings.enabled$' "$UCI_LOG")" = 2 ] || \
	fail 'both serialized sync commands must re-read UCI under the lock'
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null && \
	fail 'serialized disable left owned nft rules'
managed_hook_present "$HOOK" && \
	fail 'serialized disable left the managed hook'
FEATURE_ENABLED=

: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
run_helper apply
: >"$NFT_BATCH_LOG"
: >"$NFT_CALL_LOG"
if LIST_CHAIN_FAIL=openclash_output run_helper cleanup; then
	fail 'cleanup must fail when a table-enumerated chain cannot be listed'
fi
LIST_CHAIN_FAIL=
[ ! -s "$NFT_BATCH_LOG" ] || fail 'cleanup list-chain failure wrote an nft batch'
assert_count 0 '-f ' "$NFT_CALL_LOG"
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null || fail 'list-chain cleanup failure changed owned nft rules'
run_helper reconcile-hook
if NFT_BATCH_FAIL=1 run_helper cleanup; then
	fail 'cleanup must fail when the nft delete batch fails'
fi
NFT_BATCH_FAIL=0
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null || fail 'failed cleanup batch changed owned nft rules'
managed_hook_present "$HOOK" || fail 'failed nft cleanup must retain the managed hook for retry'
printf '%s' "$(FEATURE_ENABLED=0 run_helper status)" | jq -e '
	.state == "error" and .enabled == false and .hook == "managed" and
	.rules_present == 4
' >/dev/null || fail 'disabled status did not expose retained cleanup artifacts'

FEATURE_ENABLED=0 run_helper apply
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null && fail 'cleanup retry left owned nft rules'
managed_hook_present "$HOOK" && fail 'cleanup retry left the managed hook'
printf '%s' "$(FEATURE_ENABLED=0 run_helper status)" | jq -e '
	.state == "disabled" and .enabled == false and .hook == "absent" and
	.rules_present == 0
' >/dev/null || fail 'successful cleanup retry did not report a residue-free disabled state'

FEATURE_ENABLED=1 run_helper sync
printf '%s\n' '900|insert rule inet fw4 openclash iifname "tailscale0" counter return comment "user-owned-rule"' >>"$NFT_STATE"
run_helper cleanup
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null && fail 'cleanup left owned nft rules'
grep -F 'user-owned-rule' "$NFT_STATE" >/dev/null || fail 'cleanup removed a user-owned rule'
managed_hook_present "$HOOK" && fail 'cleanup left the managed hook block'

FEATURE_ENABLED=1 run_helper sync
: >"$NFT_BATCH_LOG"
NFT_TABLE_STATE=TABLE_ABSENT run_helper cleanup
NFT_TABLE_STATE=PRESENT
[ ! -s "$NFT_BATCH_LOG" ] || fail 'cleanup with an absent fw4 table submitted an nft batch'
: >"$NFT_STATE"

FEATURE_ENABLED=1 run_helper sync
awk '!/insert rule inet fw4 openclash_output /' "$NFT_STATE" >"$TMP_DIR/nft-with-missing-chain"
mv "$TMP_DIR/nft-with-missing-chain" "$NFT_STATE"
MISSING_CHAIN=openclash_output run_helper cleanup
MISSING_CHAIN=
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null && \
	fail 'cleanup with an already absent target chain left rules from existing chains'

FEATURE_ENABLED=1 run_helper sync
: >"$NFT_DISAPPEARED_FILE"
: >"$NFT_CALL_LOG"
DISAPPEAR_CHAIN=openclash_output run_helper cleanup
DISAPPEAR_CHAIN=
[ "$(grep -c '^-j list table inet fw4$' "$NFT_CALL_LOG")" -ge 2 ] || \
	fail 'cleanup did not refresh table state after a chain disappeared'
: >"$NFT_STATE"
: >"$NFT_DISAPPEARED_FILE"

printf '%s' "$(run_helper status)" | jq -e '.state == "error"' >/dev/null || \
	fail 'incomplete managed state did not report error'

rm -f "$HOOK"
printf '%s' "$(MISSING_CHAIN=openclash_output run_helper status)" | jq -e '.state == "waiting" and .hook == "absent"' >/dev/null || \
	fail 'missing hook and target chain did not report waiting'
MISSING_CHAIN=
mkdir "$HOOK"
printf '%s' "$(run_helper status)" | jq -e '.state == "error" and .hook == "error"' >/dev/null || \
	fail 'hook read failure did not report error'
rmdir "$HOOK"

printf '%s\n' '# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash' >>"$HOOK"
printf '%s' "$(run_helper status)" | jq -e '.state == "error"' >/dev/null || \
	fail 'malformed markers did not report error'
printf '%s' "$(NFT_TABLE_STATE=TABLE_ABSENT FEATURE_ENABLED=0 run_helper status)" | \
	jq -e '.state == "error" and .enabled == false and .hook == "error"' >/dev/null || \
	fail 'verified absent firewall4 table hid a malformed disabled hook'
printf '%s' "$(NFT_TABLE_STATE=TABLE_ABSENT UCI_SECTION_MODE=error FEATURE_ENABLED=1 run_helper status)" | \
	jq -e '.state == "error" and .enabled == false' >/dev/null || \
	fail 'verified absent firewall4 table hid an operational UCI failure'
printf '%s' "$(NFT_JSON_UNSUPPORTED=1 FEATURE_ENABLED=0 run_helper status)" | jq -e '.state == "error"' >/dev/null || \
	fail 'malformed nft JSON did not report error'
rm -f "$HOOK"
printf '%s' "$(NFT_TABLE_STATE=TABLE_ABSENT FEATURE_ENABLED=0 run_helper status)" | \
	jq -e '.state == "disabled" and .enabled == false and .firewall4_supported == false and .hook == "absent" and .rules_present == 0' >/dev/null || \
	fail 'disabled state with no fw4 table and no hook did not report cleanly disabled'
run_helper reconcile-hook
printf '%s' "$(NFT_TABLE_STATE=TABLE_ABSENT FEATURE_ENABLED=0 run_helper status)" | \
	jq -e '.state == "error" and .enabled == false and .firewall4_supported == false and .hook == "managed" and .rules_present == 0' >/dev/null || \
	fail 'disabled state with no fw4 table hid a retained managed hook'
NFT_TABLE_STATE=TABLE_ABSENT run_helper cleanup
rm -f "$TMP_DIR/openclash-init"
printf '%s' "$(NFT_TABLE_STATE=TABLE_ABSENT run_helper status)" | jq -e '.state == "absent"' >/dev/null || \
	fail 'OpenClash absence did not take status precedence'
grep -F 'firewall' "$UCI_LOG" >/dev/null && fail 'helper queried the firewall UCI package'

printf '%s\n' 'tailscale OpenClash bypass tests passed'
