# Changelog

## [0.3.24-r1] - 2026-09-19

- Bump version for release.

## [0.3.23-r2] - 2026-09-19

### Added

- Send canonical `device.device_code` and `device.device_code_source` metadata with Hub resolve requests and expose the same identity through `safeshield.status`.
- Prefer `/usr/share/smartsafehub/firmware.json` as the authoritative device-code source for SmartSafeHub firmware, with exact board-name mappings for supported standalone SafeShield installations.
- Add regression coverage for firmware-provided device codes, board fallback, unknown devices, resolve payload metadata, and rpcd status exposure.

### Changed

- Keep unsupported or unrecognized hardware explicit by sending an empty `device_code` with source `unknown` instead of inferring a supported product from architecture, memory, or fuzzy model matching.

## [0.3.23-r1] - 2026-09-15

- Bump version for release.

## [0.3.22-r4] - 2026-09-13

### Changed

- Remove legacy shell helpers that no production path calls, including generic string transforms, the old status active/enabled helpers, unused failure/debug log wrappers, manual dnsmasq kill/clear helpers, and the pre-identity duplicate primary-MAC detector.
- Stop caching the unused shell-side `ss_debug` value while preserving the public UCI/rpcd `debug` option for compatibility.
- Remove the unused `/lib/functions/network.sh` import from the init script; interface reload triggers continue to use the procd API supplied by `rc.common`.

### Added

- Add a dead-code regression contract that prevents retired helpers and the unused network-functions import from being reintroduced while asserting their active replacement paths remain present.

## [0.3.22-r3] - 2026-09-13

### Added

- Add end-to-end shell state-machine coverage for full SafeShield refresh success, rollback failures, lock contention, and HTTP 426 upgrade-required preservation of the active blocklist.
- Add local-rule fast-apply coverage for cached-artifact fallback, duplicate fingerprints, lock timeout/termination, successful apply, and merge/restart/runtime/verification rollback paths.
- Add init lifecycle coverage for disabled startup, statistics runtime wiring, dnsmasq directive migration failures, active-blocklist restart ownership, and enabled/disabled shutdown states.
- Add artifact integrity coverage for retry recovery, partial checksum metadata, SHA-256 mismatch, missing `sha256sum`, and artifact size limits.
- Add refreshd scheduler coverage for failed-attempt retry anchoring, future/invalid timestamps, manual-refresh rescheduling, WAN waits, recent-success boot skips, and disabled runtime behavior.
- Add direct rpcd `runtime.uc` regression coverage and compile/behavior coverage for `status-store.uc`, including malformed state recovery and message mutations.

### Fixed

- Make refresh-lock regression coverage portable to macOS and other development hosts without a system `flock(1)` binary by using a test-only atomic lock shim while preserving the production `flock -n/-u` contract.
- Make the new lifecycle and refreshd regression helpers ShellCheck-clean by exporting mocks consumed by dynamically sourced production functions and narrowly annotating scheduler calls loaded from the generated test harness.

## [0.3.22-r2] - 2026-09-13

### Added

- Add regression coverage for authenticated OpenWrt `uclient-fetch` statistics POSTs, HTTP status propagation, and the no-header safety guard.
- Add statistics uploader state-machine coverage for corrupted pending metadata, stale/duplicate acknowledgements, periodic full reconciliation, and permanent HTTP 400 rejection.
- Expand artifact resolve payload assertions to cover device identity/registration metadata and invalid memory fallback.
- Expand rpcd ucode tests for statistics persistence/session metadata, config no-op behavior, dedicated options, runtime reconciliation failures, and oversized license keys.

## [0.3.22-r1] - 2026-09-13

- Bump version for release.

## [0.3.21-r5] - 2026-09-12

### Changed

- Reduce routine Hub statistics synchronization from every five minutes to every 30 minutes, cutting router TLS/JSON work and backend request volume by roughly six times while keeping the two-hour recovery window.
- Send a full retained statistics reconciliation approximately every 12 hours instead of every six hours; startup, generation changes, entitlement recovery, and upload-failure recovery still force the next eligible upload to be full.
- Include canonical client identity metadata in statistics payloads as `identities[]`, exposing DHCP client-id, DHCPv6 DUID, and MAC aliases already tracked by the local collector so the Hub can preserve one network client across private/randomized MAC changes.

