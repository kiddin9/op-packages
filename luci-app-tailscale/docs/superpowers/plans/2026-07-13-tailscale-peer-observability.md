# Tailscale Peer Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only LuCI page that lists all Tailscale peers and lets the user manually probe whether each peer is reached directly or through DERP.

**Architecture:** Add a focused shell helper for safe `tailscale ping` probing and a new LuCI view for rendering peer state from `tailscale status --json`. Keep the existing settings, keepalive, DNS, firewall, and network lifecycle behavior unchanged.

**Tech Stack:** OpenWrt LuCI JavaScript views, `fs.exec()`, rpcd ACL JSON, POSIX shell helpers, package static shell tests.

## Global Constraints

- The feature is diagnostic only; it must not change Tailscale configuration, keepalive configuration, firewall rules, DNS settings, or network interfaces.
- Add menu path `admin/vpn/tailscale/peers` with title `Peers`, Chinese title `对端列表`, after `Interface Info` and before `Logs`.
- Page load must not automatically ping all peers.
- The first version must not include a `Probe all` button.
- Probe helper path must be `/usr/sbin/tailscale_peer_probe`.
- Probe helper accepts exactly one peer argument.
- Probe helper validates peer arguments: length 1 to 253 characters, allowed characters letters, numbers, `_`, `-`, `.`, `:`.
- Probe helper outputs JSON only.
- LuCI probe action must be read-only.
- No network reload, Tailscale restart, or firewall restart is part of this feature.

---

## File Structure

- Create `root/usr/sbin/tailscale_peer_probe`: safe command wrapper around `/usr/sbin/tailscale ping`, returning normalized JSON.
- Create `tests/tailscale_peer_probe_test.sh`: shell unit tests with a fake `tailscale` binary.
- Create `htdocs/luci-static/resources/view/tailscale/peers.js`: new read-only peer observability page.
- Modify `root/usr/share/luci/menu.d/luci-app-tailscale.json`: add `admin/vpn/tailscale/peers`.
- Modify `root/usr/share/rpcd/acl.d/luci-app-tailscale.json`: allow read-only exec of `/usr/sbin/tailscale_peer_probe`.
- Modify `tests/package_release_test.sh`: assert new files, menu, ACL, strings, and syntax coverage.
- Modify `po/templates/tailscale.pot`, `po/zh_Hans/tailscale.po`, and `po/zh_Hant/tailscale.po`: add visible labels for the new page.

---

### Task 1: Probe Helper

**Files:**
- Create: `root/usr/sbin/tailscale_peer_probe`
- Create: `tests/tailscale_peer_probe_test.sh`
- Modify: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: one CLI argument `peer`.
- Produces: JSON object with fields `peer`, `ok`, `path`, `latency_ms`, `relay`, `summary`, `raw`.

- [ ] **Step 1: Add failing package assertions**

Add these assertions to `tests/package_release_test.sh` after the existing helper file assertions:

```sh
assert_file root/usr/sbin/tailscale_peer_probe
assert_contains "tailscale_peer_probe" root/usr/share/rpcd/acl.d/luci-app-tailscale.json
assert_contains "Peer probe" root/usr/sbin/tailscale_peer_probe
```

- [ ] **Step 2: Add the failing helper test**

Create `tests/tailscale_peer_probe_test.sh`:

```sh
#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/sbin/tailscale_peer_probe"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-peer-probe-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	needle="$1"
	haystack="$2"
	case "$haystack" in
		*"$needle"*) ;;
		*) fail "expected output to contain: $needle
actual: $haystack" ;;
	esac
}

assert_not_contains() {
	needle="$1"
	haystack="$2"
	case "$haystack" in
		*"$needle"*) fail "expected output not to contain: $needle
actual: $haystack" ;;
	esac
}

mkdir -p "$TMP_DIR"

cat >"$TMP_DIR/fake-tailscale" <<'SH'
#!/bin/sh
case "$*" in
	"ping --c=1 --timeout=5s direct-peer")
		echo "pong from direct-peer (100.64.2.2) via 192.168.188.1:41641 in 12.4ms"
		exit 0
		;;
	"ping --c=1 --timeout=5s derp-peer")
		echo "pong from derp-peer (100.64.2.1) via DERP(litata) in 41.8ms"
		exit 0
		;;
	"ping --c=1 --timeout=5s weird-peer")
		echo "pong from weird-peer using new format"
		exit 0
		;;
	"ping --c=1 --timeout=5s failed-peer")
		echo "timeout waiting for pong from failed-peer" >&2
		exit 1
		;;
	*)
		echo "unexpected fake tailscale args: $*" >&2
		exit 99
		;;
esac
SH
chmod +x "$TMP_DIR/fake-tailscale"

run_probe() {
	TAILSCALE_BIN="$TMP_DIR/fake-tailscale" "$HELPER" "$@"
}

direct_output="$(run_probe direct-peer)"
assert_contains '"peer":"direct-peer"' "$direct_output"
assert_contains '"ok":true' "$direct_output"
assert_contains '"path":"direct"' "$direct_output"
assert_contains '"latency_ms":12.4' "$direct_output"
assert_contains '"summary":"direct 12.4 ms"' "$direct_output"

derp_output="$(run_probe derp-peer)"
assert_contains '"peer":"derp-peer"' "$derp_output"
assert_contains '"ok":true' "$derp_output"
assert_contains '"path":"derp"' "$derp_output"
assert_contains '"relay":"litata"' "$derp_output"
assert_contains '"latency_ms":41.8' "$derp_output"
assert_contains '"summary":"DERP litata 41.8 ms"' "$derp_output"

unknown_output="$(run_probe weird-peer)"
assert_contains '"peer":"weird-peer"' "$unknown_output"
assert_contains '"ok":true' "$unknown_output"
assert_contains '"path":"unknown"' "$unknown_output"
assert_contains '"summary":"unknown path"' "$unknown_output"

failed_output="$(run_probe failed-peer || true)"
assert_contains '"peer":"failed-peer"' "$failed_output"
assert_contains '"ok":false' "$failed_output"
assert_contains '"path":"failed"' "$failed_output"
assert_contains '"summary":"tailscale ping failed"' "$failed_output"

invalid_output="$(run_probe 'bad peer;rm -rf /' || true)"
assert_contains '"ok":false' "$invalid_output"
assert_contains '"path":"failed"' "$invalid_output"
assert_contains '"summary":"invalid peer argument"' "$invalid_output"
assert_not_contains 'rm -rf' "$invalid_output"

missing_arg_output="$("$HELPER" || true)"
assert_contains '"ok":false' "$missing_arg_output"
assert_contains '"summary":"usage: tailscale_peer_probe <peer>"' "$missing_arg_output"

echo "tailscale_peer_probe tests passed"
```

- [ ] **Step 3: Run tests to verify RED**

Run:

```sh
sh tests/package_release_test.sh
sh tests/tailscale_peer_probe_test.sh
```

Expected:

- `tests/package_release_test.sh` fails because `root/usr/sbin/tailscale_peer_probe` is missing.
- `tests/tailscale_peer_probe_test.sh` fails because the helper is missing or not executable.

- [ ] **Step 4: Implement `tailscale_peer_probe`**

Create `root/usr/sbin/tailscale_peer_probe`:

