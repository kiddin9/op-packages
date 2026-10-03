# RMM LuCI theme

`luci-theme-rmm` provides a compact dark LuCI shell matching `DESIGN.md`.
It uses the upstream Bootstrap LuCI menu data and login module, so the official
`luci-theme-bootstrap` package is a dependency. At 900 px and wider, the menu
is a scrollable sidebar; below 600 px, its primary sections move to a fixed
bottom bar with touch-sized submenus. The tablet layout keeps the top menu.
The active page is marked in the menu, and the same LuCI links and access
permissions are preserved. The theme does not change any network settings and
does not become active on installation.

Install the package from the signed RMM package feed, then select **RMM** in
**System → Language and Style**. To switch by SSH:

```sh
uci set luci.main.mediaurlbase='/luci-static/rmm'
uci commit luci
```

Refresh LuCI and verify the login page, navigation, forms, and mobile layout.
Check direct links and submenus with mouse, touch, and keyboard at 320, 390,
768, 1024, and 1440 px. On mobile and tablet, Escape closes an open submenu and restores focus to its trigger. Tablet submenus open on keyboard focus; Tab and Shift+Tab follow the existing links. Click or touch also toggles a submenu. At 200% zoom,
the bottom bar uses two rows when the CSS viewport is narrower than 300 px.
To return to the default theme:

```sh
uci set luci.main.mediaurlbase='/luci-static/bootstrap'
uci commit luci
```

The theme is based on the Apache-2.0 licensed LuCI Bootstrap templates.

## P2 components

The theme owns responsive rules based on viewport width. Bootstrap mobile.css
is no longer imported, so phone screen size does not change the CSS cascade.
Below 600 px, supported data tables show labelled stacked records; header
content and sorting controls remain in a compact scroll row. Read-only tables
have their own keyboard-focusable scroll region. Editable tables keep their
native nodes, events and visible overflow for dropdowns/tooltips. Labels are
refreshed when LuCI replaces rows during polling.

Diagnostics command groups stack on mobile and have visible destination labels.
Normal controls use 36 px; login, mobile and coarse-pointer controls use 42 px.
Tabs scroll locally; technical output wraps or scrolls inside its own component.
Open dropdowns stay inside the viewport and account for the mobile navigation.
Non-login dialogs have bounded height, accessible titles, Tab containment and
focus restoration. Native LuCI save/cancel/Escape handlers remain responsible
for their actions. No configuration writes or additional RPC calls are added.

After upgrade, perform a full browser reload and check the base LuCI entry URL,
DHCP, interfaces, Wi-Fi, firewall, startup, DDNS, diagnostics (without running
commands), dropdowns and a safe dialog at 320/390/768/1024/1440 px. Also check
physical touch devices, 200% zoom and the same widgets in installed third-party
packages. DOM tests do not replace this device validation.
