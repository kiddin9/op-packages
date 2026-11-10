# Local upstream-readiness validation

## Loading and online-status updates: 2026-11-10

- Node regression suite: 124 passed, including cold/expired-cache loading,
  cached-empty lists, sequential unknown-device checks and stale-reply handling.
- Python regression suite: 8 passed.
- Official LuCI ESLint configuration, native message extraction and GNU gettext
  checks passed; shell/JavaScript syntax and whitespace checks passed.
- Chromium tests used synthetic RPC data to verify the installed legacy-version
  compatibility patches: the page renders before slow discovery, empty messages
  wait for online checks, failed loading can be retried, and source warnings close
  manually or after 12 seconds. These are fixture-based browser results.
- Targeted frontend compatibility patches were installed on OpenWrt 23.05.5 at
  192.168.1.1. Served resources matched the validated patch files. Hash checks
  confirmed network, wireless and device-manager configuration files were intact.
  The stale wlan0 discovery failure was reproduced using live RPC data and fixed.

The router runs an older development version with the targeted compatibility
patches; it is not a full-package acceptance test of the current upstream export.
SDK packaging, package upgrades, account enforcement and physical browser/theme
acceptance have not been rerun for this revision. Earlier SDK evidence below
belongs to the dated snapshots and does not validate the new revision.

## PR review follow-up: 2026-10-11

Addressed the dependency, license installation, redundant initializer and
in-tree README comments on OpenWrt LuCI PR #9125.

- Full Node regression suite: 100 passed, 0 failed, 0 skipped.
- Python regression suite, including the exported installation instructions:
  8 passed.
- Official LuCI ESLint, native translation extraction, gettext, shell syntax
  and whitespace checks passed.
- Official OpenWrt BusyBox packages tested locally with the SDK musl loader:
  SNAPSHOT 1.38.0-r3 and 24.10.4 1.36.1-r3. Both support
  `ip -o -4 addr show dev lo`, `ip neigh show` and `flock -n 9`.
  The actual RPC helper parsed IPv4 and IPv6 neighbor output from both binaries.
- The 33 shell/Ping/scan regressions passed with each official BusyBox binary,
  its flock applet and SDK-native jshn. Network probes, netifd and UCI inputs
  were isolated fixtures; no router was modified.
- Rebuilt the main and Chinese language APKs in the x86/64 SNAPSHOT SDK.
  Main-package dependencies are libc, luci-base, rpcd-mod-iwinfo and jshn.
  ip-tiny, ip-full and util-linux flock were disabled in the SDK configuration.
  The extra license installation hook and packaged configuration initializer
  were removed; MIT and Apache-2.0 declarations and source notices remain.

Compatibility evidence and official binaries: /tmp/device-manager-review-compat/.
SDK build log: /tmp/device-manager-review-sdk-build.log.
Real-router acceptance and a stable-release SDK build remain unverified.

## Initial validation: 2026-10-10

The checks below describe the initial submission snapshot, before the PR review
follow-up. No router was modified during that validation.

## Passed checks

- Node regression suite: 100 passed, 0 failed, 0 skipped.
- Python regression suite: 8 passed.
- Official LuCI master ESLint configuration: no errors or warnings.
- Native POT extraction: 184 source messages, including menu, ACL and UI.
- GNU gettext template/catalogue comparison and PO checks.
- SDK-native jshn regression run: 33 passed, 0 skipped. Network and UCI inputs were isolated fixtures.
- Workflow YAML parsing and every run block checked with bash -n.
- Shell syntax and git diff --check.

## SDK package validation

- Official x86/64 SNAPSHOT SDK archive SHA256:
  60b7182a36d0542810e5564dcf9f7c2531bbbc74546ededcbc619b2939b72127
- SDK base source commit: 53ec2d05a487e6011cfa096de9211d15197c501b.
- LuCI reference commit: 36720dd716c7f7008af95c0d520edefab621adb7.
- SDK download checksum was verified. Official GitHub mirrors were used for feeds, retaining the SDK base commit.
- Main package and Chinese language package compiled successfully.
- ip-tiny and ip-full dependency variants both built; each main package depends only on its selected IP implementation.
- Unpacked the ip-tiny packages and checked executable RPC helper, configuration preservation metadata, both applicable license texts, icon attribution and absence of legacy bundled translations.
- The language package LMO matches a fresh compilation of the current PO using SDK po2lmo.

Local APKs and manifest: /tmp/device-manager-built-packages/. These are local validation builds.
The local package version uses the existing source HEAD while compiling this uncommitted working tree.
CI builds calculate the version from the checked-out source commit; upstream builds use the LuCI feed revision.

## Remaining external acceptance

Real-router installation, upgrades, reboot persistence, account enforcement, packet captures, themes and mobile UI remain to be checked using the README acceptance steps.
GitHub Actions was validated locally but has not been triggered remotely.
Stable-release SDK/IPK builds have not been rerun in this validation.
