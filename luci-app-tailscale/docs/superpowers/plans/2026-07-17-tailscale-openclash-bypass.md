# Tailscale OpenClash Bypass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a package-owned, firewall4/nftables-only OpenClash bypass that is applied through OpenClash's official custom firewall hook, while preserving the existing WAN-direct and site-to-site SNAT behavior as independent flows.

**Architecture:** Keep the existing WAN-direct and Tailscale firewall-zone logic in `tailscale_helper`; the new `/usr/sbin/tailscale_openclash_bypass` helper owns only one marked hook block and four runtime nftables rules. Store the OpenClash toggle in the app-owned `/etc/config/tailscale_openclash` package and give it a dedicated procd reload trigger, because the existing `tailscale` trigger is package-wide and would otherwise restart Tailscale and execute the WAN/firewall path for an OpenClash-only change. The setting remains visible in the existing Tailscale LuCI page, while status is loaded asynchronously through a read-only rpcd method.

**Tech Stack:** OpenWrt 24.10 firewall4, nftables JSON output, POSIX `ash`, `flock`, `jq`, UCI/procd, LuCI JavaScript, shell and Node.js behavior tests.

## Approved Final-Review Corrections

The user approved these corrections on 2026-07-17 after read-only verification
against the office OpenWrt 24.10.5 target. They supersede conflicting details in
Tasks 1-6 below:

- BusyBox 1.36 `grep` on the target has no `-b`; hook parsing must use exact
  whole marker lines and BusyBox-compatible `awk`/POSIX tools while preserving
  all bytes outside the managed block.
- The canonical managed body must be validated and repaired. A user line that
  merely contains marker text is not a managed marker.
- The procd lifecycle invokes one helper `sync` operation. `sync` re-reads UCI
  and reconciles hook plus runtime rules under one lock; it does not call
  `reconcile-hook` and `apply` as separate transactions.
- Unsupported or absent OpenClash/firewall4 states are side-effect-free. Missing
  OpenClash chains may install the canonical hook and report `waiting`, allowing
  the next official OpenClash hook execution to apply rules.
- Remove the custom package `postinst`. Standard LuCI/OpenWrt package lifecycle
  must retain LuCI cache invalidation, `rpcd` reload, and normal init handling.
- Normalize UCI booleans with OpenWrt semantics.
- Site-to-site no-SNAT creates/maintains `firewall.tszone.masq='0'` even when no
  forwarding access tokens are selected; forwarding sections still depend only
  on the access list.
- Cleanup treats an absent fw4 table/chains as success, refreshes state after
  chain-read races, restores owner before mode, and removes tracked temporary
  files on signals.

## Global Constraints

- Preserve every pre-existing working-tree change; do not run `git reset`, `git checkout`, `git restore`, or overwrite files modified by another session.
- Before each task, run `git status --short --branch` and stage only the paths named by that task.
- WAN direct owns only firewall UCI objects and firewall4 reload behavior.
- OpenClash bypass must not read or write firewall UCI, modify `/etc/config/firewall`, reload or restart firewall4, or manage the OpenClash service.
- OpenClash bypass must be invoked by `/etc/openclash/custom/openclash_custom_firewall_rules.sh` after OpenClash creates its chains.
- Support only firewall4/nftables; do not add firewall3 or iptables compatibility.
- Use test-driven development: add a failing focused test, observe the expected failure, implement the smallest change, then rerun focused and full tests.
- Do not connect to or modify any production OpenWrt during this plan. Device deployment and remote verification require a separate explicit `ok`.
- Do not push, merge, tag, publish a release, or start a GitHub Actions package build during this local implementation phase.

## Current-Tree Audit

- Plan baseline is branch `codex/fix-release-install-instructions` at `10fa8b6`; do not switch, reset, rebase, or merge this worktree before preserving any newer user changes found at execution time.
- Baseline at plan creation: all existing `tests/*_test.sh` and `tests/*_test.js` pass.
- WAN direct already belongs in this app as an explicit, disabled-by-default option. It reads the current Tailscale listen port, supports multiple firewall source zones, creates idempotent `firewall.ts_wan_direct_*` rules, and removes them when disabled.
- `子网互通` maps to `disable_snat_subnet_routes=1`. The current init script passes `--snat-subnet-routes=false`, and `tailscale_helper` sets the app-owned `firewall.tszone.masq=0`. Turning it off restores `--snat-subnet-routes=true` and `masq=1`.
- The dual SNAT behavior is implemented but lacks a behavioral regression test. Task 1 adds that protection before OpenClash work begins.
- No OpenClash helper, hook lifecycle, dedicated UCI package, rpcd status method, or LuCI control exists yet.

## File Map

**Create:**

- `root/usr/sbin/tailscale_openclash_bypass`: sole owner of the managed hook block and four nftables rules.
- `root/etc/config/tailscale_openclash`: app-owned toggle, isolated from the `tailscale` package reload trigger.
- `root/etc/init.d/tailscale-openclash-bypass`: one-shot reconciler with a reload trigger only for `tailscale_openclash`.
- `tests/tailscale_openclash_bypass_test.sh`: hook, nftables, locking, status, and cleanup behavior.
- `tests/tailscale_openclash_lifecycle_test.sh`: UCI/procd and package lifecycle isolation.
- `tests/setting_openclash_bypass_test.js`: LuCI separate-UCI binding and nonblocking status behavior.

**Modify:**

- `tests/tailscale_helper_network_cleanup_test.sh`: prove fw4 `masq` follows the site-to-site setting.
- `tests/tailscale_init_adguard_lifecycle_test.sh`: prove Tailscale receives the matching `--snat-subnet-routes` flag.
- `Makefile`: package install/upgrade/removal hooks and no new OpenClash service dependency.
- `root/usr/libexec/rpcd/luci.tailscale`: read-only OpenClash bypass status method.
- `root/usr/share/rpcd/acl.d/luci-app-tailscale.json`: read access for status and UCI access for `tailscale_openclash`.
- `htdocs/luci-static/resources/view/tailscale/setting.js`: OpenClash tab, toggle, and asynchronous status.
- `po/templates/tailscale.pot`, `po/zh_Hans/tailscale.po`, `po/zh_Hant/tailscale.po`: UI strings.
- `tests/package_release_test.sh`: package inventory and strict flow-isolation assertions.
- `README.md`: supported backend, ownership, status, and rollback documentation.

