# luci-app-substore

**English** | [简体中文](README.md)

Native **OpenWrt / ImmortalWrt** LuCI application for managing airport / proxy
subscriptions. Parse nodes from a subscription, filter, deduplicate, rename and
group them, then re-emit them in a format your client can consume.

![Screenshot](screenshot.png)

## Features

**Subscription management**
- Add / edit / delete / update multiple subscription sources, with manual and
  per-subscription scheduled (cron) updates; an overview shows node counts, last
  update time and error messages
- **Batch delete**: tick one or more subscriptions (the header checkbox selects
  all) and hit Delete to remove them in one go; with nothing ticked, Delete
  removes nothing
- Remaining traffic / expiry per subscription (parsed from the `subscription-userinfo`
  response header)
- **Subscription proxy**: fetch through `http` / `https` / `socks4` / `socks5` /
  `socks5h`, for sources that cannot be reached directly
- **Subscription client type**: the `User-Agent` sent when fetching, set per
  subscription, with Clash Verge / v2rayN / Clash Party / FlClash presets and a
  custom value (the raw `User-Agent` header to send verbatim, e.g.
  `clash-verge/v2.5.0`; at most 256 chars, no control characters).
  Some providers hand out nodes by UA — the same link only yields the
  real nodes for its bound client; a wrong UA returns a "client incompatible"
  placeholder (which still parses, but is nothing but fake `127.0.0.1:1080` nodes)
- **Combined subscriptions**: merge any subset of existing subscriptions into a new
  one with its own name, token and link; it is recomputed when a source updates or
  is **deleted** (the dead id is pruned from its sources; deleting every source
  reports an error instead of silently becoming a 0-node combo)
- **Local subscriptions**: paste node text directly (one format at a time,
  auto-detected) instead of providing a URL, or enter nodes field by field

**Input parsing**
- Formats: URI list, Base64, JSON, Clash YAML, sing-box JSON, V2Ray / Xray JSON,
  Surge / Surfboard / Loon / Quantumult X configs, wg-quick / AmneziaWG `.conf`
- Protocols: `vmess` / `vless` / `trojan` / `shadowsocks` / `ssr` / `hysteria` /
  `hysteria2` / `tuic` / `wireguard` / `socks`
  (`http` can be imported and exported, but is not offered in the node form)
- **WireGuard / AmneziaWG**: all fields plus the `amnezia-wg-option` block; an
  AmneziaWG client `.conf` can be pasted as-is
- **Tolerant parsing**: nodes missing `server`, or with a port outside 1–65535, are
  dropped during parsing — otherwise they would be written into a config the client
  refuses to load, and one bad node would break the whole subscription

**Node handling**
- Filter by group / protocol, keyword search, sorting; a node's group is editable
  directly in the table (saved over XHR)
- Edit / delete a single node, or select several and delete them in bulk
- Per-subscription rules: keyword include / exclude, protocol filter, dedup, and
  rename (exact match / regex / placeholder template)

**Network probing** (nodes page)
- Ping (ICMP), TCPing (TCP connect) and URL test (HTTP), run in parallel with a
  success count and average latency

**Conversion & output**
- 15 output formats: Plain JSON, Stash, Clash.Meta / Mihomo, Clash (original),
  Surfboard, Surge, Surge Mac, Loon, Egern, Shadowrocket, Quantumult X, sing-box,
  V2Ray / Xray, V2Ray URI, WireGuard / AmneziaWG `.conf`
- SSR (`ssr://`) can only be emitted to clients that support it (Mihomo, Stash, Loon,
  Egern, Shadowrocket); other targets drop it
- **Only content the target client can actually load is emitted**: protocols are
  filtered by target capability, array-valued fields use the type the client expects,
  and proxy-group member lists drop node names that would break their syntax
- sing-box / V2Ray(Xray) output is a **complete working config** (including routing),
  usable as a single-file config

**Subscription links**
- A random per-subscription token backs the public download endpoint
  `/substore/download?token=<token>&target=<format>`, so Passwall / OpenClash can
  pull it directly
- The format dropdown on the list page stays greyed out until the subscription has
  actually parsed some nodes (just added, update failed, or node count 0), so you
  cannot generate a subscription link that is bound to be empty

**LuCI interface & i18n**
- English by default, Simplified Chinese when the runtime language is `zh-cn`

## Installation

> The version in the package name must match `PKG_VERSION` / `PKG_RELEASE` in the
> [Makefile](Makefile) (currently `2.7.1-r5`).

**Minimum supported: OpenWrt / ImmortalWrt 23.05** (older releases are out of scope).