## [0.3.21-r4] - 2026-09-12

### Added

- Track DHCP client identifiers from the dnsmasq lease file and DHCPv6 DUIDs from odhcpd so statistics history can survive private/randomized MAC changes.
- Add an odhcpd IPv6 identity helper that pairs DHCPv6 DUID/hostname metadata with kernel NDP MAC resolution.
- Add regression coverage for DHCP client-id MAC rotation, DHCPv6 DUID MAC rotation, conservative hostname fallback, and aggregated unresolved clients.

### Changed

- Reconcile a previously retained MAC identity into the currently observed MAC when a stable DHCP client-id or DHCPv6 DUID proves they are the same client.
- Use a conservative hostname fallback only when exactly one active MAC advertises a non-generic hostname and the retained candidate is no longer active.
- Serialize unresolved IP-only clients as a single `unknown` device while retaining their recent IP-specific buckets internally long enough for later DHCP/ARP/NDP reconciliation.
- Compact unresolved IP-only identities without a strong identifier into the local `unknown` bucket after six hours, bounding retained per-device state on networks with frequent IPv6 privacy-address rotation.
- Bump the internal statistics persistence schema from 5 to 6 to retain DHCP client-id and DHCPv6 DUID metadata across collector restarts and journal recovery.

## [0.3.21-r3] - 2026-09-12

### Changed

- Gate Hub statistics synchronization on the entitlement returned by `/api/v1/licenses/resolve`; eligible PRO and ULTIMATE licenses in ACTIVE or TRIAL status continue to upload while free and unlicensed devices keep statistics local only.
- Cache the non-secret cloud-upload entitlement in tmpfs so an explicitly ineligible device does not repeatedly request statistics credentials.
- Recheck an explicitly denied statistics entitlement at most once every 12 hours when a license key remains configured, allowing server-side license reactivation to recover without waiting for the normal artifact refresh cycle.
- Reset cached statistics entitlement, credentials, pending payloads, and upload progress immediately when `license_update` changes or clears the configured key so the next eligible synchronization starts with a full reconciliation.

### Fixed

- Stop statistics POST/re-authentication loops after the Hub returns `statistics: null`, including when a previously entitled license is rejected with HTTP 401.
- Clear stale statistics credentials, pending cloud payloads, and prior synchronization progress when upload entitlement is removed without affecting the local statistics collector or retained local data.
- Treat a backward wall-clock correction as immediately due for denied-entitlement revalidation so NTP adjustments cannot postpone cloud-upload recovery.

## [0.3.21-r2] - 2026-09-12

### Added

- Upload SafeShield DNS statistics to the Hub `/api/v1/statistics` endpoint with the device-scoped bearer credential issued by `/api/v1/licenses/resolve`.
- Add a separate statistics uploader process so Hub or WAN failures cannot block local DNS statistics collection.
- Add generation-scoped statistics schema v3 `snapshot_seq` ordering with durable sequence-range reservation on persistence-enabled devices.
- Add a compact two-hour upload projection for routine synchronization while retaining the full local 168-hour statistics dataset.

### Changed

- Upload statistics every five minutes, use a full retained snapshot at startup/recovery and approximately every six hours, and otherwise send only the recent two-hour window.
- Cache Hub statistics upload credentials only in tmpfs and refresh them through license resolve after an HTTP 401 response.
- Keep exact pending payloads across retry attempts so a lost HTTP acknowledgement can be safely resolved as a Hub `duplicate`.
- Keep upload credentials and pending synchronization state in tmpfs so bearer tokens and retry payloads are never written to flash.

### Fixed

- Force a full reconciliation after upload failures so data outside the routine two-hour window is recovered after connectivity returns.
- Reject a stale recent projection while the collector is atomically publishing a newer full snapshot, preventing a previous sequence from being promoted for upload.
- Recover statistics ordering by `snapshot_seq` within the same generation, including across backward NTP corrections, journal replay, collector restarts, and persistent reboot recovery.

## [0.3.21-r1] - 2026-09-09

- Bump version for release.