---

### Task 1: Lock Down Existing WAN and Site-to-Site Contracts

**Files:**
- Modify: `tests/tailscale_helper_network_cleanup_test.sh:243-425`
- Modify: `tests/tailscale_init_adguard_lifecycle_test.sh:21-356`
- Test: `tests/tailscale_helper_network_cleanup_test.sh`
- Test: `tests/tailscale_init_adguard_lifecycle_test.sh`

**Interfaces:**
- Consumes: `DISABLE_SNAT_SUBNET_ROUTES`, `configure_tailscale_access_rules()`, and `tailscale_helper()` from the existing implementation.
- Produces: regression coverage proving `disable_snat_subnet_routes` controls both Tailscale `NoSNAT` and app-owned fw4 zone masquerade.

- [ ] **Step 1: Extend the firewall test harness and write the failing no-SNAT assertions**

In `run_helper()`, insert this assignment after the existing `access` assignment:

```sh
disable_snat_subnet_routes="${6:-0}"
```

Replace the existing forced value:

```sh
DISABLE_SNAT_SUBNET_ROUTES=0
```

with:

```sh
DISABLE_SNAT_SUBNET_ROUTES="$disable_snat_subnet_routes"
```

Then add this sequence after the existing access-rule assertions:

```sh

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts" 1
assert_contains "firewall.tszone.masq=0" "$(cat "$TMP_DIR/uci_db")" \
	"site-to-site enable must disable masquerade in the app-owned Tailscale firewall zone"
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" \
	"changing site-to-site SNAT must reload firewall4 through the existing firewall flow"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts" 1
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "unchanged no-SNAT firewall state must be idempotent"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "unchanged no-SNAT firewall state must not reload firewall4"

run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts" 0
assert_contains "firewall.tszone.masq=1" "$(cat "$TMP_DIR/uci_db")" \
	"site-to-site disable must restore masquerade in the app-owned Tailscale firewall zone"
```

- [ ] **Step 2: Run the focused firewall test and confirm the harness fails before accepting the new argument**

Run:

```sh
sh tests/tailscale_helper_network_cleanup_test.sh
```

Expected: FAIL because the original harness forces `DISABLE_SNAT_SUBNET_ROUTES=0`, so `firewall.tszone.masq=0` is absent.

- [ ] **Step 3: Implement only the sixth-argument harness change and rerun the test**

Run:

```sh
sh tests/tailscale_helper_network_cleanup_test.sh
```

Expected: `tailscale_helper network cleanup tests passed`.

- [ ] **Step 4: Add a behavioral init-script capture for both Tailscale SNAT values**

Add a fake procd command recorder to `tests/tailscale_init_adguard_lifecycle_test.sh`:

```sh
capture_tailscale_snat_args() {
	disable_snat="$1"
	PROCD_LOG="$TMP_DIR/procd-snat-$disable_snat.log"
	: >"$PROCD_LOG"
	export PROCD_LOG
	(
		. "$INIT_SCRIPT"
		PROGS="$TMP_DIR/fake-secrets"
		config_get() {
			case "$3" in
				port) eval "$1=41641" ;;
				access) eval "$1=ts_ac_lan" ;;
				*) eval "$1=" ;;
			esac
		}
		config_get_bool() {
			case "$3" in
				disable_snat_subnet_routes) eval "$1=$disable_snat" ;;
				accept_dns) eval "$1=1" ;;
				*) eval "$1=0" ;;
			esac
		}
		config_list_foreach() { :; }
		procd_open_instance() { :; }
		procd_set_param() { printf 'set:%s\n' "$*" >>"$PROCD_LOG"; }
		procd_append_param() { printf 'append:%s\n' "$*" >>"$PROCD_LOG"; }
		procd_close_instance() { :; }
		tailscale_helper settings
	)
	cat "$PROCD_LOG"
}

snat_disabled_args="$(capture_tailscale_snat_args 1)"
printf '%s\n' "$snat_disabled_args" | grep -F -- '--snat-subnet-routes=false' >/dev/null || \
	fail "site-to-site enable must pass --snat-subnet-routes=false"
printf '%s\n' "$snat_disabled_args" | grep -F 'DISABLE_SNAT_SUBNET_ROUTES=1' >/dev/null || \
	fail "site-to-site enable must pass no-SNAT state to the firewall helper"

snat_enabled_args="$(capture_tailscale_snat_args 0)"
printf '%s\n' "$snat_enabled_args" | grep -F -- '--snat-subnet-routes=true' >/dev/null || \
	fail "site-to-site disable must pass --snat-subnet-routes=true"
printf '%s\n' "$snat_enabled_args" | grep -F 'DISABLE_SNAT_SUBNET_ROUTES=0' >/dev/null || \
	fail "site-to-site disable must pass SNAT state to the firewall helper"
```

- [ ] **Step 5: Run both focused tests**

Run:

```sh
sh tests/tailscale_helper_network_cleanup_test.sh
sh tests/tailscale_init_adguard_lifecycle_test.sh
```

Expected: both scripts print their existing `tests passed` messages.

- [ ] **Step 6: Commit only the regression tests**

```sh
git add tests/tailscale_helper_network_cleanup_test.sh tests/tailscale_init_adguard_lifecycle_test.sh
git commit -m "test: lock down Tailscale subnet SNAT behavior"
```

### Task 2: Implement Ownership-Safe OpenClash Hook Reconciliation

**Files:**
- Create: `tests/tailscale_openclash_bypass_test.sh`
- Create: `root/usr/sbin/tailscale_openclash_bypass`

**Interfaces:**
- Consumes: `/etc/openclash/custom/openclash_custom_firewall_rules.sh`, `flock`, and the app-owned `tailscale_openclash.settings.enabled` value.
- Produces: `tailscale_openclash_bypass reconcile-hook` and `tailscale_openclash_bypass cleanup`, with a uniquely delimited managed block and ownership-scoped rollback.

