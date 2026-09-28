# Final Review Fix Report

## Scope completed

All six final-review corrections were implemented as one fix wave:

1. Added an nftables table-generation guard before handle caching, made its deletion the first operation in the atomic reconciliation batch, and covered success, failure, signal, cleanup, and deterministic table-replacement paths.
2. Distinguished a verified absent UCI `enabled` option from UCI section/read failures.
3. Added `nft -j list tables` inventory checks so verified `inet fw4` absence remains non-fatal while inventory, table-read, and malformed-JSON failures remain errors.
4. Reordered cleanup to remove nftables rules before the hook, retained the hook when nftables cleanup failed, and made disabled status report managed residue.
5. Bumped `PKG_VERSION` to `1.2.8`.
6. Made status require the canonical managed hook body and exact structured nftables rule expressions while allowing dynamic counter values.

A second independent whole-branch review found five additional reconciliation issues, which were fixed before deployment:

1. Chain reads now require structurally valid nftables JSON with exactly one matching chain object and correctly scoped rules with numeric handles.
2. The command used by the official OpenClash hook now performs full cleanup when the feature is disabled, including removal of the managed hook.
3. A failed or interrupted independent generation-guard deletion remains tracked so the EXIT trap can retry it.
4. Status validates UCI and disabled managed artifacts before treating an absent `inet fw4` table as unsupported.
5. If any target OpenClash chain is absent, reconciliation removes any surviving package-owned partial rule set and waits without installing a subset.

A final focused review found one remaining apply-time race: a target chain could disappear after the initial complete table snapshot but before its individual chain read. That path now removes package-owned rules from all surviving chains instead of returning with a partial rule set.

## Strict TDD evidence

Temporary test paths in two failure messages are normalized as `<tmp>`; all other output is verbatim.

### Correction 1: table-generation guard

- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: apply must create a named counter before caching owned handles`
- GREEN command: `sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

### Correction 2: UCI absence versus failure

- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: <tmp>/uci.log expected 1 exact occurrences of -q show tailscale_openclash.settings, got 0`
- GREEN command: `sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

### Correction 3: nftables table inventory

- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: <tmp>/nft.calls expected 1 occurrences of -j list tables, got 0`
- GREEN command: `sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

### Correction 4: retryable cleanup and disabled residue

- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: false alias 0 did not report disabled`
- GREEN command: `sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

### Correction 5: release version

- RED command: `sh tests/package_release_test.sh`
- RED result: exit 1, `FAIL: Makefile should contain: PKG_VERSION:=1.2.8`
- GREEN command: `sh tests/package_release_test.sh`
- GREEN result: exit 0, `package release tests passed`

### Correction 6: canonical status validation

- RED command: `sh -n tests/tailscale_openclash_bypass_test.sh && sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: status accepted a noncanonical managed hook body`
- GREEN command: `sh -n root/usr/sbin/tailscale_openclash_bypass && sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

### Second review: strict chain JSON validation

- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: apply accepted structurally invalid chain JSON mode empty`
- GREEN command: `sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`
- Compatibility evidence: a read-only query against the office OpenWrt 24.10.5 / nftables 1.1.1 returned the expected `metainfo`, matching `chain`, and scoped `rule` objects with numeric handles. The fake nft fixture now includes that real top-level structure.

### Second review: retryable hook cleanup and generation guard

- Added regression coverage for the actual official hook path (`apply` while disabled), independent guard-deletion failure, and termination during guard deletion.
- GREEN result: `tailscale OpenClash bypass tests passed`

### Second review: status ordering and partial-rule cleanup

- Added regression coverage for invalid UCI with no fw4 table, disabled hook residue with no fw4 table, clean disabled state with no fw4 table, and a missing target chain with surviving partial owned rules.
- GREEN result: `tailscale OpenClash bypass tests passed`

### Final review: apply-time chain disappearance

- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: apply did not clean surviving owned rules after a target chain disappeared during inspection`
- GREEN command: `sh -n root/usr/sbin/tailscale_openclash_bypass && sh -n tests/tailscale_openclash_bypass_test.sh && sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

### Office preflight: OpenWrt applet compatibility