## [0.3.20-r4] - 2026-09-09

### Changed

- Keep `statistics_enabled` as the configured user preference when the dnsmasq SafeShield extension is unavailable; disable collection only for the current runtime so a later compatible firmware can restore it automatically.
- Expose `effective_enabled` separately from the configured Statistics toggle and report the source unavailable while the collector is not running.
- Propagate dnsmasq `untracked_blocked` metadata through collector state, JSON output, and the statistics RPC.

### Fixed

- Strictly validate dnsmasq `safeshield_stats` schema 1, required totals, client arrays, and non-negative cumulative counters before accepting a poll snapshot.
- Establish a fresh cumulative-counter baseline after Statistics or SafeShield has been disabled, preventing queries from the disabled period from being backfilled when collection is re-enabled.

## [0.3.20-r3] - 2026-09-09

### Changed

- Use the SafeShield namespace for dnsmasq integration: `safeshield-block=/domain/` and `dnsmasq.safeshield_stats`.
- Rename SafeShield-side dnsmasq capability helpers, migration paths, logs, documentation, and regression contracts to the SafeShield namespace.

### Fixed

- Keep DNS protection operational on an unpatched dnsmasq by falling back to standard `address=/domain/#` rules instead of installing an unsupported directive.
- Defensively disable and persist `statistics_enabled=0` when the SafeShield dnsmasq extension is unavailable, preventing statistics collector respawn/error loops.
- Reconcile installed `address=/domain/#` and `safeshield-block=/domain/` rules to the format supported by the running dnsmasq.

## [0.3.20-r2] - 2026-09-09

### Changed

- Replace per-query dnsmasq log ingestion with low-frequency polling of the SafeShield cumulative UBus statistics source.
- Emit SafeShield block rules with `safeshield-block=/domain/` so only SafeShield-owned rules increment the blocked counter.
- Preserve the existing statistics retention, per-device identity, journal persistence, and `generation_id` model while tracking dnsmasq `instance_id` counter epochs.
- Require dnsmasq 2.93 with the SafeShield block-accounting extension, matching the OpenWrt 25.12 baseline.

### Added

- Add `/usr/libexec/safeshield-stats-poll`, a one-shot ucode helper for `dnsmasq.safeshield_stats`.
- Expose statistics source availability, `instance_id`, transport scope, client capacity, tracked clients, untracked queries, and poll errors through the local statistics JSON/RPC.
- Persist the last dnsmasq cumulative counter baseline in collector state (and the persistent base snapshot where enabled) so collector restarts do not double-count an unchanged dnsmasq instance.

### Fixed

- Remove the high-frequency `logread -f`/AWK event path and managed `log-queries`/`log-async` configuration that could contribute to latency spikes on resource-constrained routers.
- Continue excluding loopback health-check traffic by subtracting loopback client counter deltas from global statistics.
- Migrate an already-installed legacy `address=/domain/#` SafeShield blocklist to the SafeShield directive during service startup.

## [0.3.20-r1] - 2026-09-08

- Bump version for release.

## [0.3.19-r4] - 2026-09-08

### Fixed

- Detect HTTP 426 responses from Hub artifact resolve and download requests and stop retrying immediately with `safeshield_upgrade_required`.
- Preserve the currently active blocklist without an unnecessary dnsmasq restore/restart when the Hub requires a newer SafeShield version.
- Keep the installed runtime version string in OpenWrt `0.3.19-rN` form so Hub minimum-version validation receives the same revision that the package reports.

## [0.3.19-r3] - 2026-09-07

### Added

- Resolve IPv6 DNS clients through the kernel NDP neighbor cache so privacy/temporary IPv6 addresses from the same link-layer client converge on one MAC-based statistics identity.
- Add regression coverage for IPv6 temporary-identity migration, shared-MAC neighbor merging, failed neighbor fallback, and the modular statistics runtime contract.

### Changed

- Split the monolithic statistics AWK collector into focused common, recovery, identity, aggregation, persistence, output, and lifecycle modules loaded together by `safeshield-statsd`.
- Keep unresolved IPv6 clients on the existing `ip:<address>` fallback until a valid neighbor `lladdr` becomes available, then migrate retained hourly buckets to the MAC identity.

