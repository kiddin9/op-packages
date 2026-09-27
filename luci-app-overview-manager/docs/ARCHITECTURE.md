# Implementation notes

Load-bearing facts about LuCI and OpenWrt that this package depends on, why the
code is shaped the way it is, and how to re-verify each claim. None of it is
derivable from this repository alone: the upstream behaviour lives in
`luci-base`, `luci-mod-status` and the active theme.

Upstream references are paths inside `openwrt/luci`.

## The Overview page rebuilds itself every poll cycle

`luci-mod-status/htdocs/luci-static/resources/view/status/index.js` builds one
`.cbi-section` per include **once**, in `render()`, and then on every poll cycle
calls each include's `load()` and `render()` again and replaces the section
*content* through `dom.content`. The interval is `luci.main.pollinterval`,
default 5 seconds.

Two consequences drive the design of `luci/overview.js`:

1. **Never move a section unless the order actually changed.** Re-appending a
   node re-inserts it, and re-insertion restarts its CSS animations. The theme
   puts `fade-in` on every revealed section — `.fade-in { animation: fade-in
   .4s ease }` with `opacity` `0 → 1` in
   `themes/luci-theme-bootstrap/htdocs/luci-static/bootstrap/cascade.css` — so
   re-appending all sections on each cycle makes the whole page flash every
   five seconds. `applyLayout()` therefore compares the wanted order against
   the live DOM order and touches nothing when they match.

2. **Never clear a visibility class and re-add it.** Dropping
   `overview-manager-hidden` from every section and then re-adding it exposes
   every hidden widget for a frame. Use `classList.toggle(name, force)`, which
   only mutates when the state really changes.

`scripts/test-overview-ui.js` pins both: it counts `appendChild` calls and class
mutations across a second identical render and fails if either is non-zero.
Reverting either property makes it fail, which is worth re-checking if the test
is ever refactored.

`dom.content` (in `luci.js`) removes all children and appends the new ones in
one synchronous task, so replacing our own container each cycle cannot paint an
intermediate state. Only node *moves* and class churn are visible.

`load()` caches its result for the lifetime of the page. The saved layout cannot
change while the Overview page stays open, and the alternative is two helper
process spawns every five seconds forever. A failed read is deliberately not
cached, so a transient rpcd error retries on the next cycle instead of pinning
an empty widget list for the session.

## Widget-to-section mapping is positional and order-sensitive

There is no attribute tying a rendered section to the include that produced it,
so the mapping is by index: the *n*-th `.cbi-section` belongs to the *n*-th
include. `data-overview-widget` is stamped on first use and reused afterwards.

`index.js` requires its includes as `view.status.include.<name>` and sorts
**those module names**, so the `.js` suffix takes no part in the ordering. A
file-name sort is not the same sort: `-` is 0x2D and `.` is 0x2E, so plain file
names order `20_x-y.js` before `20_x.js`, while module names order `20_x` before
`20_x-y`. One such pair shifts every later widget onto the wrong section, and
the visible effect is that the wrong card is hidden or moved.

`common.compareWidgets` exists for exactly this and must stay code-unit based.
`localeCompare` would reorder per browser locale and reintroduce the bug in a
locale-dependent way.

Two further constraints follow from the same mechanism:

- The include count must equal the section count, or `applyLayout()` gives up
  after eight retries and silently does nothing. `index.js` filters
  `fs.list` entries by `type == 'file'`, so an include installed as a symlink
  would be skipped there while the shell helper's `[ -f ]` follows it and counts
  it. Nothing in the tree creates such a symlink today; if the layout ever stops
  applying on a specific device, check this first.
- `title` must be non-empty and stable. `index.js` uses the include title as the
  `localStorage` key for its own per-browser Hide button (`includes[i].id =
  title`), so an empty title claims the empty key and collides with any other
  untitled include. It is deliberately not wrapped in `_()`: a translated title
  would change that key whenever the interface language changes.

## Client-side translation

The chain is not obvious and is easy to get subtly wrong.

- The global `_()` is defined in `luci-base/htdocs/luci-static/resources/cbi.js`,
  not in `luci.js`. It is `TR[sfh(trimws(s))] || s`.
- `window.TR` is emitted by `admin/translations/<lang>`
  (`luci-base/ucode/controller/admin/index.uc`), which the theme header loads on
  every page, including the login page. It is a flat map of eight-hex-digit
  hashes to strings, merged from **every** `*.<lang>.lmo` in
  `/usr/lib/lua/luci/i18n`.
- The lookup key is the hash of the *whitespace-normalised* msgid: `trimws` in
  `cbi.js` trims and collapses runs of space, tab and newline. `po2lmo` hashes
  the **raw** msgid from the catalog. **Therefore msgids must already be
  normalised** — one line, single spaces, no leading or trailing whitespace — or
  the runtime lookup misses and the string silently stays English.
- Because all catalogs share one namespace in an unspecified merge order, a
  string that `luci-base` also translates must either be left out or given the
  identical translation. `Show`, `Move up` and `Move down` are in that category
  and use the exact `luci-base` wording so the collision cannot matter.