- [ ] **Step 1: Create hook fixtures and failing behavior tests**

Create `tests/tailscale_openclash_bypass_test.sh` with a temporary OpenClash tree and these assertions:

```sh
#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/root/usr/sbin/tailscale_openclash_bypass"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-openclash-test.$$"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_count() {
	expected="$1"; needle="$2"; file="$3"
	actual="$(grep -cF -- "$needle" "$file" || true)"
	[ "$actual" = "$expected" ] || fail "$file expected $expected occurrences of $needle, got $actual"
}

mkdir -p "$TMP_DIR/openclash/custom" "$TMP_DIR/bin"
touch "$TMP_DIR/openclash-init"
chmod +x "$TMP_DIR/openclash-init"
HOOK="$TMP_DIR/openclash/custom/openclash_custom_firewall_rules.sh"
printf '#!/bin/sh\nprintf user-before\nprintf user-after\n' >"$HOOK"
chmod 750 "$HOOK"
original_owner="$(stat -c '%u:%g' "$HOOK")"
original_hash="$(sha256sum "$HOOK" | awk '{print $1}')"

run_helper() {
	OPENCLASH_INIT="$TMP_DIR/openclash-init" \
	OPENCLASH_HOOK_FILE="$HOOK" \
	LOCK_FILE="$TMP_DIR/lock" \
	UCI_BIN="$TMP_DIR/bin/uci" \
	NFT_BIN="$TMP_DIR/bin/nft" \
	JQ_BIN=jq \
	"$SCRIPT" "$@"
}

run_helper reconcile-hook
assert_count 1 '# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash' "$HOOK"
assert_count 1 '# END luci-app-tailscale 托管：Tailscale 绕过 OpenClash' "$HOOK"
grep -F 'printf user-before' "$HOOK" >/dev/null || fail 'hook insertion removed user content before the block'
grep -F 'printf user-after' "$HOOK" >/dev/null || fail 'hook insertion removed user content after the block'
[ "$(stat -c '%a' "$HOOK")" = 750 ] || fail 'hook mode changed'
[ "$(stat -c '%u:%g' "$HOOK")" = "$original_owner" ] || fail 'hook ownership changed'

first_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
run_helper reconcile-hook
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$first_hash" ] || fail 'reconcile-hook is not idempotent'

cp "$HOOK" "$TMP_DIR/hook-before-malformed"
printf '%s\n' '# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash' >>"$HOOK"
malformed_hash="$(sha256sum "$HOOK" | awk '{print $1}')"
if run_helper reconcile-hook >/dev/null 2>&1; then
	fail 'duplicate managed markers must fail'
fi
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$malformed_hash" ] || fail 'malformed hook changed after rejection'

cp "$TMP_DIR/hook-before-malformed" "$HOOK"
run_helper cleanup
grep -F 'luci-app-tailscale 托管' "$HOOK" >/dev/null && fail 'cleanup left the managed hook block'
grep -F 'printf user-before' "$HOOK" >/dev/null || fail 'cleanup removed user content'
[ "$(sha256sum "$HOOK" | awk '{print $1}')" = "$original_hash" ] || \
	fail 'hook cleanup did not restore every original byte'
```

Also test these states in the same script:

```sh
rm -f "$TMP_DIR/openclash-init" "$HOOK"
run_helper reconcile-hook
[ ! -e "$HOOK" ] || fail 'OpenClash-absent reconciliation created a custom script'

touch "$TMP_DIR/openclash-init"
chmod +x "$TMP_DIR/openclash-init"
run_helper reconcile-hook
[ -x "$HOOK" ] || fail 'missing OpenClash custom script was not created executable'
sh -n "$HOOK" || fail 'created hook is not valid shell'
```

- [ ] **Step 2: Run the new test and confirm the helper is missing**

Run:

```sh
sh tests/tailscale_openclash_bypass_test.sh
```

Expected: FAIL because `root/usr/sbin/tailscale_openclash_bypass` does not exist.

- [ ] **Step 3: Implement the hook-only helper commands**

Create `root/usr/sbin/tailscale_openclash_bypass` with these constants and command contract:

```sh
#!/bin/sh
set -u

OPENCLASH_INIT="${OPENCLASH_INIT:-/etc/init.d/openclash}"
OPENCLASH_HOOK_FILE="${OPENCLASH_HOOK_FILE:-/etc/openclash/custom/openclash_custom_firewall_rules.sh}"
LOCK_FILE="${LOCK_FILE:-/var/lock/tailscale-openclash-bypass.lock}"
UCI_BIN="${UCI_BIN:-uci}"
NFT_BIN="${NFT_BIN:-nft}"
JQ_BIN="${JQ_BIN:-jq}"
LOGGER_CMD="${LOGGER_CMD:-logger}"

BEGIN_MARKER='# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash'
END_MARKER='# END luci-app-tailscale 托管：Tailscale 绕过 OpenClash'

managed_block() {
	cat <<'EOF'
# BEGIN luci-app-tailscale 托管：Tailscale 绕过 OpenClash
if test -x /usr/sbin/tailscale_openclash_bypass; then
	/usr/sbin/tailscale_openclash_bypass apply
fi
# END luci-app-tailscale 托管：Tailscale 绕过 OpenClash
EOF
}
```

Implement these exact functions in the same file:

```sh
openclash_installed() { test -x "$OPENCLASH_INIT"; }
log_error() { "$LOGGER_CMD" -p daemon.err -t tailscale_openclash_bypass "$*"; }

marker_state() {
	file="$1"
	begin_count="$(grep -cF -- "$BEGIN_MARKER" "$file" 2>/dev/null || true)"
	end_count="$(grep -cF -- "$END_MARKER" "$file" 2>/dev/null || true)"
	[ "$begin_count" = 0 ] && [ "$end_count" = 0 ] && { printf 'absent\n'; return 0; }
	[ "$begin_count" = 1 ] && [ "$end_count" = 1 ] || return 1
	begin_line="$(grep -nF -- "$BEGIN_MARKER" "$file" | cut -d: -f1)"
	end_line="$(grep -nF -- "$END_MARKER" "$file" | cut -d: -f1)"
	[ "$begin_line" -lt "$end_line" ] || return 1
	printf 'present\n'
}
```