opkg (OpenWrt / ImmortalWrt 24.10 and earlier):

```bash
opkg install luci-app-substore-2.7.1-r5.ipk
```

apk (OpenWrt / ImmortalWrt 25.12+):

```bash
apk add --allow-untrusted luci-app-substore-2.7.1-r5.apk
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

> **Rename rules match with Lua patterns, not PCRE.** `|` means "or", but only at
> the **top level**: `(a|b)` is not expanded into "a or b" — it matches literally,
> requiring the name to actually contain `a|b`. Write `a|b` for alternatives, or
> use separate rules. A `|` inside a character class `[...]` is literal too.

## Known limitations

Each of these is a **code-audit-confirmed** limitation kept deliberately, not an
oversight; the reasoning for each is in
[docs/LEGACY_ISSUES.md](docs/LEGACY_ISSUES.md) (Chinese).

- **Mixed-format text import is rejected** — pasted node text may contain only one
  format at a time (URI / Base64 / YAML / JSON / WireGuard `.conf`); protocols may
  be mixed *within* that format. Mixing formats fails with an explicit error naming
  the formats found, instead of silently dropping part of the input.
  **Remote subscriptions are not affected**: mixed content there is still resolved
  by priority to a single format (unchanged historical behaviour).
- **hysteria v1 exported to sing-box needs `up` / `down` (bandwidth) added by hand** —
  the node model carries no bandwidth field, and inventing a default would be a guess.
- **hysteria v1 URIs are only guaranteed round-trip faithful** (this package's export →
  this package's import) — the upstream URI spec could not be verified (its docs site
  has been 404ing), so unrecognised query parameters are ignored rather than
  given an invented meaning.
- **`http` cannot be created by hand in the UI** — it is absent from the authoritative
  protocol list, so the form does not offer it; it can still be imported from
  Clash / JSON configs and exported normally.
- **AmneziaWG options are a single JSON text box** in the UI (`amnezia-wg-option`) —
  the data round-trips correctly, but has to be written as JSON by hand.
- **On the wget backend, size and redirect checks happen *after* the request is sent** —
  busybox wget has no equivalent of `--max-filesize` / `--max-redirect`. An oversized
  response is **discarded and reported as an error** (it never reaches the parser), and
  every redirect hop is **re-checked** with any private/reserved hop rejecting the whole
  download; the only difference is that both checks land after the request went out.
  **Installing curl avoids this entirely** (the curl path uses `--max-filesize` and
  `--max-redirs 0` to stop before sending).
- **On a box with no DNS resolution capability at all, the wget backend refuses to
  download domain subscriptions** — pre-flight validation cannot check the target there,
  and wget lacks curl's `%{remote_ip}` for a post-connect re-check, so it refuses rather
  than allowing an unverifiable target (the error suggests installing curl). Literal IP
  targets and boxes that do have a resolver are unaffected.

## Project layout

```
.
├── Makefile                      # OpenWrt package definition
├── LICENSE                       # GPL-3.0-or-later
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
│   │       ├── rpcd/acl.d/luci-app-substore.json  # ACL group (referenced by menu depends.acl)
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
**fails to resolve is rejected** when a resolver is available, so "unresolvable ⇒ pass"
is not a bypass; every redirect hop is re-checked), protocol whitelisting and port range
validation (1–65535), response size & timeout limits, download temp files removed on
every exit path (`/tmp` is a tmpfs), command-injection defence (whitelisted parsing +
shell quoting, plus probe targets starting with `-` rejected — busybox `getopt` would
read them as options), token-based access control on the public download endpoint, and
no credentials in logs.

**On a box with no DNS resolver** (neither nixio nor `nslookup`), domain targets cannot
be validated before the request; the curl backend then re-checks the actual peer address
via `%{remote_ip}` **after connecting** (which also closes the DNS-rebinding TOCTOU
window), while the wget backend has no equivalent and **refuses** instead of allowing it
(see "Known limitations").

**Form submission validation**: write actions require a `token` that is present and
non-empty, and — when available — equal to LuCI's `context.authtoken` (the very value
the framework's templates put in `token`); a failure is **reported back** rather than
silently dropped. **Access control**: the `luci-app-substore` ACL group takes effect
through `menu.d`'s `depends.acl` — unauthorised LuCI users do not see the app, and
**direct URL access is refused with 403** (the ucode dispatcher validates the
`depends.acl` accumulated along the request path at dispatch time; verified against
upstream source **and measured on a device**). See
[docs/SECURITY.md](docs/SECURITY.md) for how to grant it.

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

[GPL-3.0-or-later](LICENSE) — see the [LICENSE](LICENSE) file.