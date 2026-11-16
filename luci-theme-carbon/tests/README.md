# Tests

| Suite | Command | Needs |
|---|---|---|
| Unit: formatting, i18n, devices, ARP, IPv6, brands (`carbon.test.js`) | `npm test` | Node 18+ |
| Unit: per-device counter deltas, resets, sampling intervals and read-only collector permissions (`traffic-provider.test.js`) | `npm test` | Node 18+ |
| Unit: LuCI glue — poll pause, language list/switch, menu cache | `npm test` | Node 18+ |
| Unit: release-notes Markdown | `npm test` | Node 18+ |
| Unit: settings backend — logo upload validation (types, size, unsafe SVG) (`settings-backend.test.js`; `CARBON_TEST_SH=/bin/dash` for a strict shell) | `npm test` | Node 18+, `sh` |
| Unit: release body — one bilingual file per release, each language read through once, legacy notes (`release-notes.test.js`) | `npm test` | Node 18+, `sh` |
| Browser: preview pages, accessibility, minified build parity | `npm run test:browser` | `npm ci`, `npx playwright install chromium` |
| Installer control flow (stub apk/opkg/uci) | `npm test` | Node 18+, `sh`, `tar` |
| Installer with real apk (25.12) and opkg (24.10) | `python3 tests/installer-integration.py` | Docker, network |
| Theme templates rendered by OpenWrt's ucode | see below | Docker |
| Updater (APK and IPK) | see [online-update.md](../docs/online-update.md#maintainers) | Docker |

The browser suite also checks every bundled catalogue in the sidebar, the custom-logo hero, the settings page layout (`tests/fixtures/settings.html`), the language listbox, and the plugin adapters (DiskMan partition bar) against copied plugin markup. Table dropdown regressions use LuCI's open/closed DOM states to check that options beyond the last row receive pointer events, including plugin cells without `.cbi-value-field`, on desktop/phone and in light/dark mode against source/minified CSS. It serves the repository and a minified copy locally, runs `tests/navigation.html` at 390 × 844, loads the preview in Chinese/English × light/dark × desktop/phone (screenshots go to `.cache/screenshots/`), checks the dashboard data, the language switch, keyboard/touch behaviour of the rail and drawer, and compares computed styles of the minified release build with the sources.

Device regressions cover DHCP-disabled side routers with static or DHCP-client LAN, failed DHCP RPC calls, retained leases, gateway labels, and separate static WAN neighbours. These use the production dashboard with simulated provider responses. `CARBON_TEST_BROWSER` can point to an installed Chromium executable instead of Playwright's bundled browser. On a real router, also verify ARP reads after logging out and back in following an upgrade; an older session may lack the dashboard permissions. An IPv6-only device without a lease or local Wi-Fi association is not discoverable: this provider reads IPv4 ARP, while IPv6 addresses come from leases and host hints.

Realtime graph regressions (`node --test tests/browser/realtime.test.js`) execute pinned OpenWrt 24.10 load, bandwidth and connection plotting code with simulated RPC replies. They verify sidebar collapse/expansion, desktop/mobile resizing, continued polling, retained samples, unscaled text, hidden interface charts and the fallback without `ResizeObserver`, against source and minified theme scripts. Modern SVGs with their own `viewBox` and charts outside realtime pages are left alone. On a router, open Status → Realtime Graphs, wait for samples, collapse/expand the sidebar and resize the window; curves and time markers should fill the plot without refreshing the page.

Render the templates with the real ucode runtime:

```bash
docker run --rm --mount "type=bind,source=$PWD,target=/source,readonly" openwrt/rootfs:x86_64-24.10.8 sh /source/tests/template-render.sh
```

# Navigation and menu cache regressions

Run `node --test tests/menu-cache.test.js` from the repository root. This executes the production LuCI menu module with both menu-cache layers and checks version invalidation, retained session data, unchanged-version reuse and retry after failure. CI runs this suite before packaging.

Serve the repository locally (for example, `python -m http.server 8080 --bind 127.0.0.1`) and open `/tests/navigation.html` at a **390 × 844** viewport. All ten checks must show `PASS`. The page loads the production theme script and stylesheet and tests route tabs, nested tabs, asynchronously inserted form tabs, hidden panes, resizing, manual scrolling and focus/vertical-scroll preservation. A desktop viewport fails the viewport check because desktop tabs wrap instead of overflowing.

Also verify in a disposable LuCI environment: open a multi-page app with an active tab beyond the initial visible area, then navigate between nested pages. When testing a real upgrade, keep the existing login session, install the native package and reload. LuCI uses the package database modification time to invalidate JavaScript module URLs; merely copying files into an already loaded development instance does not reproduce this part of installation.

For signed APK and native IPK updater integration tests, see [online-update.md](../docs/online-update.md#maintainers).

Device-speed browser coverage checks upload/download values, missing records, untouched DHCP lease labels, unsupported collectors, hidden-tab suspension/resume, error backoff and mobile overflow. Real-device checks should compare network/DHCP/firewall/nlbwmon configuration before and after installing the theme, and keep the collector's existing interval and running state. An inactive or absent collector is expected to leave the speed display hidden; do not enable it as part of a theme test.

## Release notes

Run `node --test tests/markdown.test.js` to check the built-in Markdown renderer (`htdocs/luci-static/resources/carbon/markdown.js`): release-note structures, unsafe HTML/URLs, pathological input and unchanged-content polling. In LuCI, check for updates and confirm the notes render as headings, lists, links, tables and code, in both appearance modes and at 390px width. Long code/table content must scroll inside the notes; status polling must retain the reading position and text selection.