`reconcile_hook()` must preserve bytes outside the managed block. Locate exact
whole-line markers with BusyBox-compatible tools; do not use `grep -b`. The
parser must distinguish marker-like user text, reject duplicate/malformed marker
pairs, and replace a noncanonical managed body. Use byte-preserving prefix/suffix
copies and insert the managed block immediately after the shebang line. Treat any
separator newline introduced for the block as part of the managed byte range so
`cleanup_hook()` restores the original file hash even when the original last line
has no newline. Build a temp file in the hook's directory, run `sh -n`, restore
numeric owner/group before mode, and atomically `mv` it over the hook. When the
file is absent, create a minimal `#!/bin/sh` script with mode `0755`. Any malformed
marker state must return nonzero before a write, and every failure or signal
before `mv` must delete only the tracked temp file.

`cleanup_hook()` must use the same parser and atomic replacement path, but omit the managed block. It must return zero when OpenClash, the hook, or the managed block is absent.

Acquire one exclusive lock before dispatching mutating commands:

```sh
exec 9>"$LOCK_FILE" || exit 1
flock -x 9 || exit 1
case "${1:-}" in
	reconcile-hook) openclash_installed || exit 0; reconcile_hook ;;
	cleanup) cleanup_hook ;;
	*) printf 'usage: %s {reconcile-hook|cleanup}\n' "$0" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run hook tests and shell syntax checks**

Run:

```sh
sh -n root/usr/sbin/tailscale_openclash_bypass
sh tests/tailscale_openclash_bypass_test.sh
```

Expected: syntax passes and all hook assertions pass; nft assertions are added in Task 3.

- [ ] **Step 5: Commit the hook reconciler**

```sh
git add root/usr/sbin/tailscale_openclash_bypass tests/tailscale_openclash_bypass_test.sh
git commit -m "feat: add ownership-safe OpenClash hook"
```

### Task 3: Reconcile Four nftables Rules Atomically and Report Status

**Files:**
- Modify: `tests/tailscale_openclash_bypass_test.sh`
- Modify: `root/usr/sbin/tailscale_openclash_bypass`

**Interfaces:**
- Consumes: `nft -j -a list chain inet fw4 <chain>` and `nft -f <batch>`.
- Produces: `apply`, complete `cleanup`, and JSON `status` with `active`, `waiting`, `disabled`, `absent`, `unsupported`, or `error` state.

- [ ] **Step 1: Add a stateful fake nft command and failing rule tests**

The fake must expose all four target chains, record the single `nft -f` batch, and return owned handles from JSON. Add assertions for these exact managed rules:

```text
insert rule inet fw4 openclash_mangle_output meta mark & 0x00ff0000 == 0x00080000 counter comment "luci-app-tailscale: Tailscale 标记流量绕过 OpenClash（mangle output）" return
insert rule inet fw4 openclash_output meta mark & 0x00ff0000 == 0x00080000 counter comment "luci-app-tailscale: Tailscale 标记流量绕过 OpenClash（output）" return
insert rule inet fw4 openclash_mangle iifname "tailscale0" counter comment "luci-app-tailscale: tailscale0 入站流量绕过 OpenClash（mangle）" return
insert rule inet fw4 openclash iifname "tailscale0" counter comment "luci-app-tailscale: tailscale0 入站流量绕过 OpenClash（filter）" return
```

Add test cases that verify:

```sh
run_helper apply
assert_count 1 'insert rule inet fw4 openclash_mangle_output ' "$NFT_BATCH_LOG"
assert_count 1 'insert rule inet fw4 openclash_output ' "$NFT_BATCH_LOG"
assert_count 1 'insert rule inet fw4 openclash_mangle iifname "tailscale0"' "$NFT_BATCH_LOG"
assert_count 1 'insert rule inet fw4 openclash iifname "tailscale0"' "$NFT_BATCH_LOG"

run_helper apply
[ "$(grep -c 'insert rule inet fw4' "$NFT_STATE")" = 4 ] || fail 'repeated apply duplicated owned rules'

MISSING_CHAIN=openclash_output run_helper apply
[ ! -s "$NFT_BATCH_LOG" ] || fail 'missing target chain produced a partial nft transaction'
printf '%s' "$(run_helper status)" | jq -e '.state == "waiting"' >/dev/null || fail 'missing chain did not report waiting'

run_helper cleanup
grep -F 'luci-app-tailscale:' "$NFT_STATE" >/dev/null && fail 'cleanup left owned nft rules'
grep -F 'user-owned-rule' "$NFT_STATE" >/dev/null || fail 'cleanup removed a user-owned rule'
```

- [ ] **Step 2: Run the focused test and confirm `apply` and `status` fail**

Run:

```sh
sh tests/tailscale_openclash_bypass_test.sh
```

Expected: FAIL at the first `apply` assertion because Task 2 intentionally left nft commands unimplemented.

- [ ] **Step 3: Implement complete-chain validation and one nft transaction**

Add an exact rule registry:

```sh
rule_specs() {
	cat <<'EOF'
openclash_mangle_output|luci-app-tailscale: Tailscale 标记流量绕过 OpenClash（mangle output）|meta mark & 0x00ff0000 == 0x00080000
openclash_output|luci-app-tailscale: Tailscale 标记流量绕过 OpenClash（output）|meta mark & 0x00ff0000 == 0x00080000
openclash_mangle|luci-app-tailscale: tailscale0 入站流量绕过 OpenClash（mangle）|iifname "tailscale0"
openclash|luci-app-tailscale: tailscale0 入站流量绕过 OpenClash（filter）|iifname "tailscale0"
EOF
}
```

For each spec, first run `"$NFT_BIN" -j -a list chain inet fw4 "$chain"`. Do not create a batch until every call succeeds. Extract only handles whose JSON rule comment exactly equals the registered comment:

```sh
printf '%s' "$chain_json" | "$JQ_BIN" -r --arg comment "$comment" '
	.nftables[] | .rule? | select(.comment == $comment) | .handle