```sh
#!/bin/sh

# Peer probe for LuCI Tailscale diagnostics.

TAILSCALE_BIN="${TAILSCALE_BIN:-/usr/sbin/tailscale}"

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

json_string() {
	printf '"%s"' "$(json_escape "$1")"
}

emit_json() {
	peer="$1"
	ok="$2"
	path="$3"
	latency_ms="$4"
	relay="$5"
	summary="$6"
	raw="$7"

	printf '{'
	printf '"peer":'; json_string "$peer"; printf ','
	printf '"ok":%s,' "$ok"
	printf '"path":'; json_string "$path"; printf ','
	if [ -n "$latency_ms" ]; then
		printf '"latency_ms":%s,' "$latency_ms"
	else
		printf '"latency_ms":null,'
	fi
	printf '"relay":'; json_string "$relay"; printf ','
	printf '"summary":'; json_string "$summary"; printf ','
	printf '"raw":'; json_string "$raw"
	printf '}\n'
}

usage() {
	emit_json "" false failed "" "" "usage: tailscale_peer_probe <peer>" ""
	exit 2
}

[ "$#" -eq 1 ] || usage

peer="$1"

case "$peer" in
	""|*[!A-Za-z0-9_.:-]*)
		emit_json "" false failed "" "" "invalid peer argument" ""
		exit 2
		;;
esac

peer_len=${#peer}
if [ "$peer_len" -lt 1 ] || [ "$peer_len" -gt 253 ]; then
	emit_json "" false failed "" "" "invalid peer argument" ""
	exit 2
fi

raw="$("$TAILSCALE_BIN" ping --c=1 --timeout=5s "$peer" 2>&1)"
rc="$?"

latency_ms="$(printf '%s\n' "$raw" | sed -nE 's/.* in ([0-9]+(\.[0-9]+)?)ms.*/\1/p' | head -n 1)"
relay="$(printf '%s\n' "$raw" | sed -nE 's/.*DERP\(([^)]*)\).*/\1/p' | head -n 1)"

if [ "$rc" -ne 0 ]; then
	emit_json "$peer" false failed "" "" "tailscale ping failed" "$raw"
	exit 0
fi

if [ -n "$relay" ]; then
	if [ -n "$latency_ms" ]; then
		summary="DERP $relay $latency_ms ms"
	else
		summary="DERP $relay"
	fi
	emit_json "$peer" true derp "$latency_ms" "$relay" "$summary" "$raw"
	exit 0
fi

case "$raw" in
	*pong\ from*)
		if [ -n "$latency_ms" ]; then
			summary="direct $latency_ms ms"
		else
			summary="direct"
		fi
		emit_json "$peer" true direct "$latency_ms" "" "$summary" "$raw"
		;;
	*)
		emit_json "$peer" true unknown "" "" "unknown path" "$raw"
		;;
esac
```

Run:

```sh
chmod +x root/usr/sbin/tailscale_peer_probe
```

- [ ] **Step 5: Run helper tests to verify GREEN**

Run:

```sh
sh tests/tailscale_peer_probe_test.sh
sh tests/package_release_test.sh
```

Expected:

- `tailscale_peer_probe tests passed`
- `package release tests passed` after ACL/menu assertions are added in later tasks; at this step it may still fail on menu/ACL checks not yet implemented.

Commit after Task 1 only if helper tests pass:

```sh
git add root/usr/sbin/tailscale_peer_probe tests/tailscale_peer_probe_test.sh tests/package_release_test.sh
git commit -m "Add Tailscale peer probe helper"
```

---

### Task 2: Menu and ACL

**Files:**
- Modify: `root/usr/share/luci/menu.d/luci-app-tailscale.json`
- Modify: `root/usr/share/rpcd/acl.d/luci-app-tailscale.json`
- Modify: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: helper `/usr/sbin/tailscale_peer_probe` from Task 1.
- Produces: LuCI route `admin/vpn/tailscale/peers`, ACL exec access for the helper.

- [ ] **Step 1: Add failing static assertions**

Add to `tests/package_release_test.sh` near menu and ACL checks:

```sh
assert_contains '"admin/vpn/tailscale/peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_contains '"title": "Peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_contains '"path": "tailscale/peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_before '"admin/vpn/tailscale/interface"' '"admin/vpn/tailscale/peers"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_before '"admin/vpn/tailscale/peers"' '"admin/vpn/tailscale/log"' root/usr/share/luci/menu.d/luci-app-tailscale.json
assert_contains '"/usr/sbin/tailscale_peer_probe": [ "exec" ]' root/usr/share/rpcd/acl.d/luci-app-tailscale.json
```

- [ ] **Step 2: Run test to verify RED**

Run:

```sh
sh tests/package_release_test.sh
```

Expected: FAIL because the menu and ACL entries are not present.

- [ ] **Step 3: Add menu entry**

Edit `root/usr/share/luci/menu.d/luci-app-tailscale.json` so the child routes are:

```json
	"admin/vpn/tailscale/interface": {
		"title": "Interface Info",
		"order": 20,
		"action": {
			"type": "view",
			"path": "tailscale/interface"
		}
	},
	"admin/vpn/tailscale/peers": {
		"title": "Peers",
		"order": 25,
		"action": {
			"type": "view",
			"path": "tailscale/peers"
		}
	},
	"admin/vpn/tailscale/log": {
		"title": "Logs",
		"order": 30,
		"action": {
			"type": "view",
			"path": "tailscale/log"
		}
	}
```

