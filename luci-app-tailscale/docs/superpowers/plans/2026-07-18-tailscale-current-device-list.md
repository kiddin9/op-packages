# Tailscale Current Device List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the current OpenWrt device in the existing user-grouped Tailscale device list and label its probe cell as “Current device”.

**Architecture:** Extend `parseStatus()` to normalize the top-level Tailscale `Self` object through the same mapping used for `Peer` entries, adding an `isSelf` marker. Keep grouping, filtering, and pagination unchanged; branch only when rendering the last column so the current device cannot be probed.

**Tech Stack:** LuCI JavaScript, Tailscale `status --json`, Node.js behavior tests, gettext PO translations, shell package checks.

## Global Constraints

- The current device must be grouped by `Self.UserID` under the same user heading as its other devices.
- The current device participates in existing status, subnet, and pagination behavior.
- The probe column displays “Current device” and never invokes the probe helper for `Self`.
- A missing `Self` object remains compatible with the existing peer-only response.
- Existing uncommitted `.superpowers/sdd/task-*-report.md` files must not be modified or committed.

---

### Task 1: Normalize and render the current device

**Files:**
- Modify: `tests/peers_pagination_test.js`
- Modify: `htdocs/luci-static/resources/view/tailscale/peers.js`

**Interfaces:**
- Consumes: Tailscale status JSON containing optional top-level `Self`, `Peer`, and `User` objects.
- Produces: `parseStatus(stdout)` entries with `isSelf: boolean`; the current device row renders a non-interactive “Current device” probe cell.

- [ ] **Step 1: Write the failing normalization test**

Add a `Self` object to the existing status fixture and assert that it is returned with its user metadata and marker:

```javascript
Self: {
	ID: 'self-node',
	HostName: 'hz-office-openwrt',
	DNSName: 'hz-office-openwrt.example.ts.net.',
	TailscaleIPs: ['100.64.2.15'],
	PrimaryRoutes: ['192.168.100.0/24'],
	UserID: 2,
	Online: true
}
```

```javascript
const selfPeer = normalizedPeers.find(item => item.isSelf);
assert(selfPeer && selfPeer.name === 'hz-office-openwrt', 'Self should be normalized into the device list');
assert(selfPeer.userName === 'Alpha User', 'Self should resolve its owner through UserID');
assert(selfPeer.routes.join(',') === '192.168.100.0/24', 'Self should preserve its advertised routes');
```

- [ ] **Step 2: Write the failing render test**

Render a list containing a current-device entry and verify that the serialized tree contains `Current device` but no `Probe` action for that row:

```javascript
const currentDevice = {
	id: 'self-node',
	name: 'hz-office-openwrt',
	ip: '100.64.2.15',
	userKey: '2',
	userName: 'Alpha User',
	userLoginName: 'alpha@example.test',
	online: true,
	lastSeen: '-',
	exitNode: false,
	routes: ['192.168.100.0/24'],
	hasSubnetRoutes: true,
	probeTarget: '100.64.2.15',
	isSelf: true
};
```

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```bash
node tests/peers_pagination_test.js
```

Expected: FAIL because `parseStatus()` ignores `Self` and the row renderer has no current-device branch.

- [ ] **Step 4: Implement shared status normalization**

In `parseStatus()`, introduce a local `appendPeer(peerId, peer, isSelf)` helper containing the existing normalization logic. Call it once for `parsed.Self` and once per `parsed.Peer` entry. Include:

```javascript
isSelf: !!isSelf
```

Use a stable current-device identifier derived from `Self.ID`, falling back to `Self.PublicKey`, `Self.HostName`, and finally `self`.

- [ ] **Step 5: Render a non-interactive current-device probe cell**

In the device-row loop, branch before creating the probe button:

```javascript
var probeCell = peer.isSelf
	? E('span', { style: 'font-weight:600;color:#475569' }, _('Current device'))
	: E('div', {
		style: 'display:flex;align-items:center;gap:8px;flex-wrap:wrap'
	}, [button, resultNode]);
```

Guard `probePeer()` with `if (peer.isSelf || !peer.online) return;` as defense in depth.

- [ ] **Step 6: Run the focused test and verify GREEN**

Run:

```bash
node tests/peers_pagination_test.js
```

Expected: `peers pagination and behavior tests passed`.

### Task 2: Add translations and package regression coverage

**Files:**
- Modify: `po/templates/tailscale.pot`
- Modify: `po/zh_Hans/tailscale.po`
- Modify: `po/zh_Hant/tailscale.po`
- Modify: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: gettext key `Current device` emitted by `peers.js`.
- Produces: Simplified Chinese `当前设备`, Traditional Chinese `目前設備`, and package-level assertions for the new behavior.

- [ ] **Step 1: Add failing package assertions**

Add checks requiring the renderer marker and translations:

```bash
assert_contains "peer.isSelf" htdocs/luci-static/resources/view/tailscale/peers.js
assert_contains "Current device" htdocs/luci-static/resources/view/tailscale/peers.js
assert_po_entry "Current device" "当前设备" po/zh_Hans/tailscale.po
assert_po_entry "Current device" "目前設備" po/zh_Hant/tailscale.po
```

- [ ] **Step 2: Run the package test and verify RED**

Run:

```bash
sh tests/package_release_test.sh
```

Expected: FAIL because the gettext entries do not exist yet.

- [ ] **Step 3: Add gettext entries**

Add `Current device` to the POT template and both PO catalogs:

```po
msgid "Current device"
msgstr "当前设备"
```

```po
msgid "Current device"
msgstr "目前設備"
```

- [ ] **Step 4: Run focused and complete verification**

Run:

```bash
node tests/peers_pagination_test.js
sh tests/package_release_test.sh
for test_file in tests/*_test.sh; do sh "$test_file"; done
git diff --check
```

Expected: all commands exit `0`, the behavior test prints its success message, and no whitespace errors are reported.

- [ ] **Step 5: Commit only feature files**

```bash
git add htdocs/luci-static/resources/view/tailscale/peers.js \
  tests/peers_pagination_test.js tests/package_release_test.sh \
  po/templates/tailscale.pot po/zh_Hans/tailscale.po po/zh_Hant/tailscale.po \
  docs/superpowers/plans/2026-07-18-tailscale-current-device-list.md
git commit -m "feat: show current device in peer list"
```
