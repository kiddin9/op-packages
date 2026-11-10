# luci-app-liteportal

A static HTML navigation dashboard for OpenWrt / ImmortalWrt, served by the
router's existing `uhttpd` under `/liteportal/` and configured entirely from LuCI.

[中文说明](README.zh-CN.md)

| LuCI — *Services → Portal* | The portal page |
|---|---|
| <img src="docs/images/luci-settings.png" width="400" height="232" alt="General settings tab: service status, enable switch, page title, background colour and the current background image"> | <img src="docs/images/portal-page.png" width="400" height="232" alt="The portal page: the heading, the search box and two bookmark cards over a blurred background photo"> |

## What it does

The router keeps serving its normal LuCI exactly as before. This app adds a
deliberately minimal page next to it — a grid of bookmarks to the services
running on the router (or anywhere else) — on a path of the *same* web server,
so there is no second daemon to run and no extra port to open in the firewall.
Bookmarks, icons and the background are stored in `uci` and baked into a static
`links.json`, so the portal page itself never needs a backend.

```
                    ┌──────────────────────────────────────┐
   :80 / :443  ────►│  uhttpd  (the router's web server)   │
                    │    /             → LuCI              │
                    │    /liteportal/  → the portal page   │
                    └──────────────────┬───────────────────┘
                                       │ served straight from disk
                                       ▼
                    ┌──────────────────────────────────────┐
                    │  /www/liteportal/                    │
                    │    index.html   liteportal.js        │
                    │    liteportal.css                    │
                    │    links.json   ◄── baked from uci   │
                    │    bg/  icons/  ◄── uploads land here│
                    └──────────────────────────────────────┘
                                       ▲
   LuCI  ── /admin/services/liteportal ────────────────────┘  publishes / withdraws the page
```

## Features

| | |
|---|---|
| On/off switch | Publish the page or take it off the web server; the uploaded icons and backgrounds survive either way |
| No second daemon | Served by the `uhttpd` the router already runs, under `/liteportal/` — nothing extra to start, supervise or open in the firewall |
| Bookmarks | Add, enable/disable and delete; emoji, remote URL or an image from the asset library (a thumbnail is shown in the row when an asset image is used) |
| Asset library | Upload (2 MiB per file), preview, rename, list and delete icons and background images, and pick the page background |
| Appearance | Page title, CSS background colour or a background image, plus 0-100 sliders for background dimming, frosted blur and bookmark-card transparency |
| Search box | A search field that stays hidden until you press the space bar, submits straight to the chosen engine from the browser, and needs no backend at all |
| Discovery | Scans `/proc/net/tcp[6]` for locally reachable listening services, adds the known web ones as *disabled* bookmarks, and asks about the rest |
| Status panel | Reports whether the page is reachable *and*, when it is not, which of the two conditions behind that is missing — plus the address and the baked bookmark count |
| Static output | Everything is persisted in `uci` and rendered into `links.json`; the page is plain HTML/JS |
| No `luci-compat` | Pure JavaScript views on the modern LuCI stack — no Lua runtime required |

## Using the search box

Enable it under *General → Search box* and the portal page gains a search field
that stays out of the way until you call for it. That is the whole point: the
page is a grid of links, and a permanently visible input would compete with them.

| Action | Result |
|---|---|
| Press `Space` anywhere on the page | The box appears and takes focus |
| Press `Space` again while the box is empty, or `Esc` | The box is put away |
| Type, then `Enter` | The results open in a new tab; the box clears and hides |

Two behaviours worth knowing before they surprise you:

- **A space typed into a non-empty box is a space.** Only an empty box hides on
  `Space`, so a two-word query needs no modifier.
- **An input method keeps its own space bar.** While a composition is in progress
  the key belongs to the IME, and any other text field on the page keeps its
  space bar as well.

The query is submitted by the browser straight to the engine, so the router needs
no backend method for it — nothing to grant in the ACL. The engine is picked in
the same *General* page: Google, Bing, DuckDuckGo, Baidu, or *Custom* with your
own results URL (`%s` marks where the keyword goes).

## Requirements

| Component | Minimum |
|---|---|
| OpenWrt / ImmortalWrt | 23.05 (JS LuCI + ucode) |
| Packages | `luci-base`, `uhttpd`, `ucode`, `rpcd-mod-ucode` (pulled in automatically) |

## Install

```sh
# OpenWrt 25.12 and newer (apk)
apk add --allow-untrusted ./luci-app-liteportal-4.0.1-r1.apk

# OpenWrt 24.10 and older (opkg), built from the matching SDK
opkg install ./luci-app-liteportal_4.0.1-r1_all.ipk
```

Then open **Services → Portal** in LuCI, or go straight to
`http://<router>/liteportal/`.

## Layout