- [ ] **Step 4: Add ACL entry**

Edit `root/usr/share/rpcd/acl.d/luci-app-tailscale.json` read file exec list to include:

```json
				"/usr/sbin/tailscale_peer_probe": [ "exec" ],
```

Keep it in the read section, not write.

- [ ] **Step 5: Run static test to verify GREEN**

Run:

```sh
sh tests/package_release_test.sh
```

Expected: PASS for menu and ACL assertions, unless later page assertions are not yet added.

Commit:

```sh
git add root/usr/share/luci/menu.d/luci-app-tailscale.json root/usr/share/rpcd/acl.d/luci-app-tailscale.json tests/package_release_test.sh
git commit -m "Add Tailscale peers menu and ACL"
```

---

### Task 3: Peers LuCI View

**Files:**
- Create: `htdocs/luci-static/resources/view/tailscale/peers.js`
- Modify: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: `tailscale status --json`, `/usr/sbin/tailscale_peer_probe`.
- Produces: a read-only LuCI page with peer table, filters, and per-peer probe action.

- [ ] **Step 1: Add failing static assertions**

Add to `tests/package_release_test.sh` after existing view file assertions:

```sh
assert_file htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Tailscale Peers" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "filterMode" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Advertising subnets" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "tailscale_peer_probe" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Probe" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "DERP" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Direct" htdocs/luci-static/resources/view/tailscale/peers.js
assert_not_contains "Probe all" htdocs/luci-static/resources/view/tailscale/peers.js
```

- [ ] **Step 2: Run test to verify RED**

Run:

```sh
sh tests/package_release_test.sh
```

Expected: FAIL because `peers.js` is missing.

- [ ] **Step 3: Create `peers.js`**

Create `htdocs/luci-static/resources/view/tailscale/peers.js`:

```javascript
/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Copyright (C) 2026
 */

'use strict';
'require dom';
'require fs';
'require poll';
'require ui';
'require view';

function parseStatus(stdout) {
	const parsed = JSON.parse(stdout.replace(/("\w+"):\s*(\d+)/g, '$1:"$2"'));
	const peers = Object.values(parsed.Peer || {}).map(function(peer) {
		const ip = Array.isArray(peer.TailscaleIPs) ? (peer.TailscaleIPs[0] || '') : '';
		const dnsName = (peer.DNSName || '').replace(/\.$/, '');
		const shortDnsName = dnsName.split('.', 1)[0] || '';
		const hostName = peer.HostName || '';
		const routes = Array.isArray(peer.PrimaryRoutes) ? peer.PrimaryRoutes : [];
		const name = shortDnsName || hostName || dnsName || ip;

		return {
			name: name,
			hostName: hostName,
			dnsName: dnsName,
			ip: ip,
			online: !!peer.Online,
			lastSeen: peer.LastSeen || '',
			exitNode: !!peer.ExitNodeOption,
			routes: routes,
			hasSubnetRoutes: routes.length > 0
		};
	}).filter(function(peer) {
		return !!peer.name;
	});

	peers.sort(function(a, b) {
		return a.name.localeCompare(b.name);
	});

	return peers;
}

function renderBadge(text, className) {
	return E('span', {
		class: className || 'label',
		style: 'display:inline-block;margin-right:4px;padding:1px 6px;border-radius:3px;background:#eef2f7;color:#334155;font-size:12px'
	}, text);
}

function renderProbeResult(result) {
	if (!result)
		return E('span', { style: 'color:#94a3b8' }, _('Not probed'));

	const path = result.path || 'unknown';
	const color = path === 'direct' ? 'green' : (path === 'derp' ? '#b7791f' : (path === 'failed' ? 'red' : '#64748b'));
	const label = path === 'direct' ? _('Direct') : (path === 'derp' ? _('DERP') : (path === 'failed' ? _('Failed') : _('Unknown')));
	const summary = result.summary ? ' - ' + result.summary : '';

	return E('span', { style: 'color:%s'.format(color) }, label + summary);
}

return view.extend({
	async load() {
		const res = await fs.exec('/usr/sbin/tailscale', ['status', '--json']);
		if (res.code !== 0 || !res.stdout || res.stdout.trim() === '') {
			ui.addNotification(null, E('p', {}, _('Unable to get Tailscale peer status: %s.').format(res.message || res.stderr || '')));
			return [];
		}

		try {
			return parseStatus(res.stdout);
		} catch (e) {
			ui.addNotification(null, E('p', {}, _('Error parsing Tailscale peer status: %s.').format(e.message)));
			return [];
		}
	},

	filterPeers(peers, filterMode) {
		if (filterMode === 'online')
			return peers.filter(function(peer) { return peer.online; });
		if (filterMode === 'subnets')
			return peers.filter(function(peer) { return peer.hasSubnetRoutes; });
		return peers;
	},

	async probePeer(peerName, button, resultNode) {
		button.disabled = true;
		dom.content(resultNode, E('span', {}, _('Probing...')));

		try {
			const res = await fs.exec('/usr/sbin/tailscale_peer_probe', [peerName]);
			const data = JSON.parse(res.stdout || '{}');
			dom.content(resultNode, renderProbeResult(data));
		} catch (e) {
			dom.content(resultNode, renderProbeResult({
				path: 'failed',
				summary: String(e.message || e)
			}));
		} finally {
			button.disabled = false;
		}
	},

	renderRows(peers, filterMode) {
		const filtered = this.filterPeers(peers, filterMode);

		if (!filtered.length)
			return E('tr', { class: 'tr' }, E('td', { class: 'td left', colspan: '7' }, _('No peers found')));

		return filtered.map(function(peer) {
			const resultNode = E('span', {}, renderProbeResult(null));
			const button = E('button', {
				class: 'btn cbi-button cbi-button-action',
				click: ui.createHandlerFn(this, function() {
					return this.probePeer(peer.name, button, resultNode);
				})
			}, _('Probe'));

			const role = [];
			if (peer.exitNode)
				role.push(renderBadge(_('Exit node')));
			if (peer.hasSubnetRoutes)
				role.push(renderBadge(_('Advertising subnets')));

			return E('tr', { class: 'tr' }, [
				E('td', { class: 'td left' }, peer.name),
				E('td', { class: 'td left' }, peer.ip || '-'),
				E('td', { class: 'td left' }, peer.online ? _('Online') : _('Offline')),
				E('td', { class: 'td left' }, peer.lastSeen || '-'),
				E('td', { class: 'td left' }, role.length ? role : '-'),
				E('td', { class: 'td left' }, peer.routes.length ? peer.routes.join(', ') : '-'),
				E('td', { class: 'td left' }, [button, E('span', { style: 'margin-left:8px' }, resultNode)])
			]);
		}, this);
	},

	renderContent(peers) {
		let filterMode = 'all';
		const rowsBody = E('tbody');

		const updateRows = L.bind(function() {
			dom.content(rowsBody, this.renderRows(peers, filterMode));
		}, this);

		const filterSelect = E('select', {
			change: function(ev) {
				filterMode = ev.target.value;
				updateRows();
			}
		}, [
			E('option', { value: 'all' }, _('All')),
			E('option', { value: 'online' }, _('Online')),
			E('option', { value: 'subnets' }, _('Advertising subnets'))
		]);

		updateRows();

		return E('div', {}, [
			E('div', { style: 'margin-bottom:10px' }, [
				E('label', { style: 'margin-right:8px' }, _('Filter')),
				filterSelect
			]),
			E('table', { class: 'table' }, [
				E('thead', {}, E('tr', { class: 'tr table-titles' }, [
					E('th', { class: 'th left' }, _('Name')),
					E('th', { class: 'th left' }, _('Tailnet IP')),
					E('th', { class: 'th left' }, _('Status')),
					E('th', { class: 'th left' }, _('Last Seen')),
					E('th', { class: 'th left' }, _('Role')),
					E('th', { class: 'th left' }, _('Advertised Subnets')),
					E('th', { class: 'th left' }, _('Probe'))
				])),
				rowsBody
			])
		]);
	},

	pollData(container) {
		poll.add(async () => {
			const data = await this.load();
			dom.content(container, this.renderContent(data));
		});
	},

	render(data) {
		const content = E([], [
			E('h2', { class: 'content' }, _('Tailscale Peers')),
			E('div', { class: 'cbi-map-descr' }, _('View all peers and manually probe whether traffic is direct or relayed through DERP.')),
			E('div')
		]);
		const container = content.lastElementChild;

		dom.content(container, this.renderContent(data));
		this.pollData(container);

		return content;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
```

