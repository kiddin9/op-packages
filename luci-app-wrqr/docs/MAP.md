# Repository map

Where things live. The whole application is two files under `luci/`.

## The shape of it

One OpenWrt package, `luci-app-wrqr`: a Wi-Fi QR widget on LuCI's Status →
Overview page. It shows one QR code per distinct active access-point
configuration and merges identical networks broadcast by several radios.

| file | owns |
| --- | --- |
| `luci/overview.js` | the widget: reads UCI and wireless runtime state, renders the codes |
| `luci/shared.js` | the design system and the dictionary |
| `luci/acl.json` | the calls the widget is allowed to make |
| `Makefile`, `release.env`, `apk-feed.env` | packaging and release identity |
| `scripts/` | build, packaging and the checks |

The widget is read-only by design: it restarts nothing and writes nothing.
Unsupported, disabled and non-AP interfaces are omitted rather than shown in
an error state.

## Checks

```sh
./scripts/ci-check.sh
```

`scripts/test-overview-ui.js` stubs LuCI and renders the widget - a page that
merely parses can still die at render.

## Documentation

| file | for |
| --- | --- |
| `docs/MAP.md` | this file |
| `docs/DEVELOPMENT.md` | building, signing and releasing |
| `README.md` | user-facing, English |
| `README.ru.md` | the Russian version |