`scripts/test-po2lmo.py` enforces the normalisation rule, the catalog-to-source
correspondence in both directions, and round-trips every translation through the
real hash and a minimal LMO reader.

### Registering the language is mandatory

Shipping a catalog is not enough. `determine_request_language()` in
`luci-base/ucode/dispatcher.uc` only accepts a language that exists in
`luci.languages`; with `luci.main.lang=auto` and no matching entry it falls
through to `en`. A router with no `luci-i18n-*` package installed has an empty
`luci.languages`, so the catalog would never be selected.

`openwrt/files/etc/uci-defaults/luci-app-overview-manager` adds the entry, the
same way `luci.mk` generates it for stock `luci-i18n-*` packages. Because this
package defines its own `postinst`, the default handler that drains
`/etc/uci-defaults` does not run, so `postinst` invokes the script itself and
removes it on success; otherwise the language would only appear after the next
reboot.

Verify on a device:

```sh
wget -qO- 'http://127.0.0.1/cgi-bin/luci/admin/translations/ru' | head -c 400
uci show luci.languages
```

and that content negotiation resolves as expected:

```sh
curl -s -H 'Accept-Language: ru' http://<router>/cgi-bin/luci/ | grep -o '<html lang="[^"]*"'
```

### `scripts/po2lmo.py` must stay byte-compatible

It reimplements `luci-base/src/po2lmo.c`. Format details that are easy to lose:
values are written first, each padded to a four-byte boundary; the index of
16-byte big-endian records follows, sorted by key hash; the file ends with the
total size of the value blob. The `val_id` field does not hold a hash, it holds
the plural count. Entries whose key and value hash identically are omitted so
the reader falls back to the source string. `extract_string` unescapes only `\"`
and `\\` — `\n` stays two literal characters, which is what makes the header's
`Plural-Forms` parsing work. An empty catalog produces no file at all.

To re-verify after any change, build the reference tool and diff its output. The
reader needs a generated parser header that is not required for writing, so an
empty stub is enough:

```sh
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/openwrt/luci
cd luci && git sparse-checkout set modules/luci-base && git checkout master
cd .. && mkdir -p oracle/lib
cp luci/modules/luci-base/src/po2lmo.c oracle/
sed -n '1,72p' luci/modules/luci-base/src/lib/lmo.c > oracle/lib/sfh.c
cp luci/modules/luci-base/src/lib/lmo.h oracle/lib/
: > oracle/lib/plural_formula.h
cc -O1 -Ioracle/lib -o oracle/po2lmo oracle/po2lmo.c oracle/lib/sfh.c

PO2LMO_REFERENCE=$PWD/oracle/po2lmo python3 scripts/test-po2lmo.py
```

The same binary can be diffed against every catalog in `luci-base/po/*/*.po` as
a broader check; all of them currently match byte for byte.

## Static resources are cached without a cache-buster

`L.require` builds module URLs as
`<base>/<path>.js` plus `?v=<env.resource_version>` **only when that field is
set**, and the OpenWrt 25.12 page template does not set it — it versions
`luci.js` alone. uhttpd serves the files with `ETag` and `Last-Modified` but no
`Cache-Control`, so browsers apply heuristic freshness and can reuse a stale
copy for a long time.

Practical effect: after changing anything under
`/www/luci-static/resources/`, a normal reload may keep running the old code. A
reload that bypasses the cache is required — in Safari that is
`Cmd+Option+R` ("Reload Page From Origin"); `Cmd+Shift+R` does nothing there.
Confirm which code is live by reading the section titles, since a stale include
renders its section heading differently:

```js
[...document.querySelectorAll('.cbi-section')].map(s => s.querySelector('h3')?.textContent.trim())
```

## Shell that ships to the router runs under BusyBox

The test suite runs on GNU coreutils, which silently accepts constructs a stock
OpenWrt image does not have: `sort -o`, `base64`, `grep -P` and `find -printf`
among them. `scripts/check-busybox-compat.sh` scans the **staged package tree**
rather than the sources, so the checked set cannot drift from what is installed;
it also runs `busybox ash -n` on each script when a `busybox` binary is present,
which no pattern list can replace.

Four files reach the router: `CONTROL/postinst`, `CONTROL/prerm`,
`etc/uci-defaults/luci-app-overview-manager` and `usr/libexec/overview-manager`.

## Working against a real device

- OpenWrt has no `sftp-server`, so `scp` fails. Stream instead:
  `ssh <host> 'cat > /path' < localfile`.
- `apk-tools` on the device has no `mkpkg`, and OpenWrt 25.12 cannot install an
  `.ipk`. Building a package needs the SDK; for a quick check, deploy the payload
  files and compare checksums.
- ACL changes need `/etc/init.d/rpcd reload`, which drops active LuCI sessions.
- Name the package in every transaction. A blanket upgrade is never appropriate
  on a live router; `scripts/check-apk-trust.sh` fails the build if one appears
  in a script or in the documentation.
- Verify a published package with the device's own `apk` and the tracked public
  key, and confirm it is rejected without it:

  ```sh
  apk verify --keys-dir <dir-with-public-key> <package>.apk
  ```