## [0.3.19-r2] - 2026-09-06

### Added

- Add a persistent `generation_id` to statistics state, journal records, JSON output, and the public statistics RPC so one retained dataset can be identified across collector restarts.
- Document the distinction between dataset-scoped `started_at` and process-scoped `session_started_at`.
- Add regression coverage for stale journal recovery, internal loopback DNS queries, statistics generation/session identity, and temporary IPv6 device identities.

### Fixed

- Ignore committed journal transactions that are not newer than the loaded persistent base snapshot, preventing stale retained journal data from rolling statistics backward after interrupted compaction.
- Exclude loopback DNS traffic from both global and per-device statistics so SafeShield's own localhost health checks do not inflate query or blocked counters.

## [0.3.19-r1] - 2026-09-02

- Bump version for release.

## [0.3.18-r13] - 2026-09-02

### Changed

- Remove the `tests/run.sh` compatibility wrapper now that the shell regression suite is fully native ShellSpec.
- Run ShellSpec directly in GitHub Actions with `REQUIRE_UCODE=1 shellspec`, leaving a single test entry point for local and CI execution.
- Extend the tooling contract to require direct ShellSpec CI execution and prevent the legacy `tests/run.sh` wrapper from being reintroduced.

## [0.3.18-r12] - 2026-09-02

### Changed

- Replace the legacy ShellSpec adapter with native ShellSpec suites for the existing SafeShield shell regression coverage.
- Organize the converted suite into core, blocklist, runtime, statistics, ucode, and tooling specs so failures are reported by feature-oriented ShellSpec examples.
- Move reusable shell fixtures and integration scenarios under `spec/support/`, where they remain covered by the normal shfmt, ShellCheck, and `sh -n` lint pipeline.
- Keep `tests/run.sh` as the compatibility entry point while ShellSpec directly discovers only native `spec/*_spec.sh` files.
- Preserve the existing ucode test programs under `tests/ucode/` and invoke them from the native ShellSpec ucode example.

## [0.3.18-r11] - 2026-09-02

### Changed

- Adopt ShellSpec 0.28.1 as the shell test runner and use its `spec/*_spec.sh` discovery instead of maintaining a manual test list in `tests/run.sh`.
- Run the existing POSIX shell regression scripts as individual ShellSpec examples so their established assertions and OpenWrt-specific mocks remain intact during the migration.
- Pin ShellSpec 0.28.1 in GitHub Actions and keep the compatibility `tests/run.sh` entry point for local and CI usage.
- Exclude ShellSpec DSL spec files from general `shfmt` formatting while continuing to lint normal shell helpers and production scripts.
- Treat legacy test stdout as an expected success message and require empty stderr so ShellSpec does not emit unverified-output warnings.

## [0.3.18-r10] - 2026-09-02

### Fixed

- Clear stale Statistics persistence health, error and checkpoint metadata when persistent storage is disabled.
- Keep persistence health non-erroring in volatile mode and avoid scheduling persistent checkpoint or compaction work when no persistent paths are configured.
- Record the collector's effective snapshot interval in runtime statistics and expose it separately from the configured UCI interval so GL-MT300N-V2 reports its 300-second runtime interval.

## [0.3.18-r9] - 2026-09-02

### Changed
- Run Statistics on GL-MT300N-V2 in volatile tmpfs-only mode by disabling the persistent snapshot and journal paths while keeping runtime state and `statistics.json` snapshots available.
- Avoid creating or touching Statistics flash-persistence directories on GL-MT300N-V2; other device profiles continue using the existing journal-based persistence path unchanged.

### Fixed
- Prevent periodic Statistics persistence and journal I/O from contributing to latency spikes on resource-constrained GL-MT300N-V2 routers.

## [0.3.18-r8] - 2026-09-01

### Changed
- Merge already sorted normalized Hub artifact shards with `sort -m -u` instead of concatenating and fully sorting them again during blocklist refresh.
- Reuse the existing statistics totals pass to track each device's first and last retained hourly bucket, then serialize only that active range in `statistics.json`.

## [0.3.18-r7] - 2026-09-01