'
```

Write all owned-handle deletions and four `insert rule` statements to one temp batch, then execute one `"$NFT_BIN" -f "$batch"`. A failed batch returns nonzero and is logged; nftables transaction semantics prevent partial application.

`cleanup_rules()` uses the same exact-comment handle lookup and one delete-only batch. Missing chains are successful no-ops during cleanup, and user-owned equivalent rules are never selected.

- [ ] **Step 4: Implement machine-readable status without mutating state**

Use `jq -nc` to return one object with these fields:

```json
{
  "state": "active",
  "enabled": true,
  "openclash_present": true,
  "firewall4_supported": true,
  "hook": "managed",
  "rules_present": 4,
  "message": "OpenClash bypass is active."
}
```

Status precedence must be:

1. OpenClash absent -> `absent`.
2. firewall4 table or nft JSON unsupported -> `unsupported`.
3. configured disabled -> `disabled`.
4. malformed/duplicate markers -> `error`.
5. one or more target chains absent -> `waiting`.
6. hook and all four exact owned comments present -> `active`.
7. every other incomplete state -> `error`.

Read only `tailscale_openclash.settings.enabled`; never query the `firewall` UCI package. Default enabled is `1` when the option is absent and OpenClash is installed.

- [ ] **Step 5: Finish cleanup and rerun focused tests**

`cleanup_all()` must call `cleanup_hook` and `cleanup_rules` under the same lock, preserve the first nonzero result, and never call firewall4 or OpenClash service commands.

Replace the Task 2 dispatcher with the final command set:

```sh
case "${1:-}" in
	reconcile-hook)
		openclash_installed || exit 0
		reconcile_hook
		;;
	apply)
		openclash_installed || exit 0
		feature_enabled || { cleanup_rules; exit $?; }
		apply_rules
		;;
	cleanup)
		cleanup_all
		;;
	status)
		print_status
		;;
	*)
		printf 'usage: %s {reconcile-hook|apply|cleanup|status}\n' "$0" >&2
		exit 2
		;;
esac
```

Run:

```sh
sh -n root/usr/sbin/tailscale_openclash_bypass
sh tests/tailscale_openclash_bypass_test.sh
```

Expected: `tailscale OpenClash bypass tests passed`.

- [ ] **Step 6: Commit atomic nft reconciliation**

```sh
git add root/usr/sbin/tailscale_openclash_bypass tests/tailscale_openclash_bypass_test.sh
git commit -m "feat: reconcile OpenClash bypass rules"
```

### Task 4: Add an Independent UCI and Package Lifecycle

**Files:**
- Create: `root/etc/config/tailscale_openclash`
- Create: `root/etc/init.d/tailscale-openclash-bypass`
- Create: `tests/tailscale_openclash_lifecycle_test.sh`
- Modify: `Makefile:7-21`
- Modify: `tests/package_release_test.sh:126-199,500-547`

**Interfaces:**
- Consumes: helper commands `sync`, `apply`, and `cleanup` from Tasks 2-3.
- Produces: a package-owned UCI toggle whose reload trigger cannot invoke `/etc/init.d/tailscale` or the WAN-direct helper.

- [ ] **Step 1: Write failing lifecycle and static-isolation tests**

Create `tests/tailscale_openclash_lifecycle_test.sh` that sources the new init script with a fake helper and verifies:

```sh
enabled_log="$(run_sync 1)"
[ "$enabled_log" = "sync" ] || fail "enabled OpenClash bypass must reconcile under one helper lock"

disabled_log="$(run_sync 0)"
[ "$disabled_log" = "cleanup" ] || fail "disabled OpenClash bypass must remove only owned state"

grep -F 'procd_add_reload_trigger "tailscale_openclash"' "$INIT_SCRIPT" >/dev/null || \
	fail 'OpenClash lifecycle needs its own UCI reload trigger'
grep -F 'procd_add_reload_trigger "tailscale"' "$INIT_SCRIPT" >/dev/null && \
	fail 'OpenClash lifecycle must not subscribe to the core Tailscale UCI package'
grep -E '/etc/init.d/(firewall|openclash)|fw4 (reload|restart)' "$INIT_SCRIPT" >/dev/null && \
	fail 'OpenClash lifecycle must not manage firewall4 or OpenClash services'
```

Extend `tests/package_release_test.sh` with these hard boundaries:

```sh
assert_file root/usr/sbin/tailscale_openclash_bypass
assert_file root/etc/config/tailscale_openclash
assert_file root/etc/init.d/tailscale-openclash-bypass
assert_not_contains "tailscale_openclash_bypass" root/usr/sbin/tailscale_helper
assert_not_contains "openclash_custom_firewall_rules.sh" root/usr/sbin/tailscale_helper
assert_not_contains "/etc/config/firewall" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "uci commit firewall" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "/etc/init.d/firewall" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "/etc/init.d/openclash reload" root/usr/sbin/tailscale_openclash_bypass
assert_not_contains "/etc/init.d/openclash restart" root/usr/sbin/tailscale_openclash_bypass
```

- [ ] **Step 2: Run both tests and confirm lifecycle files are missing**

Run:

```sh
sh tests/tailscale_openclash_lifecycle_test.sh
sh tests/package_release_test.sh
```

Expected: both fail on missing package files.

- [ ] **Step 3: Add the dedicated UCI package and one-shot init script**

Create `root/etc/config/tailscale_openclash`:

```uci
config openclash 'settings'
	option enabled '1'
```

Create `root/etc/init.d/tailscale-openclash-bypass`:

```sh
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1
PROG="${PROG:-/usr/sbin/tailscale_openclash_bypass}"

service_triggers() {
	procd_add_reload_trigger "tailscale_openclash"
}

sync_instance() {
	"$PROG" sync
}

start_service() {
	config_load tailscale_openclash
	config_foreach sync_instance openclash
}