| Path | Purpose |
|---|---|
| `htdocs/luci-static/resources/liteportal/common.js` | Shared helpers: RPC wrappers, status panel, error reporting |
| `htdocs/luci-static/resources/view/liteportal/general.js` | LuCI view — switch, title, background, appearance, maintenance |
| `htdocs/luci-static/resources/view/liteportal/bookmarks.js` | LuCI view — the bookmark table |
| `htdocs/luci-static/resources/view/liteportal/assets.js` | LuCI view — the icon and background image library |
| `root/usr/share/luci/menu.d/luci-app-liteportal.json` | Menu registration |
| `root/usr/share/rpcd/acl.d/luci-app-liteportal.json` | ubus / uci / file permissions for the views |
| `root/usr/share/rpcd/ucode/liteportal.uc` | Backend: the `luci.liteportal` ubus object (plugin only, no CLI mode) |
| `root/etc/init.d/liteportal` | Service script: publishes or withdraws the page and bakes `links.json`; runs no daemon of its own |
| `root/usr/share/liteportal/www/` | Portal frontend template (`index.html`, `liteportal.js`, `liteportal.css`), copied into `/www/liteportal/` |
| `root/etc/config/liteportal` | Default `uci` configuration |
| `scripts/check.sh` | The entire local/CI gate — read this before the rest |
| `docs/` | Architecture, DoD, configuration and the ADR log |

## Backend API

`/usr/share/rpcd/ucode/liteportal.uc` is loaded by `rpcd-mod-ucode` and exposed as
the `luci.liteportal` ubus object:

```sh
ubus call luci.liteportal generate
# { "ok": true, "title": "My Portal", "links": 2 }

ubus call luci.liteportal scan
# { "lan_ip": "192.168.1.1",
#   "ports": [ { "port": 80, "svc": "http", "web": true },
#              { "port": 22, "svc": "ssh", "web": false },
#              { "port": 7890, "svc": "", "web": "unknown" } ] }

ubus call luci.liteportal status
# { "ok": true, "enabled": true, "path": "/liteportal/", "published": true,
#   "server_listening": true, "reachable": true, "links": 2,
#   "generated": true, "generated_at": 1791124783 }

# asset management - the browser may only write /tmp/liteportal_upload.tmp,
# the backend moves the file to its final name
ubus call luci.liteportal upload '{ "dir": "bg", "name": "wallpaper.jpg" }'
ubus call luci.liteportal rename '{ "dir": "bg", "name": "wallpaper.jpg", "new_name": "home.jpg" }'
ubus call luci.liteportal remove  '{ "dir": "bg", "name": "home.jpg" }'
```

Every method above must be listed in `root/usr/share/rpcd/acl.d/luci-app-liteportal.json`,
otherwise the view gets *Access denied* in the browser. `scripts/check.sh` verifies
this correspondence on every run.

The `web` field of a scanned port is one of:

| Value | Meaning |
|---|---|
| `true` | A known web service — added as a disabled bookmark |
| `false` | Definitely not a browser target (`ssh`, `dns`, `mdns`, `dhcp`, `ntp`, `openvpn`, `wireguard`, …) — never offered |
| `"unknown"` | No `/etc/services` entry says what speaks on it — listed in a dialog, your call |

A port number carries no protocol information, so `7890` may be a proxy or an
arbitrary TCP service and `1053` is mDNS. Rather than guess in either direction,
unrecognised ports are shown and can be added as disabled bookmarks in one go.

The script is a plugin only — rpcd does not define `ARGV` while loading it, so it
cannot double as a command line tool. Call it over ubus as shown above.

`status` answers one question — can the page be reached — and reports the two
conditions behind it separately, because each has a different fix: `published`
(the entry point and `links.json` are in place) and `server_listening` (the main
uhttpd owns one of the ports it was configured with). `reachable` is the two of
them together. The result carries no `url`: the browser composes the address from
its own origin plus `path`, which is the one address guaranteed to be the server
that is actually serving the page.

## uci reference

```
config liteportal
	option enabled           '1'         # master switch; '0' takes the page off the web server
	option title             'My Portal' # page heading and <title>
	option background        '#0e1116'   # CSS colour
	option background_file   ''          # absolute path below /www/liteportal
	option bg_veil           '78'        # 0-100: how strongly a background image is dimmed
	option bg_blur           '0'         # 0-100: frosted blur, 100 = the 20 px maximum
	option card_transparency '45'        # 0-100: 100 = bookmark cards fully see-through
	option search_enabled    '0'         # '1' enables the space-bar search box
	option search_engine     'https://www.google.com/search?q=%s'  # results URL, %s = keyword

config link
	option name     'AdGuard Home'
	option url      'http://192.168.1.1:3000'
	option icon_url '🛡️'              # or: option icon '/www/liteportal/icons/x.png'
	option enabled  '1'
```

The page carries no port of its own: it is reachable on whatever port the main
`uhttpd` listens on, so there is nothing to open in the firewall.

`enabled` means "publish or withdraw the page", not "start or stop a daemon".
Switching it off removes the entry point and `links.json` from
`/www/liteportal/`, so `/liteportal/` stops resolving; the uploaded icons and
backgrounds are left alone and come back when it is switched on again.