- A read-only preflight on the office OpenWrt 24.10.5 image confirmed that neither `stat` nor `od` is installed or provided as a BusyBox applet.
- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1 after fake target-image `stat` and `od` commands returned 127.
- Replaced hook metadata reads with POSIX `ls -ldn | awk` parsing. The parser preserves owner/group, ordinary mode bits, and setuid/setgid/sticky bits.
- Replaced single-byte hexadecimal inspection with `dd | grep` newline detection, using commands present on the target image.
- Added regression coverage that hides `stat` and `od` from the helper and verifies numeric restoration of mode `6750` after atomic replacement.
- GREEN command: `sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

### Compatibility re-review: byte-read errors and special modes

- A fresh independent review found that a POSIX pipeline exposed only the final `grep` status, so an underlying `dd` failure could be mistaken for an ordinary non-newline byte at the optional suffix boundary.
- RED command: `sh tests/tailscale_openclash_bypass_test.sh`
- RED result: exit 1, `FAIL: reconcile-hook must fail when the optional-newline probe cannot be read`
- The byte probe now appends and parses the `dd` status without losing a leading newline to command substitution. It returns three distinct states: newline, non-newline/EOF, and read error.
- Both optional-newline call sites now abort atomic replacement on a read error.
- Added special-mode reconciliation and cleanup coverage for `4640`, `1750`, `1751`, and `7777`, in addition to the existing `6750` check. This covers uppercase and lowercase setuid/setgid/sticky renderings (`S/s/T/t`).
- GREEN command: `sh tests/tailscale_openclash_bypass_test.sh`
- GREEN result: exit 0, `tailscale OpenClash bypass tests passed`

The complete 11-file shell suite and 4-file JavaScript suite also passed after the compatibility correction GREEN.

## Final verification

Focused checks:

```sh
sh -n root/usr/sbin/tailscale_openclash_bypass && \
sh -n tests/tailscale_openclash_bypass_test.sh && \
sh tests/tailscale_openclash_bypass_test.sh
sh -n tests/package_release_test.sh && sh tests/package_release_test.sh
```

Result: both passed.

Complete shell suite:

```sh
set -eu
count=0
for test_file in tests/*_test.sh; do
	sh "$test_file"
	count=$((count + 1))
done
printf 'shell test files passed: %s\n' "$count"
```

Latest result after the target-image compatibility correction: `shell test files passed: 11`.

Complete JavaScript suite:

```sh
set -eu
count=0
for test_file in tests/*_test.js; do
	node "$test_file"
	count=$((count + 1))
done
printf 'JavaScript test files passed: %s\n' "$count"
```

Latest result after the target-image compatibility correction: `JavaScript test files passed: 4`.

Static gates:

```sh
for file in .github/scripts/*.sh; do bash -n "$file"; done
for file in root/etc/init.d/tailscale root/etc/init.d/tailscale-openclash-bypass root/etc/hotplug.d/iface/* root/etc/uci-defaults/* root/usr/libexec/rpcd/* root/usr/sbin/tailscale_* tests/*_test.sh; do sh -n "$file"; done
for file in htdocs/luci-static/resources/view/tailscale/*.js tests/*_test.js; do node --check "$file"; done
for file in root/usr/share/luci/menu.d/*.json root/usr/share/rpcd/acl.d/*.json; do jq -e . "$file" >/dev/null; done
for file in po/templates/*.pot po/*/*.po; do msgfmt --check-format -o /dev/null "$file"; done
git diff --check
```

Latest results: 23 shell syntax files, 8 JavaScript syntax files, 2 JSON files, 3 translation files, both the whole-branch and working-tree `git diff --check` checks passed.

Ownership-isolation searches returned no matches:

```sh
rg -n '/etc/config/firewall|uci (set|delete|commit) firewall|/etc/init.d/firewall|fw4 (reload|restart)' root/usr/sbin/tailscale_openclash_bypass root/etc/init.d/tailscale-openclash-bypass
rg -n 'tailscale_openclash_bypass|openclash_custom_firewall_rules' root/usr/sbin/tailscale_helper root/etc/init.d/tailscale
rg -n '/etc/init.d/openclash (start|stop|restart|reload|enable|disable)' root/usr/sbin/tailscale_openclash_bypass root/etc/init.d/tailscale-openclash-bypass
```

No Docker, MkDocs, router write, service reload/restart, GitHub, or production mutation command was used. Read-only SSH checks queried the office OpenWrt's nftables JSON and available applets for compatibility evidence; `hzsls-openwrt` was not accessed.

## Files changed

- `Makefile`
- `root/usr/sbin/tailscale_openclash_bypass`
- `tests/package_release_test.sh`
- `tests/tailscale_openclash_bypass_test.sh`
- `.superpowers/sdd/final-review-fix-report.md`

The pre-existing modifications to task-1 through task-4 reports were preserved byte-for-byte relative to their initial working-tree diff and excluded from staging.

## Self-review

- Reviewed the complete production and test diff against all six required corrections.
- Confirmed the generation-replacement fake preserves unrelated rules that reuse stale handles.
- Confirmed guard cleanup paths cover success, batch failure, signal exit, no-op cleanup, and table replacement.
- Confirmed status rejects noncanonical hooks, altered/overbroad/incomplete/wrong-chain rules, duplicate rules, and unexpected package-owned rules while accepting changing counter values.
- Confirmed cleanup failure leaves the hook retryable and disabled status reports both hook and rule residue.
- Confirmed structurally invalid chain JSON cannot trigger apply or cleanup mutation.
- Confirmed a missing target chain removes surviving partial owned rules and never installs an incomplete set.
- Confirmed a target chain disappearing after the initial snapshot also removes the surviving partial owned rules and reports a residue-free waiting state.
- Confirmed OpenWrt 24.10.5 / nftables 1.1.1 real chain JSON satisfies the strict validator.
- Confirmed only the five files listed above belong to this fix wave.

## Remaining concerns

Office deployment and device-level behavior verification remain pending execution of the approved backup/change/verification/rollback plan. No deployment write has started yet.

The final independent re-review of commit `94eb302` reported: `未发现可操作问题，READY`.