reload_service() {
	start_service
}

stop_service() {
	"$PROG" cleanup
}
```

This script must contain no reference to `/etc/init.d/tailscale`, `/etc/init.d/firewall`, `fw4 reload`, or OpenClash service actions.

- [ ] **Step 4: Preserve standard installation and add removal cleanup**

Do not define `Package/luci-app-tailscale/postinst`; the LuCI default post-install
script must retain cache cleanup and `rpcd` reload, while OpenWrt
`default_postinst` handles packaged init scripts. In `Makefile`, retain the
existing Tailscale stop behavior and add OpenClash cleanup before it:

```make
define Package/luci-app-tailscale/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ -x /usr/sbin/tailscale_openclash_bypass ]; then
	/usr/sbin/tailscale_openclash_bypass cleanup >/dev/null 2>&1 || true
fi
if [ -z "$${IPKG_INSTROOT}" ] && [ -x /etc/init.d/tailscale ]; then
	/etc/init.d/tailscale stop >/dev/null 2>&1 || exit 1
fi
exit 0
endef
```

The OpenClash cleanup is best-effort and runs while the helper still exists. It does not suppress the existing failure handling for Tailscale's own managed firewall cleanup.

- [ ] **Step 5: Run focused lifecycle, package, and syntax tests**

Run:

```sh
sh -n root/etc/init.d/tailscale-openclash-bypass
sh tests/tailscale_openclash_lifecycle_test.sh
sh tests/package_release_test.sh
```

Expected: all pass.

- [ ] **Step 6: Commit the isolated package lifecycle**

```sh
git add Makefile root/etc/config/tailscale_openclash root/etc/init.d/tailscale-openclash-bypass tests/tailscale_openclash_lifecycle_test.sh tests/package_release_test.sh
git commit -m "feat: isolate OpenClash bypass lifecycle"
```

### Task 5: Add Read-Only Status RPC and LuCI Control

**Files:**
- Create: `tests/setting_openclash_bypass_test.js`
- Modify: `root/usr/libexec/rpcd/luci.tailscale:6-180`
- Modify: `root/usr/share/rpcd/acl.d/luci-app-tailscale.json:4-24`
- Modify: `htdocs/luci-static/resources/view/tailscale/setting.js:16-62,349-362,470-766,849-852`

**Interfaces:**
- Consumes: helper `status` JSON and UCI package `tailscale_openclash`.
- Produces: read-only rpcd method `openclash_bypass_status` and a LuCI tab whose setting writes only `tailscale_openclash.settings.enabled`.

- [ ] **Step 1: Write failing rpcd and LuCI binding tests**

Extend `tests/tailscale_rpcd_test.sh` to require the new method and exact helper pass-through:

```sh
printf '%s\n' '{}' | OPENCLASH_BYPASS_BIN="$TMP_DIR/openclash-helper" \
	"$RPCD_SCRIPT" call openclash_bypass_status | \
	jq -e '.state == "active" and .rules_present == 4' >/dev/null || \
	fail 'rpcd must return the helper status object unchanged'
```

Create `tests/setting_openclash_bypass_test.js` with static and VM assertions:

```js
const fs = require('fs');
const source = fs.readFileSync('htdocs/luci-static/resources/view/tailscale/setting.js', 'utf8');

function assert(value, message) {
	if (!value)
		throw new Error(message);
}

assert(source.includes("uci.load('tailscale_openclash')"), 'setting view must load the isolated OpenClash UCI package');
assert(source.includes("method: 'openclash_bypass_status'"), 'setting view must use the read-only status RPC');
assert(source.includes("uci.set('tailscale_openclash', 'settings', 'enabled'"), 'toggle must write only the isolated UCI package');
assert(!source.includes("uci.set('tailscale', section_id, 'openclash"), 'toggle must not write the core Tailscale UCI package');

const loadBody = source.match(/load\(\)\s*\{([\s\S]*?)\n\t\},\n\n\trender/)[1];
assert(!loadBody.includes('callOpenclashBypassStatus('), 'OpenClash status must not block initial page rendering');
assert(source.includes('refreshOpenclashBypassStatus'), 'status must refresh after render');

console.log('setting OpenClash bypass tests passed');
```

- [ ] **Step 2: Run tests and confirm the RPC and UI are absent**

Run:

```sh
sh tests/tailscale_rpcd_test.sh
node tests/setting_openclash_bypass_test.js
```

Expected: both fail on missing `openclash_bypass_status` support.

- [ ] **Step 3: Implement the read-only rpcd method**

Add:

```sh
OPENCLASH_BYPASS_BIN="${OPENCLASH_BYPASS_BIN:-/usr/sbin/tailscale_openclash_bypass}"

run_openclash_bypass_status() {
	"$OPENCLASH_BYPASS_BIN" status
}
```

Add `"openclash_bypass_status":{}` to `print_methods()` and dispatch it without parsing caller-controlled command arguments. In the ACL, grant read access to `openclash_bypass_status` and UCI read/write access to `tailscale_openclash`; do not expose helper execution through the generic LuCI file-exec ACL.

- [ ] **Step 4: Add an asynchronous OpenClash tab to the existing settings page**

Declare the RPC and status renderer:

```js
const callOpenclashBypassStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'openclash_bypass_status',
	expect: { '': {} },
	reject: true
});

function renderOpenclashBypassStatus(status) {
	const labels = {
		active: _('Enabled and active'),
		waiting: _('Enabled; waiting for OpenClash nftables chains'),
		disabled: _('Disabled'),
		absent: _('OpenClash is not installed'),
		unsupported: _('Unsupported: firewall4/nftables is required'),
		error: _('Configuration error')
	};
	return labels[status && status.state] || _('Unknown status');
}

async function refreshOpenclashBypassStatus() {
	const node = document.getElementById('openclash_bypass_status');
	if (!node)
		return;
	try {
		const status = await callOpenclashBypassStatus();
		node.textContent = renderOpenclashBypassStatus(status);
	} catch (error) {
		node.textContent = _('Unable to read OpenClash bypass status.');
	}
}
```

Load `tailscale_openclash` alongside the existing UCI loads, but do not call the status RPC from `load()`. Add a dedicated tab:

```js
s.tab('openclash', _('OpenClash'));