`links.json` carries the title, the background and the three appearance
percentages as they are written in uci; `liteportal.js` turns the percentages into
the CSS custom properties `liteportal.css` consumes, so the served page never has to
read uci itself. A missing percentage falls back to the same default value in the
backend, so a partially written configuration still renders.

The file is re-read on every page load: the request bypasses the browser cache on
purpose. A static file reaches the browser with `Last-Modified` but no
`Cache-Control`, which makes a browser cache it heuristically for a fraction of
its age — a portal untouched for a day was considered fresh for hours, so a saved
change to any appearance slider only showed up after a hard reload.

`search_enabled` switches the search box on; an absent value means off.
`search_engine` is the engine's results URL with `%s` standing for the keyword,
and choosing *Custom* in the form sends the page to the template in `search_url`
instead — an option written only in that case. The engine list lives in the LuCI
form and nowhere else: `links.json` carries just the resolved template, so the
portal page holds no engine knowledge of its own. **See *Using the search box*
above for the keyboard interaction.**

It is regenerated automatically whenever `/etc/config/liteportal` changes (LuCI
*Save & Apply*, or `uci commit` plus `/etc/init.d/liteportal reload`).

## Troubleshooting

The *General* page has a **Service status** panel; the same numbers come from
ubus:

```sh
ubus call luci.liteportal status
```

| Symptom | Cause |
|---|---|
| `enabled: false` | The switch in *General* is off — tick it and press **Save & Apply** |
| `published: false` | The page is not on disk: the service has not run yet, or the switch is off. `sh /etc/init.d/liteportal start` publishes it |
| `server_listening: false` | The main uhttpd is not listening on any port it was configured with — check `/etc/config/uhttpd` |
| `/liteportal/` answers 404 although the panel says *reachable* | The main instance's `option home` is not `/www`, so it is serving a different tree |
| Page loads, but no bookmarks | `links.json` missing or empty — press *Save & Apply* to re-bake it, or run `ubus call luci.liteportal generate` |
| *Access denied* in the browser console | A ubus method is missing from the ACL — run `sh scripts/check.sh` |

The page is served by the main uhttpd, so it inherits that instance's listen
addresses and firewall rules — there is no separate port to unblock. The flip
side is worth knowing before you enable it: `/liteportal/` is reachable wherever LuCI
is, including from the WAN if the admin interface is exposed there.

## Known limitations

| Limitation | Why |
|---|---|
| Uploads are capped at 2 MiB | Enforced in the UI *and* in the backend, so a hand crafted request cannot bypass it. Multi-megabyte backgrounds are served fine — only the upload is bounded |
| File names are ASCII only: letters, digits, `.`, `-`, `_` | The name becomes a device path. Rejecting is safer than silently rewriting what the user typed, and it rules out path traversal by construction. Chinese names and spaces are refused |
| The page is reachable wherever LuCI is | It is served by the same uhttpd and therefore inherits the admin interface's exposure — there is no separate port left closed. Putting it out of reach would mean putting LuCI out of reach |
| The location is fixed at `/liteportal/` | It has to live inside the main instance's `option home` (default `/www`), and the LuCI-side file ACL is a static list — a custom `home` needs the package adjusted |
| Unrecognised ports are not probed | Deciding whether a port speaks HTTP would need an active `GET /` with a timeout inside a synchronous ubus method, which blocks the whole rpcd — and therefore every other LuCI page. They are listed for you to decide instead |
| Setting a background image is staged, not applied | Like every other setting, it waits for **Save & Apply**. `generate()` runs in the backend process with its own `uci` cursor and would otherwise bake the old value |

## Building

Building needs a Linux SDK matching the target firmware — WSL2 + Ubuntu works
fine, but the SDK and the source tree must live on the Linux filesystem, never
under `/mnt/`.

```sh
tar --zstd -xf immortalwrt-sdk-<version>-<arch>_gcc-*.tar.zst
cd immortalwrt-sdk-*/

./scripts/feeds update -a
./scripts/feeds install -a

cp -r /path/to/luci-app-liteportal package/luci-app-liteportal
make defconfig
make package/luci-app-liteportal/compile V=s
```

The artefact lands in `bin/packages/<arch>/luci/`. Note that the SDK ships a
`.config` describing a whole firmware image; strip its `CONFIG_PACKAGE_*=m`
lines before compiling unless you actually want to build the entire package
tree.

## Development

```sh
sh scripts/check.sh
```

That is the same gate CI runs: JS syntax, JSON validity, `shellcheck`,
`msgfmt --check`, the ubus↔ACL correspondence, line endings and leftover template
placeholders. It exits non-zero on the first failure. Individual commands are
listed in [AGENTS.md](AGENTS.md) §2, and the code conventions in
[docs/architecture.md](docs/architecture.md).

## License

GPL-2.0-only. See [LICENSE](LICENSE).