### Changed
- Filter the live statistics log stream in `logread` so only dnsmasq messages enter the FIFO and AWK collector.
- Replace refreshd's one-second polling sleep loop with a single interruptible sleep child that is cancelled immediately on TERM or INT.
- Stop blocklist test-domain sampling as soon as the requested limit is reached and skip redundant blocklist rule scans for domains already sampled from the installed blocklist.

## [0.3.18-r6] - 2026-09-01

### Changed
- Increase the dnsmasq asynchronous statistics log queue from 25 to 50 lines on GL-MT300N-V2 while keeping the existing 25-line queue on other device profiles.
- Use a 300-second hot statistics snapshot interval on GL-MT300N-V2 when the configured interval is the standard 60-second default, while preserving non-default configured intervals.
- Cache resolved DNS client IP-to-device identities for up to 60 seconds, bounded by the DHCP/ARP lease refresh interval.
- Skip redundant tmpfs state and JSON serialization when no statistics state changed, while still forcing pending persistent journal data to flush on graceful collector shutdown and serializing persistence health changes when a flush updates them.

### Fixed
- Reduce per-query AWK identity processing and periodic snapshot CPU bursts that can cause DNS latency on resource-constrained routers such as GL-MT300N-V2.

## [0.3.18-r5] - 2026-09-01

### Added

- Add journal-based persistence for SafeShield statistics to reduce flash write amplification on low-end devices.
- Persist completed hourly global and per-device statistics by appending compact journal transactions instead of rewriting the full retained statistics state every hour.
- Add transactional `begin`/`commit` markers so incomplete journal writes caused by power loss are ignored during recovery.
- Add periodic journal compaction that merges retained journal data into the persistent base snapshot.
- Preserve statistics journal data across sysupgrade.
- Expose journal persistence mode and compaction metadata through the statistics API.

### Changed

- Keep the 60-second statistics snapshot in tmpfs while limiting routine flash writes to hourly journal updates.
- Change full persistent state rewrites from hourly checkpoints to periodic compaction, with a default compaction interval of 7 days.
- Restore statistics at startup by loading the persistent base snapshot and replaying committed journal transactions.
- Persist IP-to-MAC device identity reconciliation through journal records without losing cumulative or hourly statistics.
- Use absolute hourly bucket updates in the journal so replay remains idempotent after restarts or interrupted compaction.

### Fixed

- Avoid the periodic full-state flash writes that can cause noticeable latency on resource-constrained devices such as the GL-MT300N-V2.
- Ignore incomplete journal transactions after an unexpected shutdown or power loss.
- Keep in-memory statistics operational when a journal persistence write fails, while reporting persistence health through the statistics API.

## [0.3.18-r4] - 2026-09-01

### Fixed

- Reconcile temporary `ip:<address>` statistics identities with MAC-based device identities once the client MAC address becomes available.
- Merge existing cumulative and hourly query/block counters into the resolved MAC identity without losing historical statistics.
- Remove stale IP-based device records and hourly buckets after a successful identity migration.
- Fall back to `/proc/net/arp` for client MAC resolution when DHCP lease data is unavailable.
- Make device hourly bucket migration safe across different AWK implementations by avoiding in-place associative array mutation during iteration.

## [0.3.18-r3] - 2026-09-01

### Fixed

- Preserve per-device hourly statistics through the public statistics RPC.
- Prefer the newest valid tmpfs or persistent statistics state when the collector restarts.
- Reject persistent statistics state whose stored totals do not match its retained hourly buckets.
- Expose persistent checkpoint health and back off retries after flash write failures.

## [0.3.18-r2] - 2026-09-01

### Added

- Persist retained global and per-device hourly SafeShield statistics across router reboots.
- Expose per-device hourly buckets through the statistics API for accurate local history and future cloud ingestion.

### Changed

- Keep 60-second hot snapshots in tmpfs while checkpointing aggregate statistics to flash at most once per hour and on graceful collector shutdown.
- Restore persistent statistics after reboot, retain up to 168 hourly buckets, and migrate version 1 per-device cumulative counters without dropping totals.
- Keep the persistent statistics checkpoint across sysupgrade.

## [0.3.18-r1] - 2026-09-01

### Added

