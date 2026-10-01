# luci-app-substore

**English** | [简体中文](README.md)

Native **OpenWrt / ImmortalWrt** LuCI application for managing airport / proxy
subscriptions. Parse nodes from a subscription, filter, deduplicate, rename and
group them, then re-emit them in a format your client can consume.

![Screenshot](screenshot.png)

## Features

**Subscription management**
- Add / edit / delete / update multiple subscription sources
- Manual update plus per-subscription timed (cron) updates
- Status overview: node count, last update time, error message
- Remaining traffic & remaining duration per subscription, parsed from the
  `subscription-userinfo` response header (shown on the edit page only)
- **Subscription proxy**: download the subscription through an
  `http://` / `https://` / `socks4` / `socks5` / `socks5h` proxy — useful when the
  source is unreachable directly
- **Combination subscription**: merge an arbitrary subset of existing subscriptions
  (optionally with keyword include / exclude and dedup rules) into one combination that
  has its own name, token and subscription link; combinations are recomputed automatically
  when a source updates
- **Local subscription**: no URL needed — paste node text (YAML / URI / JSON /
  wg-quick `.conf`) or enter nodes one by one via a form whose fields adapt to the
  selected protocol. A paste is detected as **one** format (YAML / URI / JSON /
  `.conf`); mixing several formats in one paste is not supported
  (vmess / vless / ss / ssr / trojan / hysteria / hysteria2 / tuic / wireguard / socks)

**Input parsing**
- Subscription formats: URI lists, Base64, JSON, Clash YAML, sing-box JSON,
  V2Ray / Xray JSON, Surge / Surfboard / Loon / Quantumult X configs, LAN
  subscription links, and wg-quick / AmneziaWG `.conf`
- Node protocols: `vmess` / `vless` / `trojan` / `shadowsocks` / `ssr` / `hysteria` /
  `hysteria2` / `tuic` / `wireguard` / `socks` (plus `http`, which can be imported from
  Clash YAML / JSON configs and exported, but is not offered in the form importer —
  it is not served as a proxy node)
- **WireGuard / AmneziaWG**: full field import and export (`private-key` / `public-key` /
  `pre-shared-key` / `ip` / `ipv6` / `allowed-ips` / `reserved` / `persistent-keepalive` /
  `listen-port` / `mtu` / `dns`) plus the `amnezia-wg-option` sub-block
  (Jc / Jmin / Jmax / S1–S4 / H1–H4 / I1–I5 / J1–J3 / Itime); you can paste the contents
  of a `.conf` file exported by an AmneziaWG client directly
- **Parsing tolerance**: `ssr://` accepts both the standard and the base64url alphabet
  for its outer layer; incomplete nodes (missing `server`, or `port` outside 1–65535)
  are dropped **at parse time** (otherwise they become `server:` / `port: 0`, which makes
  mihomo and sing-box refuse to load the whole file — one bad node kills a subscription);
  passwords containing `@` are split on the **last** `@`; sing-box YAML's nested `tls:`
  block (including the `alpn` list and `utls.fingerprint`) is fully expanded; wg-quick
  `.conf` supports inline `#` comments (matching wg-quick's own splitting semantics),
  and a single bad `[Peer]` skips only itself instead of discarding the whole file;
  whitespace-only content is treated as an empty subscription rather than reported as
  an unrecognised format

**Node processing**
- Browse nodes, filter by group / protocol, keyword search, sort
- Node grouping: set a node's group inline in the Group column (saved via XHR without
  reload), filter via the Group dropdown
- Per-node edit / delete (Actions column); header checkbox selects all, then the Delete
  button batch-deletes the selection; the Refresh button reloads the list keeping the
  current filters
