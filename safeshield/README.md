# SafeShield

[![Lint](https://github.com/Junatum/safeshield/actions/workflows/lint-shell.yml/badge.svg)](https://github.com/Junatum/safeshield/actions/workflows/lint-shell.yml)
![OpenWrt](https://img.shields.io/badge/OpenWrt-Compatible-blue)
![License](https://img.shields.io/github/license/Junatum/safeshield?label=License)

SafeShield is a lightweight DNS protection engine for OpenWrt and the core network-protection component used by **SmartSafeHub**. It blocks advertising, tracking, and phishing domains at the router through dnsmasq, so connected devices can benefit without installing a separate client application.

For most users, the recommended way to run SafeShield is through the **SmartSafeHub firmware and Web UI**. The standalone `luci-app-safeshield` package remains available for users who want a dedicated SafeShield-only LuCI interface, but current product UI development is focused on [`luci-app-smartsafehub`](https://github.com/Junatum/luci-app-smartsafehub).

- SmartSafeHub: https://www.smartsafehub.com/
- Firmware downloads: https://www.smartsafehub.com/firmware/
- Installation guide: https://www.smartsafehub.com/docs/installation/

## Features

- DNS-based blocking of ads, tracking, and phishing domains
- Fully compatible with **dnsmasq**
- Lightweight design suitable for **low-resource OpenWrt devices**
- Integrated management through the actively developed **SmartSafeHub Web UI**
- Optional standalone management through `luci-app-safeshield`
- Automatic blocklist download and refresh
- Multiple Hub artifact sources with independent block/allow actions and checksum verification
- Support for **custom allowlist and blocklist**
- Modular shell-based architecture for easy customization and maintenance
- Lean runtime surface with regression coverage guarding retired/unused shell helpers from returning

## Package versions

The badges below show the versions currently published to each repository channel.

| Package | Stable | Beta |
| --- | --- | --- |
| SafeShield | [![Stable SafeShield](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frepo.smartsafehub.com%2Fstable%2Fversions.json&query=%24.packages%5B%22safeshield%22%5D&label=&color=brightgreen&cacheSeconds=300)](https://repo.smartsafehub.com/stable/versions.json) | [![Beta SafeShield](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frepo.smartsafehub.com%2Fbeta%2Fversions.json&query=%24.packages%5B%22safeshield%22%5D&label=&color=orange&cacheSeconds=300)](https://repo.smartsafehub.com/beta/versions.json) |
| SmartSafeHub UI | [![Stable SmartSafeHub UI](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frepo.smartsafehub.com%2Fstable%2Fversions.json&query=%24.packages%5B%22luci-app-smartsafehub%22%5D&label=&color=brightgreen&cacheSeconds=300)](https://repo.smartsafehub.com/stable/versions.json) | [![Beta SmartSafeHub UI](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frepo.smartsafehub.com%2Fbeta%2Fversions.json&query=%24.packages%5B%22luci-app-smartsafehub%22%5D&label=&color=orange&cacheSeconds=300)](https://repo.smartsafehub.com/beta/versions.json) |
| Standalone SafeShield UI | [![Stable LuCI SafeShield](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frepo.smartsafehub.com%2Fstable%2Fversions.json&query=%24.packages%5B%22luci-app-safeshield%22%5D&label=&color=brightgreen&cacheSeconds=300)](https://repo.smartsafehub.com/stable/versions.json) | [![Beta LuCI SafeShield](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frepo.smartsafehub.com%2Fbeta%2Fversions.json&query=%24.packages%5B%22luci-app-safeshield%22%5D&label=&color=orange&cacheSeconds=300)](https://repo.smartsafehub.com/beta/versions.json) |

`luci-app-smartsafehub` is the primary user-facing UI and the focus of current product development. `luci-app-safeshield` is retained as an optional standalone SafeShield interface and is not the primary target for new product UI work.

## How it works

SafeShield provides DNS-level protection by automatically applying the
appropriate **dnsmasq**-compatible blocklist for each device.

It helps block ads, trackers, and phishing domains with scheduled updates
and optional local allow/block overrides.

### Hub artifact source contract

SafeShield accepts both the legacy single-artifact response and the preferred
multi-source response from the SmartSafeHub Hub API. Existing deployments can
continue returning `artifact.download_url`.

For multiple independently licensed or managed datasets, the Hub should return
`artifact.sources`:

```json
{
  "artifact": {
    "tier": "pro",
    "version": "20260830T120000Z",
    "sources": [
      {
        "id": "hagezi-pro",
        "action": "block",
        "download_url": "https://example.invalid/hagezi-pro.txt",
        "sha256": "..."
      },
      {
        "id": "smartsafehub-pro",
        "action": "block",
        "download_url": "https://example.invalid/smartsafehub-pro.txt",
        "sha256": "..."
      },
      {
        "id": "smartsafehub-allow",
        "action": "allow",
        "download_url": "https://example.invalid/smartsafehub-allow.txt",
        "sha256": "..."
      }
    ]
  }
}
```

Each source is downloaded, checksum-verified, normalized, and retained as an
independent runtime cache file. SafeShield merges all block and allow sources
only on the router when generating the active dnsmasq configuration. This keeps
the Hub artifacts separate while preserving override precedence as `local allow`
> `local block` > `Hub allow` > `Hub block`.

SafeShield also sends a canonical `device.device_code` with Hub resolve requests.
SmartSafeHub firmware is authoritative when `/usr/share/smartsafehub/firmware.json`
contains a valid `device_code`. Standalone SafeShield installations fall back only
to exact OpenWrt board-name mappings for officially recognized hardware; unknown
hardware sends an empty `device_code` instead of guessing from vendor, model,
architecture, or memory. `device.device_code_source` reports
`smartsafehub_firmware`, `board`, or `unknown` for diagnostics. The same values
are exposed through `ubus call safeshield status`.

## System Requirements

SafeShield requires the following environment:

- **OpenWrt 25.12 or later**
- **dnsmasq 2.93 or later** (the SafeShield dnsmasq extension enables cumulative statistics; stock dnsmasq falls back to standard block rules with statistics disabled)
- At least **16 MB free flash storage**
- Internet access for downloading blocklists

## Installation

### Recommended: SmartSafeHub firmware

For supported hardware, the recommended installation path is a complete **SmartSafeHub OpenWrt firmware image**. This gives users the integrated SmartSafeHub Web UI together with SafeShield and the firmware-specific integration expected by the product.

Download firmware without signing in:

https://www.smartsafehub.com/firmware/

The firmware page currently provides releases for supported devices including:

- **ipTIME AX3000SM**
- **GL.iNet GL-MT300N-V2**
- **Xiaomi Router AX3000T (International version)**

Choose the image type that matches the installation state:

- **Factory** — for an initial installation from vendor firmware or a device-specific recovery flow.
- **Sysupgrade** — for updating a router that already runs SmartSafeHub/OpenWrt.

Always verify the exact hardware model and follow the device-specific installation guide before flashing. Installing an image for a different model can prevent the router from booting.

See the installation guide for the current procedure:

https://www.smartsafehub.com/docs/installation/

### Advanced: install SafeShield packages on OpenWrt

SafeShield is also published through the SmartSafeHub OpenWrt package repository for advanced users, development environments, and compatible custom OpenWrt installations. OpenWrt 25.12 uses the `apk` package manager.

Add the SmartSafeHub signing key and Stable repository, replacing `<architecture>` with the target package architecture such as `aarch64_cortex-a53`, `mipsel_24kc`, or `x86_64`:

```sh
mkdir -p /etc/apk/keys /etc/apk/repositories.d

uclient-fetch -O /etc/apk/keys/smartsafehub.pem \
  https://repo.smartsafehub.com/stable/packages/<architecture>/smartsafehub/smartsafehub.pem

printf '%s\n' \
  'https://repo.smartsafehub.com/stable/packages/<architecture>/smartsafehub/packages.adb' \
  > /etc/apk/repositories.d/smartsafehub.list

apk update
```

Install SafeShield with the primary SmartSafeHub UI:

```sh
apk add safeshield luci-app-smartsafehub
```

If you specifically want the older standalone SafeShield-only LuCI interface, it remains available as an optional package:

```sh
apk add luci-app-safeshield
```

The standalone UI is not the primary target for new product UI development. New dashboard, device-management, firmware-update, and broader SmartSafeHub features are developed in `luci-app-smartsafehub`.

After installation, restart the relevant services if they are not already restarted by the package lifecycle:

```sh
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
/etc/init.d/safeshield restart
```

Verify SafeShield:

```sh
ubus call safeshield status
/etc/init.d/safeshield status
logread | grep -i safeshield
```

## Build from source

SafeShield is built as an OpenWrt package. Build it inside an OpenWrt buildroot or SDK that matches your target device and OpenWrt version.

### Build with OpenWrt buildroot

Clone OpenWrt and prepare feeds:

```sh
git clone -b production https://github.com/Junatum/openwrt.git
cd openwrt

./scripts/feeds update -a
./scripts/feeds install -a
```

Add SafeShield under the OpenWrt `package/` directory:

```sh
git clone https://github.com/Junatum/safeshield package/safeshield
```

If you also want the current SmartSafeHub product UI, add
`luci-app-smartsafehub`:

```sh
git clone https://github.com/Junatum/luci-app-smartsafehub package/luci-app-smartsafehub
```

The standalone `luci-app-safeshield` repository is still available, but it is not the primary target for new UI development. Clone it only when you intentionally need the dedicated SafeShield-only interface.

Select your target device:

```sh
make menuconfig
```

For example, for MediaTek Filogic devices such as ipTIME AX3000SM:

```text
Target System  ---> MediaTek Ralink ARM
Subtarget      ---> Filogic 8x0
Target Profile ---> your device profile
```

Enable SafeShield as a module:

```sh
cat >> .config <<'EOF'
CONFIG_PACKAGE_safeshield=m
CONFIG_PACKAGE_luci-app-smartsafehub=m
EOF

make defconfig
```

Build the packages:

```sh
make package/safeshield/clean V=s
make package/safeshield/compile V=s

make package/luci-app-smartsafehub/clean V=s
make package/luci-app-smartsafehub/compile V=s
```

Find the generated packages:

```sh
find bin -type f \( \
  -name 'safeshield*.apk' \
  -o -name 'luci-app-smartsafehub*.apk' \
\) -print
```

Depending on the OpenWrt version and package location, the output can appear
under one of these paths:

```text
bin/targets/<target>/<subtarget>/packages/
bin/packages/<architecture>/<feed-name>/
```

For example, a MediaTek Filogic `apk` build may generate packages under:

```text
bin/targets/mediatek/filogic/packages/
```

### Build with OpenWrt SDK

You can also build SafeShield with the OpenWrt SDK for your target. This is
faster when you only need package artifacts.

```sh
tar xf openwrt-sdk-*.tar.*
cd openwrt-sdk-*

./scripts/feeds update -a
./scripts/feeds install -a

git clone https://github.com/Junatum/safeshield package/safeshield
git clone https://github.com/Junatum/luci-app-smartsafehub package/luci-app-smartsafehub

cat >> .config <<'EOF'
CONFIG_PACKAGE_safeshield=m
CONFIG_PACKAGE_luci-app-smartsafehub=m
EOF

make defconfig

make package/safeshield/compile V=s
make package/luci-app-smartsafehub/compile V=s
```

### Install local build artifacts

For OpenWrt `apk` based builds, copy the generated artifacts to the
device:

```sh
find bin -type f \( -name 'safeshield-*.apk' -o -name 'luci-app-smartsafehub-*.apk' \) -print

scp path/to/safeshield-*.apk root@192.168.1.1:/tmp/
scp path/to/luci-app-smartsafehub-*.apk root@192.168.1.1:/tmp/
```

Install them on the device:

```sh
ssh root@192.168.1.1

apk add --allow-untrusted /tmp/safeshield-*.apk
apk add --allow-untrusted /tmp/luci-app-smartsafehub-*.apk

/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
/etc/init.d/safeshield restart
```

Verify the installation:

```sh
ubus call safeshield status
/etc/init.d/safeshield status
logread | grep -i safeshield
```

## Development linting

SafeShield uses the same shell lint entrypoint locally and in GitHub Actions:

```sh
sh scripts/lint.sh
```

The lint script runs `shfmt -d -ci`, ShellCheck, and `sh -n` against tracked shell files. Install `shfmt` and `shellcheck` on the development machine before running it.
ShellSpec support helpers are linted by the same command; mocks consumed by dynamically sourced production functions are exported explicitly so the test harness remains ShellCheck-clean without changing runtime behavior.

Run the regression suite separately when changing runtime, statistics, HTTP transport, or rpcd behavior:

```sh
REQUIRE_UCODE=1 shellspec
```

The suite includes full refresh/local-rule rollback state machines, refresh lock contention, init lifecycle transitions, artifact retry/size/SHA-256 integrity checks, refreshd scheduling, OpenWrt `uclient-fetch` authenticated POST handling, statistics uploader recovery/state transitions, artifact resolve identity payloads, and direct rpcd runtime/status-store validation paths.
The refresh-lock regression uses a test-only portable lock shim, so the suite does not require a host `flock(1)` binary on macOS; production SafeShield continues to use OpenWrt's `flock`.

To enable the repository pre-commit hook, install `pre-commit` and register the hook once:

```sh
pre-commit install
```

After that, `git commit` runs the shell lint automatically. You can also check the whole repository manually:

```sh
pre-commit run --all-files
```

## Internal rpcd ucode layout

SafeShield keeps the rpcd registration entrypoint intentionally small and loads feature modules from `/usr/share/rpcd/ucode/safeshield/`:

```text
/usr/share/rpcd/ucode/safeshield.uc
/usr/share/rpcd/ucode/safeshield/
├── core.uc
├── runtime.uc
├── status.uc
├── config.uc
├── refresh.uc
├── rules.uc
├── license.uc
└── statistics.uc
```

The entrypoint prepends `/usr/share/rpcd/ucode/safeshield/*.uc` to ucode's `REQUIRE_SEARCH_PATH`, so the private RPC modules stay colocated with the rpcd plugin instead of using the global `/usr/share/ucode` tree.

The public ubus contract remains exposed through the single `safeshield` object; the module split is an internal implementation detail.

## SafeShield ubus API

The `safeshield` package owns the public management API used by LuCI and
SmartSafeHub clients. The API keeps UCI mutations, service lifecycle,
refresh scheduling and local rule files behind one ubus object.

Available methods:

```text
safeshield.status
safeshield.config
safeshield.statistics
safeshield.config_update
safeshield.set_enabled
safeshield.refresh
safeshield.rules_list
safeshield.rule_add
safeshield.rule_delete
safeshield.license_get
safeshield.license_update
```

Read the current public configuration:

```sh
ubus call safeshield config
```

Read lightweight local DNS statistics:

```sh
ubus call safeshield statistics
/etc/init.d/safeshield statistics
```

Statistics are collected from dnsmasq cumulative SafeShield UBus counters. Raw queried domains
are never written to the statistics state. Loopback (`127.0.0.0/8` and `::1`)
queries are excluded so SafeShield's own DNS health checks do not inflate user
query or blocked counters. In addition to global hourly query/block counters,
SafeShield keeps per-device totals and per-device hourly buckets locally. DHCP
clients are identified by MAC address using the dnsmasq lease file, with the
current IP and hostname included for the local UI. The collector also retains a
non-MAC-derived DHCP client-id when one is available. IPv4 clients can be
resolved through the kernel ARP table, while IPv6 clients combine the kernel NDP
neighbor cache (`ip -6 neigh show`) with odhcpd `ipv6leases` DUID metadata. A
stable DHCP client-id or DHCPv6 DUID therefore moves retained history from an
older private/randomized MAC to the currently observed MAC instead of exposing
both MACs as separate devices. Identified clients include these stable identifiers
in the Hub statistics payload as `identities[]` entries (`dhcp_client_id`,
`dhcpv6_duid`, and `mac`) so the backend can preserve one canonical network
client across later MAC rotations.

For older retained data that predates those strong identifiers, SafeShield uses
a conservative hostname fallback only when exactly one active MAC advertises a
non-generic hostname and a matching historical MAC is no longer active. Generic
names such as `iPhone`, `Android`, `phone`, or `laptop` are never merged by
hostname alone. Unresolved IP-only identities remain separate internally for a
short reconciliation window, but the public statistics JSON serializes them as
one `unknown` device so IPv6 privacy addresses do not create a device record per
address. IP-only entries with no stable DHCP identity are compacted into that
local unknown bucket after six hours. Device statistics remain capped at 128
active retained identities to bound memory use on low-end routers.

Each retained statistics dataset has a stable `generation_id`. `started_at` is
the creation time of that retained dataset and is restored together with the
generation when the collector restarts. `session_started_at` is the start time
of the current collector process and therefore changes on every collector
restart. `snapshot_seq` is monotonically increasing within the generation and
is the ordering/idempotency key for Hub ingestion; wall-clock `updated_at` is
kept only as event metadata. Persistence-enabled devices reserve sequence
ranges ahead in `/etc/safeshield/statistics-sequence.tsv`, so a reboot can skip
unconsumed values instead of reusing a sequence already observed by Hub. This
distinction lets cloud ingestion reject duplicate or out-of-order snapshots
without treating a process restart as a new dataset.

When statistics are enabled, a separate uploader can synchronize the aggregate
statistics with the SmartSafeHub Hub at `/api/v1/statistics`. Cloud upload is an
entitlement-controlled feature: the Hub currently grants it to eligible PRO and
ULTIMATE licenses in ACTIVE or TRIAL status and returns `statistics: null` for
free, unlicensed, expired, or revoked devices. SafeShield treats that Hub response as the
authoritative entitlement, disables network upload when it is absent, and keeps
collecting local statistics normally. A device with no configured license key is
blocked locally without making a statistics credential request.

For an entitled device, the uploader gets a device-scoped bearer credential from
the existing `/api/v1/licenses/resolve` response and keeps that credential only
under `/tmp/safeshield/statistics/`; it is never written to flash or included in
status output. Routine uploads run every 30 minutes and contain a consistent
two-hour projection of the local hourly data. A full retained snapshot is sent
on initial synchronization, after a failed upload has recovered, and periodically
(approximately every 12 hours) to reconcile any missed window.

The uploader preserves the exact pending JSON across network retries. If the Hub
committed a request but the HTTP acknowledgement was lost, retrying the same
`generation_id` and `snapshot_seq` is therefore idempotent. An HTTP 401 clears
the cached credential and resolves the license again. If the refreshed response
no longer grants statistics upload, SafeShield discards the cloud pending payload
and stops statistics POST requests. While a license key remains configured, a
denied entitlement is rechecked at most once every 12 hours so a server-side
reactivation can recover without waiting for the normal artifact refresh cycle.
Changing or clearing the key through `license_update` immediately clears cached
entitlement, credentials, pending payloads, and upload progress; the next granted
entitlement therefore resumes with a full reconciliation. Local collection is
independent of upload entitlement and upload success, so a free license, WAN
outage, or Hub outage never interrupts on-router statistics.

The collector implementation is split into focused AWK modules under
`/usr/lib/safeshield/statistics/` for common helpers, recovery, client identity,
aggregation, persistence, output, and the collector lifecycle. `safeshield-statsd`
loads the modules together as one AWK program, preserving the single collector
process used on resource-constrained routers.

Hot statistics live under `/tmp/safeshield/statistics/` and are retained for up
to 168 hourly buckets. Supported profiles additionally persist aggregate state
with a compact base snapshot plus hourly journal, while constrained profiles
may stay tmpfs-only. The collector no longer follows dnsmasq query logs. It
polls dnsmasq's cumulative SafeShield UBus counters at the effective snapshot
interval and calculates deltas in RAM. `instance_id` identifies the current
dnsmasq counter epoch so a dnsmasq restart can be distinguished from a normal
counter increment.

The default statistics settings are:

```text
statistics_enabled=1
statistics_snapshot_interval_s=60
statistics_retention_hours=168
```

When statistics are enabled, SafeShield calls `ubus call dnsmasq
safeshield_stats` through a small ucode poll helper. The helper accepts only
schema version 1 snapshots with a valid `instance_id`, cumulative totals, and
client array; malformed or incompatible replies are treated as poll failures
instead of silently becoming zero counters. No `log-queries` or `log-async`
setting is required. Existing pre-0.3.20-r2 statistics logging configuration is
removed once during upgrade. SafeShield persists aggregate counters only; raw
DNS query names are never collected.

`statistics_enabled` is the configured user preference. Runtime availability is
reported separately through `effective_enabled` and `collector_running`. If the
SafeShield dnsmasq extension is unavailable, SafeShield keeps the configured
preference intact, stops only the statistics runtime, and automatically resumes
collection after a compatible dnsmasq becomes available. Disabling Statistics
or SafeShield creates a rebaseline marker so the first snapshot after re-enable
is used only as a new cumulative-counter baseline; traffic from the disabled
period is not backfilled.

When the SafeShield dnsmasq extension is available, SafeShield emits block rules
as `safeshield-block=/domain/`. Only these SafeShield-owned rules increment the
dnsmasq blocked counter. If the extension is unavailable, SafeShield defensively
uses standard `address=/domain/#` rules so DNS protection remains available
without installing an unsupported directive. The statistics source also exposes
dnsmasq's `instance_id`, `transport_scope`, client-table capacity,
tracked-client count, `untracked_queries`, and `untracked_blocked`. The OpenWrt 25.12 dnsmasq integration reports `transport_scope=udp+tcp`, so both UDP and TCP DNS requests are included in the cumulative SafeShield counters.

Update writable configuration values. `enabled` and `license_key` are
intentionally excluded and have dedicated methods:

```sh
ubus call safeshield config_update '{
  "values": {
    "refresh_interval_s": 28800,
    "refresh_on_boot": true,
    "require_wan": true,
    "apply_local_overrides": true,
    "statistics_enabled": true,
    "statistics_snapshot_interval_s": 60,
    "statistics_retention_hours": 168
  }
}'
```

Enable or disable SafeShield. This method commits the desired UCI value and
requests the full SafeShield enable/disable lifecycle. Runtime convergence is
asynchronous under procd, so a successful response reports the accepted target
state instead of returning a potentially stale status snapshot:

```sh
ubus call safeshield set_enabled '{"enabled":true}'
```

A successful response has this shape:

```json
{
  "ok": true,
  "changed": true,
  "accepted": true,
  "target_enabled": true,
  "reconciled": false
}
```

Clients should poll `safeshield.status` until runtime state converges. For an
enable request, wait for `enabled=true`, `active=true` and
`runtime.refreshd_running=true`. For a disable request, wait for
`enabled=false`, `active=false` and `runtime.refreshd_running=false`.

Request an immediate refresh:

```sh
ubus call safeshield refresh
```

List local allow/block overrides:

```sh
ubus call safeshield rules_list
ubus call safeshield rules_list '{"action":"allow"}'
ubus call safeshield rules_list '{"action":"block"}'
```

Add or delete a local rule. Rule changes request an asynchronous refresh by
default so the active dnsmasq blocklist is rebuilt. For bulk edits, pass
`"refresh":false` on intermediate mutations and invoke `safeshield.refresh`
after the last mutation.

```sh
ubus call safeshield rule_add '{
  "action": "block",
  "domain": "example.com"
}'

ubus call safeshield rule_delete '{
  "action": "block",
  "domain": "example.com"
}'
```

### Local rule fast apply

`rule_add` and `rule_delete` keep the public SafeShield API unchanged, but their automatic apply path no longer performs a full Hub artifact refresh. SafeShield retains the normalized Hub domains in `/tmp/safeshield/api.block.txt`, rebuilds only the local allow/block inputs, merges them atomically, restarts dnsmasq, and verifies runtime DNS. The local apply worker shares the normal refresh lock, so a rule edit made during a full refresh waits for that refresh and then reapplies the newest local state. If the cached Hub artifact is missing, SafeShield falls back to one normal full refresh.

Read the raw license key only when an authenticated management client explicitly
requests it. Normal `status`, `config` and `license_update` responses continue to
return only masked license metadata.

```sh
ubus call safeshield license_get
```

Update or clear the license key. Passing an empty string removes the configured
UCI option and immediately requests a SafeShield refresh so the device is resolved
as unlicensed/free again. SafeShield intentionally treats an absent `license_key`
option as the canonical unlicensed state; all runtime readers fall back to an empty
key when the option is not present.

```sh
ubus call safeshield license_update '{"license_key":"YOUR-LICENSE-KEY"}'
ubus call safeshield license_update '{"license_key":""}'
```

The package also installs an rpcd ACL named `safeshield`. Read access covers
`status`, `config` and `rules_list`; sensitive license access and mutating
methods are declared as write access.

## Contributors

<a href="https://github.com/Junatum/safeshield/graphs/contributors">
    <img src="https://contrib.rocks/image?repo=Junatum/safeshield" alt="Contributors">
</a>

## Support

For product information, supported devices, installation guidance, and firmware downloads, visit:

https://www.smartsafehub.com/

For SafeShield source-code issues or feature requests, open an issue on GitHub:

https://github.com/Junatum/safeshield/issues

Bug reports and pull requests are welcome.

## Third-party blocklist data

SafeShield may install SmartSafeHub artifacts derived from third-party DNS
blocklists, including [HaGeZi's DNS Blocklists](https://github.com/hagezi/dns-blocklists).
HaGeZi-derived artifacts remain subject to GNU GPL v3.0. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the upstream project,
license, source inventory, and installed notice location.

## License

SafeShield is under the [GNU Public License version 3](https://www.gnu.org/licenses/gpl-3.0.html)