o = s.taboption('openclash', form.Flag, 'openclash_bypass_enabled', _('Enable OpenClash Bypass'),
	_('Bypass OpenClash for Tailscale marked host traffic and traffic entering from tailscale0. This feature does not reload firewall4 or manage the OpenClash service.'));
o.default = o.enabled;
o.rmempty = false;
o.cfgvalue = function() {
	return uci.get('tailscale_openclash', 'settings', 'enabled') || '1';
};
o.write = function(section_id, value) {
	return uci.set('tailscale_openclash', 'settings', 'enabled', value);
};
o.remove = function() {
	return uci.set('tailscale_openclash', 'settings', 'enabled', '0');
};

o = s.taboption('openclash', form.DummyValue, '_openclash_bypass_status', _('Status'));
o.rawhtml = true;
o.cfgvalue = function() { return ''; };
o.renderWidget = function() {
	return E('span', { id: 'openclash_bypass_status' }, _('Checking ...'));
};
```

After `m.render()`, schedule `refreshOpenclashBypassStatus` next to the existing AdGuard refresh:

```js
window.setTimeout(refreshAdguardPreflightStatus, 0);
window.setTimeout(refreshOpenclashBypassStatus, 0);
```

- [ ] **Step 5: Run RPC, LuCI, and syntax tests**

Run:

```sh
sh tests/tailscale_rpcd_test.sh
node tests/setting_openclash_bypass_test.js
node --check htdocs/luci-static/resources/view/tailscale/setting.js
sh -n root/usr/libexec/rpcd/luci.tailscale
jq -e . root/usr/share/rpcd/acl.d/luci-app-tailscale.json >/dev/null
```

Expected: all commands pass.

- [ ] **Step 6: Commit the UI and status API**

```sh
git add htdocs/luci-static/resources/view/tailscale/setting.js root/usr/libexec/rpcd/luci.tailscale root/usr/share/rpcd/acl.d/luci-app-tailscale.json tests/setting_openclash_bypass_test.js tests/tailscale_rpcd_test.sh
git commit -m "feat: add OpenClash bypass controls"
```

### Task 6: Complete Translations, Documentation, and Full Local Verification

**Files:**
- Modify: `po/templates/tailscale.pot`
- Modify: `po/zh_Hans/tailscale.po`
- Modify: `po/zh_Hant/tailscale.po`
- Modify: `README.md:64-89`
- Modify: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: state names and UI strings from Task 5.
- Produces: complete Simplified/Traditional Chinese UI, operational documentation, and a locally verified source tree ready for review.

- [ ] **Step 1: Add failing translation inventory assertions**

Require every new msgid in the template and both translations. At minimum assert these Simplified Chinese values:

```text
OpenClash -> OpenClash
Enable OpenClash Bypass -> 启用 OpenClash 绕过
Status -> 状态
Enabled and active -> 已启用并生效
Enabled; waiting for OpenClash nftables chains -> 已启用，等待 OpenClash 创建 nftables 链
Disabled -> 已禁用
OpenClash is not installed -> 未安装 OpenClash
Unsupported: firewall4/nftables is required -> 不支持：需要 firewall4/nftables
Configuration error -> 配置错误
Unable to read OpenClash bypass status. -> 无法读取 OpenClash 绕过状态。
```

Run:

```sh
sh tests/package_release_test.sh
```

Expected: FAIL on the first missing translation assertion.

- [ ] **Step 2: Update the POT and both PO files**

Add all Task 5 msgids. Use natural Traditional Chinese equivalents in `po/zh_Hant/tailscale.po`, including `啟用 OpenClash 繞過`, `已啟用並生效`, and `未安裝 OpenClash`. Preserve existing translation entries and run format validation.

- [ ] **Step 3: Document ownership, lifecycle, and rollback separately from WAN direct**

Add a `## OpenClash Bypass` section to `README.md` containing these facts:

````markdown
## OpenClash Bypass

- Supports firewall4/nftables only.
- Enabled by default when the packaged setting is present; it is a no-op when OpenClash is absent.
- Manages one delimited block in `/etc/openclash/custom/openclash_custom_firewall_rules.sh`.
- The managed block invokes `/usr/sbin/tailscale_openclash_bypass apply` through OpenClash's official custom firewall hook.
- Manages exactly four comment-owned rules in OpenClash's nftables chains.
- Does not modify `/etc/config/firewall`, reload firewall4, or start/restart OpenClash.
- WAN direct remains a separate feature that manages only its own firewall UCI rules.

Rollback:

```sh
uci set tailscale_openclash.settings.enabled='0'
uci commit tailscale_openclash
/etc/init.d/tailscale-openclash-bypass reload
/usr/sbin/tailscale_openclash_bypass status
```
````

Do not add production hostnames, public IPs, credentials, or device-specific OpenClash content to the package README.

- [ ] **Step 4: Run the complete existing and new behavior suite**

Run:

```sh
set -eu
for test in tests/*_test.sh; do sh "$test"; done
for test in tests/*_test.js; do node "$test"; done
```

Expected: every script exits zero and prints its pass message.

- [ ] **Step 5: Run all local syntax, JSON, translation, and diff checks**

Run:

```sh
set -eu
for file in .github/scripts/*.sh; do bash -n "$file"; done
for file in root/etc/init.d/tailscale root/etc/init.d/tailscale-openclash-bypass root/etc/hotplug.d/iface/* root/etc/uci-defaults/* root/usr/libexec/rpcd/* root/usr/sbin/tailscale_* tests/*_test.sh; do sh -n "$file"; done
for file in htdocs/luci-static/resources/view/tailscale/*.js tests/*_test.js; do node --check "$file"; done
for file in root/usr/share/luci/menu.d/*.json root/usr/share/rpcd/acl.d/*.json; do jq -e . "$file" >/dev/null; done
for file in po/templates/*.pot po/*/*.po; do msgfmt --check-format -o /dev/null "$file"; done
git diff --check
```