- [ ] **Step 4: Run JavaScript syntax check**

Run:

```sh
node --check htdocs/luci-static/resources/view/tailscale/peers.js
```

Expected: exit 0.

- [ ] **Step 5: Run package test**

Run:

```sh
sh tests/package_release_test.sh
```

Expected: PASS for new page assertions after translation assertions are added in Task 4.

Commit:

```sh
git add htdocs/luci-static/resources/view/tailscale/peers.js tests/package_release_test.sh
git commit -m "Add Tailscale peers LuCI view"
```

---

### Task 4: Translations and Package Verification

**Files:**
- Modify: `po/templates/tailscale.pot`
- Modify: `po/zh_Hans/tailscale.po`
- Modify: `po/zh_Hant/tailscale.po`
- Modify: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: visible strings from `peers.js`.
- Produces: Chinese labels for the peer observability page.

- [ ] **Step 1: Add failing translation assertions**

Add to `tests/package_release_test.sh` near other translation assertions:

```sh
assert_contains 'msgid "Peers"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "对端列表"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Tailscale Peers"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "Tailscale 对端"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Direct"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "直连"' po/zh_Hans/tailscale.po
assert_contains 'msgid "DERP"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "DERP 中继"' po/zh_Hans/tailscale.po
assert_contains 'msgid "Advertising subnets"' po/zh_Hans/tailscale.po
assert_contains 'msgstr "发布网段"' po/zh_Hans/tailscale.po
```

- [ ] **Step 2: Run test to verify RED**

Run:

```sh
sh tests/package_release_test.sh
```

Expected: FAIL because translation entries are missing.

- [ ] **Step 3: Add template entries**

Append these entries to `po/templates/tailscale.pot` if the project does not regenerate POT automatically:

```po
msgid "Peers"
msgstr ""

msgid "Tailscale Peers"
msgstr ""

msgid "View all peers and manually probe whether traffic is direct or relayed through DERP."
msgstr ""

msgid "Unable to get Tailscale peer status: %s."
msgstr ""

msgid "Error parsing Tailscale peer status: %s."
msgstr ""

msgid "No peers found"
msgstr ""

msgid "Not probed"
msgstr ""

msgid "Probing..."
msgstr ""

msgid "Probe"
msgstr ""

msgid "Direct"
msgstr ""

msgid "DERP"
msgstr ""

msgid "Failed"
msgstr ""

msgid "Unknown"
msgstr ""

msgid "Filter"
msgstr ""

msgid "All"
msgstr ""

msgid "Tailnet IP"
msgstr ""

msgid "Last Seen"
msgstr ""

msgid "Role"
msgstr ""

msgid "Exit node"
msgstr ""

msgid "Advertising subnets"
msgstr ""

msgid "Advertised Subnets"
msgstr ""
```

- [ ] **Step 4: Add Simplified Chinese entries**

Append to `po/zh_Hans/tailscale.po`:

```po
msgid "Peers"
msgstr "对端列表"

msgid "Tailscale Peers"
msgstr "Tailscale 对端"

msgid "View all peers and manually probe whether traffic is direct or relayed through DERP."
msgstr "查看全部对端，并手动探测流量是直连还是通过 DERP 中继。"

msgid "Unable to get Tailscale peer status: %s."
msgstr "无法获取 Tailscale 对端状态：%s。"

msgid "Error parsing Tailscale peer status: %s."
msgstr "解析 Tailscale 对端状态失败：%s。"

msgid "No peers found"
msgstr "没有找到对端"

msgid "Not probed"
msgstr "未探测"

msgid "Probing..."
msgstr "探测中..."

msgid "Probe"
msgstr "探测"

msgid "Direct"
msgstr "直连"

msgid "DERP"
msgstr "DERP 中继"

msgid "Failed"
msgstr "失败"

msgid "Unknown"
msgstr "未知"

msgid "Filter"
msgstr "筛选"

msgid "All"
msgstr "全部"

msgid "Tailnet IP"
msgstr "Tailnet IP"

msgid "Last Seen"
msgstr "最后在线"

msgid "Role"
msgstr "角色"

msgid "Exit node"
msgstr "出口节点"

msgid "Advertising subnets"
msgstr "发布网段"

msgid "Advertised Subnets"
msgstr "已发布网段"
```