- Per-subscription rules applied on every update (available on all three forms:
  subscription / combination / local subscription):
  - keyword include / exclude (comma-separated, multi-keyword)
  - protocol filter (tick the protocols to keep; none ticked = no filtering)
  - deduplication (multiple accounts on the same endpoint are not merged: the
    dedup key includes each protocol's own credentials)
  - rename (one rule per line: `OLD=NEW` exact, `PATTERN -> REPLACEMENT` regex,
    `{server}_{port}_{proto}` placeholder template)

**Network probing** (Nodes page)
- Ping (ICMP latency), TCPing (connect latency), URL test (HTTP latency)
- Parallel probing, success count and average latency

**Conversion & output**
- Protocol conversion: any node type → any other type
- SSR (`ssr://`) input is re-emitted losslessly to SSR-capable clients only — Mihomo /
  Clash.Meta, Stash, Loon, Egern, Shadowrocket — and dropped for the rest (sing-box,
  V2Ray/Xray, Surge family), since SSR is not convertible to/from other protocols
- 15 output formats (all implemented): Plain JSON, Stash, Clash.Meta / Mihomo YAML,
  Clash (original), Surfboard, Surge, Surge Mac, Loon, Egern, Shadowrocket,
  Quantumult X, sing-box, V2Ray / Xray, V2Ray URI, WireGuard / AmneziaWG `.conf`
  - **Clash.Meta / Mihomo**: emits transport parameters in full (`ws-opts` / `grpc-opts` /
    `h2-opts` path, host and service name) plus vless `flow` (XTLS Vision)
  - **Clash (original)**: for Dreamacro Clash / ClashX / Clash for Windows; protocols the
    original does not support (vless / hysteria2 / hysteria / tuic / wireguard) are filtered out
  - **WireGuard / AmneziaWG `.conf`**: wg-quick single-interface config with `[Interface]` /
    `[Peer]` sections and AmneziaWG obfuscation parameters, importable by AmneziaWG clients
  - **sing-box / V2Ray (Xray)**: emits a **complete, runnable config** (`outbounds` plus
    routing), not just an `outbounds` fragment
    - sing-box: node outbounds + `selector` (manual switch) + `urltest` (auto latency test) +
      `direct` / `block`; `route.final` points at the selector, with a built-in private-IP
      direct rule
    - V2Ray/Xray: node outbounds + `freedom` (direct) / `blackhole` (block) + `observatory` +
      `routing.balancers` (`leastPing` auto-selection), with built-in `geoip:private` direct
      and a catch-all route
      - Only Xray-supported protocols are emitted (vmess / vless / trojan / shadowsocks /
        socks / http); hysteria2 / hysteria / tuic / wireguard / ssr have no corresponding
        outbound type and are filtered out (an unknown `protocol` makes Xray refuse to load
        the whole config)
    - Deliberately **excludes `inbounds` / `dns`**: those bind local listening ports and
      override your existing DNS settings — keep them in your own config and merge this
      output into it
    - ⚠️ Not compatible with 2.3.x: 2.3.x emitted an `outbounds`-only fragment meant to be
      pasted into an existing config; from 2.4.0 it is a complete config you can start
      directly as a single file
- **Output validity**: only what the target client can actually load is emitted — not
  something that merely looks right
  - WireGuard `allowed-ips` / `reserved` / `dns` are always emitted as the arrays the
    target client requires (`[]string` / `[]uint8` for both mihomo and sing-box),
    whether the source was a YAML list or a comma-separated string; a scalar makes the
    client **refuse to load the whole config**
  - Surge-family / Quantumult X proxy-group member lists drop node names containing a
    **comma**: those formats have no quoting or escaping, so a comma in a name is read as
    a member separator, yielding two members that do not exist and making the client
    refuse the whole config for referencing unknown proxies; Quantumult X's `[policy]`
    additionally lists only nodes that actually got a `[server_local]` line, so no
    dangling references remain
  - hysteria / hysteria2 share links take `insecure` from the authoritative
    `skip-cert-verify` field, so nodes imported from Clash YAML / sing-box JSON / the
    form no longer lose "skip certificate verification"

**Subscription links**
- Per-subscription random token → public download endpoint
  `/substore/download?token=<token>&target=<format>` that Passwall / OpenClash and
  other clients can pull directly

**LuCI web UI & i18n**
- English by default, 简体中文 auto-selected when the runtime language is `zh-cn`

## Installation

> The version in the package name must match `PKG_VERSION` / `PKG_RELEASE` in the
> [Makefile](Makefile) (currently `2.6.9-r1`).

opkg (OpenWrt / ImmortalWrt 24.10 and earlier):

```bash
opkg install luci-app-substore-2.6.9-r1.ipk
```

apk (OpenWrt / ImmortalWrt 25.12+):

```bash
apk add --allow-untrusted luci-app-substore-2.6.9-r1.apk
```

Then open LuCI: **Services → Subscriptions**.

## Usage

1. **Add a subscription** — paste the subscription URL; optionally set up a
   per-subscription cron schedule, rules, or a download proxy. No remote source?
   Use **Add local subscription**: paste node text or enter nodes via the form.
2. **Update** — fetch, parse and filter the nodes.
3. **Browse nodes** — filter (group / protocol / keyword), sort, probe latency; tick
   checkboxes and hit Delete for batch deletion, edit / delete / regroup in-row, and
   Refresh reloads the list.
4. **Export** — pick one of the 15 output formats, or copy the subscription link
   to feed a downstream client (Passwall / OpenClash / …).

## Project layout

```
.
├── Makefile                      # OpenWrt package definition
├── LICENSE                       # GPL-2.0-or-later
├── root/                         # install payload
│   ├── etc/
│   │   ├── config/substore       # UCI placeholder
│   │   └── uci-defaults/99-substore
│   ├── usr/
│   │   ├── bin/substore-cron.sh  # per-subscription cron runner
│   │   ├── lib/lua/luci/
│   │   │   ├── controller/admin/substore.lua   # routes / actions
│   │   │   └── view/substore/*.htm             # templates
│   │   └── share/
│   │       ├── luci/menu.d/luci-app-substore.json
│   │       └── substore/*.lua    # core logic (no luci.* dependency)
├── po/zh-cn/substore.po          # 简体中文 translations
├── docs/                         # design & guides
└── tests/                        # self-contained Lua 5.1 unit tests
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — architecture design
- [docs/PLAN.md](docs/PLAN.md) — staged development plan
- [docs/BUILD.md](docs/BUILD.md) — building from an OpenWrt SDK/source tree
- [docs/INSTALL.md](docs/INSTALL.md) — installation
- [docs/SECURITY.md](docs/SECURITY.md) — security model
- [docs/TESTING.md](docs/TESTING.md) — testing
- [docs/UCODE_MIGRATION.md](docs/UCODE_MIGRATION.md) — `.htm` → `.ut` (ucode) migration notes
- [CHANGELOG.md](CHANGELOG.md) — changelog
- [docs/LEGACY_ISSUES.md](docs/LEGACY_ISSUES.md) — known unfixed issues (pending decision)

## Building

Place the package under an OpenWrt / ImmortalWrt SDK or source tree matching the
target firmware, then:

```bash
cp -r luci-app-substore <openwrt-tree>/package/
make package/luci-app-substore/compile V=s
```

The `.ipk` (or `.apk` on apk builds) is produced under `bin/packages/.../`.

## Development & testing

The core is plain Lua 5.1 with no `luci.*` dependency, so it is unit-testable
without a device. Each file under `tests/` is self-contained:

```bash
lua5.1 tests/run_tests.lua          # or any single test file
for f in tests/*.lua; do lua5.1 "$f" || exit 1; done
```

Target-device verification is required for the LuCI UI and cron behaviour — see
[docs/TESTING.md](docs/TESTING.md).

## Security

SSRF protection (private / reserved / link-local ranges rejected; a hostname that
**fails to resolve is rejected** rather than allowed, so "unresolvable ⇒ pass" is not
a bypass), protocol whitelisting and port range validation (1–65535), response size &
timeout limits, download temp files removed on every exit path (`/tmp` is a tmpfs),
command-injection defence (whitelisted parsing + shell quoting, plus probe targets
starting with `-` rejected — busybox `getopt` would read them as options),
token-based access control on the public download endpoint, and no credentials in
logs.

Data on disk: `/etc/substore` is `0700`, and `subscriptions.json` / `nodes/*.json`
are `0600` — the former holds subscription URLs and public download tokens, the
latter uuid / passwords / private keys. `io.open` creates files per the umask
(typically 0644), readable by any local user, so the mode is tightened explicitly
after each write.

Batch node probing is capped at 16 concurrent processes (`probe.MAX_PARALLEL`):
the node count comes from subscription content, and unbounded concurrency exhausts
the router's fd / process budget, after which `io.popen` fails silently.

See [docs/SECURITY.md](docs/SECURITY.md).

## License

[GPL-2.0-or-later](LICENSE) — see the [LICENSE](LICENSE) file.