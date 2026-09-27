# Overview Manager for OpenWrt

[Русский](README.ru.md)

[![CI](https://github.com/Nikitid/luci-app-overview-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/Nikitid/luci-app-overview-manager/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Nikitid/luci-app-overview-manager)](https://github.com/Nikitid/luci-app-overview-manager/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

The `luci-app-overview-manager` package is a LuCI application for arranging
the cards on the **Status -> Overview** page.

![Overview Manager widget list](docs/images/widgets.png)

## Features

- reorder widgets by dragging or with the up and down buttons;
- hide cards you do not need;
- works with third-party widgets installed as a LuCI status include;
- the layout is stored in UCI and shared by every browser.

## Requirements

- official OpenWrt `24.10.x` with `opkg`;
- official OpenWrt `25.12.x` with `apk`;
- the stock `luci-mod-status` Status Overview page;
- third-party widgets installed as a LuCI status include.

On OpenWrt 25.12 the stock Hide button keeps its state separately, in the
`localStorage` of one browser. It keeps working independently of the shared
Overview Manager layout.

## Installation

### OpenWrt 24.10

Download `luci-app-overview-manager_*_all.ipk` from
[Releases](https://github.com/Nikitid/luci-app-overview-manager/releases) and upload it
through **System -> Software -> Upload Package**.

### OpenWrt 25.12

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-overview-manager
```

The installer verifies the publisher public key against a pinned checksum,
adds the shared signed repository and installs only the named package.

Later upgrades:

```sh
apk update
apk upgrade luci-app-overview-manager
```

Only Overview Manager is upgraded, never every package on the router.

## How it works

Stock LuCI loads the files in
`/www/luci-static/resources/view/status/include` in alphabetical order.
Overview Manager adds an early service include, matches the cards to their
source files and applies the layout stored in UCI to the DOM.

Files belonging to other packages are never modified, renamed or deleted.
Removing Overview Manager restores stock LuCI behaviour on its own.

## Translations

The interface uses the stock LuCI mechanism: `_()` in JavaScript and gettext
catalogues in `po/`. At build time `po/<lang>/overview-manager.po` is compiled
into `/usr/lib/lua/luci/i18n/overview-manager.<lang>.lmo` and ships in the main
package, and `/etc/uci-defaults/luci-app-overview-manager` registers the
language in `luci.languages`. The interface language follows the LuCI setting;
no separate `luci-i18n-*` package is needed.

The package translates only its own strings: a fully Russian LuCI also needs
`luci-i18n-base-ru`. A new language is added as a
`po/<lang>/overview-manager.po` catalogue; `scripts/test-po2lmo.py` checks that
the catalogues match the sources.

## Limitations

A LuCI status include has no common description of its internals: every widget
implements arbitrary `load()` and `render()`. Overview Manager therefore
arranges the order and visibility of cards, but does not edit their contents.

A hidden widget is not displayed, but its own data collection may still run on
the page poll.

## Development

```sh
./scripts/ci-check.sh
```

Building, signing and releasing: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Documentation

- [Repository map](docs/MAP.md) - where things live
- [Architecture](docs/ARCHITECTURE.md) - why the page is built this way
- [Development](docs/DEVELOPMENT.md) - building, signing and releasing

## Support

Questions and bug reports go to
[Issues](https://github.com/Nikitid/luci-app-overview-manager/issues/new/choose): pick the form that
fits. Report a vulnerability privately through
[a security advisory](https://github.com/Nikitid/luci-app-overview-manager/security/advisories/new).
English or Russian is fine.

## License

[MIT](LICENSE)