- Include the installed SafeShield package version in Hub artifact resolve requests for operational diagnostics and compatibility analysis.

## [0.3.17-r1] - 2026-08-30

- Bump version for release.

## [0.3.16-r4] - 2026-08-30

### Fixed

- Fix the shared ucode `trim()` helper so leading and trailing whitespace are both removed in a single call.
- Keep ucode unit-test mocks aligned with the production trimming behavior and add explicit leading/trailing regression cases.

## [0.3.16-r3] - 2026-08-30

### Added

- Add host-side ucode unit tests for core helpers and rpcd config, license, refresh, rules, statistics, and status behavior.
- Compile-check all production rpcd ucode modules before running ucode unit tests.
- Run ucode tests in GitHub Actions using the ucode revision shipped by the OpenWrt 25.12 package feed.

## [0.3.16-r2] - 2026-08-30

### Added

- Add host-side regression tests for shared utility helpers, configuration validation, identity persistence/profile mapping, status state transitions, and the rpcd/ACL public contract.

### Changed

- Run the new regression tests from the existing `tests/run.sh` entrypoint.

## [0.3.16-r1] - 2026-08-30

### Added

- Support multiple Hub artifact sources through `artifact.sources[]` while preserving the legacy single `artifact.download_url` response.
- Support independent `block` and `allow` actions for remote artifact sources so separately distributed datasets can be combined only at router runtime.
- Download and SHA-256 verify each remote source independently and cache normalized source files for local-rule reapply operations.
- Expose resolved block/allow source counts through the SafeShield status API.

### Changed

- Keep downloaded Hub sources separate in tmpfs and merge them only when generating the active dnsmasq blocklist.
- Define override precedence as local allow > local block > Hub allow > Hub block when multiple source actions overlap.

## [0.3.15-r2] - 2026-08-30

### Changed

- Add an installed third-party data notice for HaGeZi-derived DNS blocklist artifacts.
- Install a GPL-3.0 license copy alongside the notice so the applicable terms are available on-device.

## [0.3.15-r1] - 2026-08-30

- Bump version for release.

## [0.3.14-r8] - 2026-08-30

### Fixed

- Reconcile statistics enable/disable changes without restarting the SafeShield refresh daemon.
- Add or remove only the statistics procd instance while keeping the refresh scheduler running.
- Restart dnsmasq only when the managed statistics logging configuration changes.
- Avoid transient `stage: stopped` states caused by full SafeShield restarts from statistics-only configuration updates.

## [0.3.14-r7] - 2026-08-29

### Fixed

- Initialize all per-device AWK array elements when a device record is created.
- Avoid sparse associative-array values reaching serialization helpers, preventing gawk double-free crashes on affected versions.
- Add regression coverage for complete state serialization of unidentified IP-based devices.

## [0.3.14-r6] - 2026-08-29

### Changed

- Add a shared shell lint entrypoint for shfmt, ShellCheck, and shell syntax validation.
- Run the same shell lint script from local pre-commit hooks and GitHub Actions.
- Fail local commits early when shell formatting does not satisfy `shfmt -d -ci`.

## [0.3.14-r5] - 2026-08-29

### Fixed

- Align statistics tests with the repository shfmt formatting rules.

## [0.3.14-r4] - 2026-08-29

- Add per-device DNS query and block counters to local SafeShield statistics.
- Use `log-queries=extra` so dnsmasq block responses can be attributed to the requesting client.
- Resolve DHCP clients from the configured dnsmasq lease file and use MAC addresses as stable local device identities.
- Fall back to temporary IP identities for clients without a DHCP lease and migrate them when a lease becomes available.
- Cap retained device identities at 128 while keeping raw queried domains out of statistics state.

## [0.3.14-r3] - 2026-08-29

- Fix `shfmt -ci` formatting for the statistics collector regression test environment assignments.

## [0.3.14-r2] - 2026-08-29

- Fix orphaned `logread` / `awk` statistics collector processes after procd restarts or service termination.
- Track collector child PIDs explicitly and terminate them on HUP, INT, TERM, and normal exit.
- Use a per-instance FIFO instead of an unmanaged shell pipeline so the parent process owns the full collector lifecycle.
- Add a tmpfs collector lock to prevent concurrent statistics writers and recover stale locks after crashes.
- Add regression coverage that verifies collector children and runtime files are cleaned up after termination.