- [ ] **Step 5: Add Traditional Chinese entries**

Append to `po/zh_Hant/tailscale.po`:

```po
msgid "Peers"
msgstr "對端列表"

msgid "Tailscale Peers"
msgstr "Tailscale 對端"

msgid "View all peers and manually probe whether traffic is direct or relayed through DERP."
msgstr "查看全部對端，並手動探測流量是直連還是透過 DERP 中繼。"

msgid "Unable to get Tailscale peer status: %s."
msgstr "無法取得 Tailscale 對端狀態：%s。"

msgid "Error parsing Tailscale peer status: %s."
msgstr "解析 Tailscale 對端狀態失敗：%s。"

msgid "No peers found"
msgstr "沒有找到對端"

msgid "Not probed"
msgstr "未探測"

msgid "Probing..."
msgstr "探測中..."

msgid "Probe"
msgstr "探測"

msgid "Direct"
msgstr "直連"

msgid "DERP"
msgstr "DERP 中繼"

msgid "Failed"
msgstr "失敗"

msgid "Unknown"
msgstr "未知"

msgid "Filter"
msgstr "篩選"

msgid "All"
msgstr "全部"

msgid "Tailnet IP"
msgstr "Tailnet IP"

msgid "Last Seen"
msgstr "最後在線"

msgid "Role"
msgstr "角色"

msgid "Exit node"
msgstr "出口節點"

msgid "Advertising subnets"
msgstr "發布網段"

msgid "Advertised Subnets"
msgstr "已發布網段"
```

- [ ] **Step 6: Run package test**

Run:

```sh
sh tests/package_release_test.sh
```

Expected: `package release tests passed`.

Commit:

```sh
git add po/templates/tailscale.pot po/zh_Hans/tailscale.po po/zh_Hant/tailscale.po tests/package_release_test.sh
git commit -m "Add peer observability translations"
```

---

### Task 5: Full Verification

**Files:**
- Test only.

**Interfaces:**
- Consumes: all files from Tasks 1-4.
- Produces: verified branch ready for PR review.

- [ ] **Step 1: Run all shell tests**

Run:

```sh
sh tests/package_release_test.sh
sh tests/tailscale_peer_probe_test.sh
sh tests/tailscale_adguard_dns_switch_test.sh
sh tests/tailscale_helper_network_cleanup_test.sh
sh tests/tailscale_keepalive_test.sh
```

Expected:

```text
package release tests passed
tailscale_peer_probe tests passed
tailscale_adguard_dns_switch tests passed
tailscale_helper network cleanup tests passed
tailscale_keepalive resolver tests passed
```

- [ ] **Step 2: Run JavaScript syntax checks**

Run:

```sh
node --check htdocs/luci-static/resources/view/tailscale/setting.js
node --check htdocs/luci-static/resources/view/tailscale/interface.js
node --check htdocs/luci-static/resources/view/tailscale/log.js
node --check htdocs/luci-static/resources/view/tailscale/peers.js
```

Expected: all commands exit 0.

- [ ] **Step 3: Run shell syntax checks**

Run:

```sh
find root -type f \( -path '*/init.d/*' -o -path '*/sbin/*' -o -path '*/uci-defaults/*' \) -exec sh -n {} \;
```

Expected: exit 0.

- [ ] **Step 4: Run whitespace check**

Run:

```sh
git diff --check
```

Expected: exit 0.

- [ ] **Step 5: Inspect final diff**

Run:

```sh
git diff --stat origin/main...HEAD
git diff --name-only origin/main...HEAD
```

Expected: changed files include the helper, peer view, menu, ACL, translations, and tests. No unrelated OpenWrt runtime config files should be changed.

- [ ] **Step 6: Push**

Run:

```sh
git push
```

Expected: current PR branch updates successfully.

---

### Task 6: Office OpenWrt Hot Deployment Check

**Files:**
- Remote deployment only after user confirms `ok` for OpenWrt write operations.

