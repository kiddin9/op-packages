# Repository map

Where things live, so a task starts at the right file. Nothing here is large
enough to need a generated function index; the biggest source file is 254
lines, so reading one whole is cheap.

## The shape of it

One OpenWrt package: a LuCI application that customises the Overview page -
which sections appear, in what order, and what each one shows.

| area | files |
| --- | --- |
| pages | `luci/overview.js`, `luci/settings.js` |
| shared design system and dictionary | `luci/shared.js` |
| wiring | `luci/menu.json`, `luci/acl.json` |
| packaged defaults | `openwrt/files/etc/config/overview-manager` |
| translations | `po/` plus `scripts/po2lmo.py` |
| build and release | `Makefile`, `apk-feed.env`, `scripts/` |

## Checks

`scripts/` holds the version-sync, release-tag and translation checks plus
`test-po2lmo.py`. Run them before completion.

## Documentation

| file | for |
| --- | --- |
| `docs/MAP.md` | this file |
| `docs/DEVELOPMENT.md` | building, signing and releasing |
| `docs/ARCHITECTURE.md` | why the page is built the way it is |
| `README.md` | user-facing, English |
| `README.ru.md` | the Russian version |