## [0.3.14-r1] - 2026-08-29

- Add lightweight local DNS statistics collection using dnsmasq query logs.
- Keep statistics in tmpfs only to avoid persistent flash writes.
- Add hourly query/block counters with configurable snapshots and up to 168 hours of retention.
- Add the `safeshield.statistics` ubus RPC endpoint for local dashboards.
- Enable asynchronous dnsmasq query logging only while statistics collection is enabled.

## [0.3.13-r1] - 2026-08-28

- Bump version for release.

## [0.3.12-r2] - 2026-08-28

- Fix ShellCheck warnings in the dnsmasq compatibility helper and regression test scripts.
- Encapsulate the dnsmasq compatibility failure code behind a helper instead of exposing a cross-file global variable.
- Use an explicit empty `CDPATH` assignment in test path resolution and remove an unused test variable.

## [0.3.12-r1] - 2026-08-28

- Require dnsmasq 2.80 or later before SafeShield starts, refreshes, or reapplies local rules.
- Expose the detected and minimum dnsmasq versions through runtime status and health checks.
- Accept optimized Hub artifacts using `address=/domain/#` and emit the same single-line dual-stack rule in the active dnsmasq blocklist.
- Keep blocklist verification compatible with both the optimized `/#` rule and legacy `0.0.0.0` / `::` rules.

## [0.3.11-r35] - 2026-08-27

- Declare `coreutils-cksum` as a runtime dependency because SafeShield uses `cksum` to fingerprint normalized local allow/block rules.
- Ensure the existing identity hash fallback also has a guaranteed `cksum` implementation on minimal OpenWrt images such as GL-MT300N-V2.
- Fix false dnsmasq restart/runtime failures on OpenWrt targets where `pgrep -x dnsmasq` does not match the running dnsmasq process.
- Use the base-system `pidof` applet for dnsmasq process detection, while retaining the existing DNS query readiness check.
- Declare direct runtime dependencies for the `uci` CLI and `jsonfilter` used by SafeShield shell helpers.
- Use BusyBox-aware fallback dependencies for `sha256sum`, `awk`, `grep`, and `sed` so minimal OpenWrt images install GNU implementations only when the corresponding BusyBox applet is disabled.
- Remove the invalid `cksum` fallback from identity SHA-256 generation; CRC output is not a SHA-256 digest and cannot satisfy the identity format.
- Fail closed when artifact SHA-256 verification cannot run instead of silently accepting an unverified artifact.

## [0.3.10-r34] - 2026-08-26

- Refactor the 1,300+ line rpcd ucode implementation into focused modules under `/usr/share/rpcd/ucode/safeshield/`.
- Keep all SafeShield rpcd ucode sources together under the rpcd plugin tree instead of installing private modules under `/usr/share/ucode`.
- Keep `/usr/share/rpcd/ucode/safeshield.uc` as a small ubus registration entrypoint while preserving existing RPC names, arguments, and response schemas.
- Separate shared UCI/helpers, runtime lifecycle, status, configuration, local rules, refresh, and license logic to reduce coupling.
- Treat an absent `license_key` UCI option as the canonical unlicensed state and clear it explicitly with `uci.delete()` instead of relying on the ucode UCI empty-string deletion side effect.
- Add `safeshield.license_get` for explicit authenticated retrieval of the configured raw license key while keeping normal status/config responses masked.
- Keep license removal on `safeshield.license_update` with an empty key and document the refresh/unlicensed transition.

## [0.3.9-r29] - 2026-08-19

- Apply local allow/block rule mutations from the retained normalized Hub artifact instead of re-resolving and re-downloading the full artifact.
- Serialize local rule application with the full refresh lock and wait for an in-flight refresh before merging the newest local files.
- Fingerprint normalized local rules so rapid duplicate apply workers collapse without repeated dnsmasq restarts.
- Fall back to a full refresh only when the cached Hub artifact is unavailable.
- Expose `last_local_apply` and `last_local_apply_failure` timestamps while keeping the normal Hub refresh schedule unchanged.