**Interfaces:**
- Consumes: verified files from Tasks 1-5.
- Produces: office OpenWrt can load `Peers` page and probe one peer.

- [ ] **Step 1: Read infrastructure status before remote operations**

Run from `/Users/jearton/projects/litata/infra-docs`:

```sh
sed -n '1,260p' docs/infra/litata-current-infrastructure-status.md
```

Expected: read current OpenWrt, Headscale, DNS, and route-sync context.

- [ ] **Step 2: Confirm write plan with user**

Ask the user to approve this exact write plan:

```text
1. Backup current LuCI view/menu/ACL/helper files under /tmp.
2. Upload peers.js, tailscale_peer_probe, menu JSON, and ACL JSON.
3. Do not reload network, do not restart Tailscale, do not restart firewall.
4. Restart rpcd only if LuCI ACL does not pick up the new helper permission.
5. Verify static file over HTTP and run tailscale_peer_probe against one known peer.
6. Rollback by restoring /tmp backups.
```

Do not run remote write commands until the user replies `ok`.

- [ ] **Step 3: Backup remote files**

After user approval, run:

```sh
/usr/bin/expect <<'EXPECT'
set timeout 60
set password {password}
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.100.1 "set -eu; ts=\$(date +%Y%m%d-%H%M%S); for f in /www/luci-static/resources/view/tailscale/peers.js /usr/share/luci/menu.d/luci-app-tailscale.json /usr/share/rpcd/acl.d/luci-app-tailscale.json /usr/sbin/tailscale_peer_probe; do [ -e \$f ] && cp \$f /tmp/\$(basename \$f).bak-\$ts || true; done; echo BACKUP_TS=\$ts"
expect {
  -re "password:" { send "$password\r"; exp_continue }
  eof
}
EXPECT
```

Expected: prints `BACKUP_TS=...`.

- [ ] **Step 4: Upload files**

Run `scp -O` for:

```text
htdocs/luci-static/resources/view/tailscale/peers.js -> root@192.168.100.1:/www/luci-static/resources/view/tailscale/peers.js
root/usr/sbin/tailscale_peer_probe -> root@192.168.100.1:/usr/sbin/tailscale_peer_probe
root/usr/share/luci/menu.d/luci-app-tailscale.json -> root@192.168.100.1:/usr/share/luci/menu.d/luci-app-tailscale.json
root/usr/share/rpcd/acl.d/luci-app-tailscale.json -> root@192.168.100.1:/usr/share/rpcd/acl.d/luci-app-tailscale.json
```

Then run:

```sh
ssh root@192.168.100.1 "chmod 0755 /usr/sbin/tailscale_peer_probe; chmod 0644 /www/luci-static/resources/view/tailscale/peers.js /usr/share/luci/menu.d/luci-app-tailscale.json /usr/share/rpcd/acl.d/luci-app-tailscale.json"
```

- [ ] **Step 5: Verify served static view**

Run:

```sh
curl -fsS --max-time 10 http://192.168.100.1/luci-static/resources/view/tailscale/peers.js | rg -n "Tailscale Peers|tailscale_peer_probe|Probe|DERP|Direct"
```

Expected: all strings are present.

- [ ] **Step 6: Verify helper with known peer**

Run:

```sh
ssh root@192.168.100.1 "/usr/sbin/tailscale_peer_probe hzsls-openwrt"
```

Expected: JSON with `"path":"direct"`, `"path":"derp"`, `"path":"unknown"`, or `"path":"failed"`. The command must output JSON, not shell errors.

- [ ] **Step 7: Verify LuCI menu visibility**

Open:

```text
http://192.168.100.1/cgi-bin/luci/admin/vpn/tailscale/peers
```

Expected: page loads and shows the peer table.

If LuCI returns an ACL or not-found error, restart only rpcd:

```sh
/etc/init.d/rpcd restart
```

Then repeat Step 7.

---

## Self-Review

- Spec coverage: all spec requirements are mapped to Tasks 1-6.
- Placeholder scan: no unfinished placeholder markers are intentionally left.
- Type consistency: helper JSON fields are consistent across helper, tests, and LuCI view.
- Scope check: no `Probe all`, no keepalive changes, no Headscale API integration, no historical charts.
