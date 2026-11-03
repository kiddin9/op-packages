# Wi-Fi QR for OpenWrt

[Русский](README.ru.md)

[![CI](https://github.com/Nikitid/luci-app-wrqr/actions/workflows/ci.yml/badge.svg)](https://github.com/Nikitid/luci-app-wrqr/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Nikitid/luci-app-wrqr)](https://github.com/Nikitid/luci-app-wrqr/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

The `luci-app-wrqr` package adds a widget with Wi-Fi QR codes to the LuCI
**Status -> Overview** page.

![Wi-Fi QR widget on Status -> Overview](docs/images/widget.png)

## Features

- one QR code for each distinct active access point;
- identical networks broadcast by several radios share one code;
- disabled, unsupported and non-AP interfaces are left out.

## Requirements

- OpenWrt 24.10 (IPK) or OpenWrt 25.12 (APK);
- LuCI.

## Installation

### OpenWrt 24.10

Download the latest `luci-app-wrqr_*_all.ipk` from
[Releases](https://github.com/Nikitid/luci-app-wrqr/releases) and upload it
through **System -> Software -> Upload Package**.

### OpenWrt 25.12

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-wrqr
```

The installer verifies the publisher key, adds the shared signed Nikitid
application repository and installs only the named package. To update:

```sh
apk update
apk upgrade luci-app-wrqr
```

## How it works

The widget reads fresh UCI and wireless runtime state on LuCI's normal status
poll. It only reads: it restarts nothing and writes nothing - not Wi-Fi, rpcd,
uhttpd or the router.

## Development

```sh
./scripts/ci-check.sh
```

Building, signing and releasing: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Documentation

- [Repository map](docs/MAP.md) - where things live
- [Development](docs/DEVELOPMENT.md) - building, signing and releasing

## Support

Questions and bug reports go to
[Issues](https://github.com/Nikitid/luci-app-wrqr/issues/new/choose): pick the form that
fits. Report a vulnerability privately through
[a security advisory](https://github.com/Nikitid/luci-app-wrqr/security/advisories/new).
English or Russian is fine.

## License

[MIT](LICENSE)