Expected: no output except test pass messages, and exit status zero.

- [ ] **Step 6: Verify strict isolation from source text**

Run:

```sh
! rg -n '/etc/config/firewall|uci (set|delete|commit) firewall|/etc/init.d/firewall|fw4 (reload|restart)' root/usr/sbin/tailscale_openclash_bypass root/etc/init.d/tailscale-openclash-bypass
! rg -n 'tailscale_openclash_bypass|openclash_custom_firewall_rules' root/usr/sbin/tailscale_helper root/etc/init.d/tailscale
! rg -n '/etc/init.d/openclash (start|stop|restart|reload|enable|disable)' root/usr/sbin/tailscale_openclash_bypass root/etc/init.d/tailscale-openclash-bypass
```

Expected: all three negated searches exit zero and print nothing.

- [ ] **Step 7: Commit documentation and translations**

```sh
git add README.md po/templates/tailscale.pot po/zh_Hans/tailscale.po po/zh_Hant/tailscale.po tests/package_release_test.sh
git commit -m "docs: document OpenClash bypass management"
```

### Task 7: Correct Final-Review Findings Against OpenWrt 24.10

**Files:**
- Modify: `docs/superpowers/specs/2026-07-16-tailscale-openclash-bypass-design.md`
- Modify: `docs/superpowers/plans/2026-07-17-tailscale-openclash-bypass.md`
- Modify: `root/usr/sbin/tailscale_openclash_bypass`
- Modify: `root/etc/init.d/tailscale-openclash-bypass`
- Modify: `root/usr/sbin/tailscale_helper`
- Modify: `Makefile`
- Modify: `tests/tailscale_openclash_bypass_test.sh`
- Modify: `tests/tailscale_openclash_lifecycle_test.sh`
- Modify: `tests/tailscale_helper_network_cleanup_test.sh`
- Modify: `tests/package_release_test.sh`
- Modify: `README.md`

**Interfaces:**
- Preserves: WAN-direct ownership of firewall UCI/firewall4 reloads only.
- Preserves: OpenClash ownership of one official custom-hook block and four
  comment-owned runtime nftables rules only.
- Produces: one-lock `sync`, BusyBox-compatible hook handling, standard LuCI
  installation lifecycle, and empty-access no-SNAT correctness.

- [x] **Step 1: Add focused failing regression tests**

Add tests proving:

1. no production path invokes `grep -b`, and the hook works with a fake grep that
   rejects `-b`;
2. marker-like user text is preserved, exact duplicate/malformed markers fail,
   and a stale managed body is replaced canonically;
3. `sync` performs one locked decision after re-reading UCI, including concurrent
   enable/disable coverage;
4. missing OpenClash or unsupported fw4 produces no hook/rule side effect, while
   present fw4 with missing OpenClash chains produces `waiting` with a canonical
   hook;
5. cleanup succeeds when the fw4 table or target chains are already absent, and
   a disappearing chain is reclassified from refreshed table state;
6. false aliases `0`, `false`, `off`, `no`, and `disabled` disable the feature;
7. site-to-site no-SNAT with an empty access list keeps `tszone.masq=0` and creates
   no forwarding sections; disabling no-SNAT with empty access removes the zone;
8. standard LuCI post-install behavior is not replaced by a custom package
   `postinst`;
9. replacement restores owner before mode and tracked temporary files are removed
   after termination;
10. fake nftables rejects nonexistent handles and the locking test uses real
    `flock` behavior.

Run each focused test before implementation and retain the expected failure
output in the task report.

- [x] **Step 2: Implement the smallest complete corrections**

Implement `sync` under one exclusive lock. It re-reads UCI itself and dispatches
the full enabled/disabled state. Keep `apply` for the OpenClash-owned hook, but do
not split procd reconciliation into two helper invocations. Use exact whole-line,
canonical hook parsing without `grep -b`; clean only package-owned state; never
touch firewall UCI or manage OpenClash/firewall4 services.

Remove the custom package post-install block. Keep best-effort package removal
cleanup. Decouple `tszone` existence from forwarding-token existence when
site-to-site no-SNAT is enabled.

- [x] **Step 3: Strengthen lifecycle, race, and documentation coverage**

Document all status states and ownership cleanup. Make the fake nftables harness
fail on stale/nonexistent handles and add a deterministic generation-race case.
Verify unsupported, waiting, disabled, active, and cleanup behavior through the
public command interface.

- [x] **Step 4: Run focused and full verification**

Run:

```sh
set -eu
sh tests/tailscale_openclash_bypass_test.sh
sh tests/tailscale_openclash_lifecycle_test.sh
sh tests/tailscale_helper_network_cleanup_test.sh
sh tests/package_release_test.sh
for test in tests/*_test.sh; do sh "$test"; done
for test in tests/*_test.js; do node "$test"; done
```

Then run every syntax, JSON, translation, strict-isolation, and diff check from
Task 6. No router is modified in Task 7.

- [x] **Step 5: Commit Task 7 as one review-fix commit**

Stage only Task 7 paths and preserve the pre-existing modified SDD reports.
Record the final commit range and request a fresh whole-branch review against
merge base `7f100d587f473eb73d8736ef9731d644c75b6b2d`.

## Local Completion Gate

After Task 7, stop. Report:

- the exact local commits created;
- the complete test and syntax results;
- `git status --short --branch` without changing or staging unrelated files;
- confirmation that no router, server, GitHub branch, PR, tag, release, or Actions workflow was modified.

Production deployment remains a separate operation requiring a new explicit `ok`. That later verification must first read current device state, take rollback backups, and then independently verify:

1. OpenClash hook content outside the managed block is unchanged.
2. Four owned rules are at the heads of the expected chains with no duplicates.
3. OpenClash restart recreates the rules through its custom hook without a firewall4 reload.
4. Disabling removes only the owned block and rules.
5. WAN direct still creates only its firewall UCI rules and cold-start direct connectivity works.
6. Site-to-site enabled shows both Tailscale `NoSNAT=true` and `firewall.tszone.masq='0'`, with routing table 52 intact.
