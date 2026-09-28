# Tailscale Peer Observability Design

## Goal

Add a LuCI page for observing all Tailscale peers and manually probing whether traffic to a peer is direct or relayed through DERP.

This feature is diagnostic only. It does not change Tailscale configuration, keepalive configuration, firewall rules, DNS settings, or network interfaces.

## User Experience

Add a top-level Tailscale child page:

- Menu path: `admin/vpn/tailscale/peers`
- Title: `Peers`
- Chinese title: `对端列表`
- Order: after `Interface Info`, before `Logs`

The page shows a compact table of every peer from `tailscale status --json`.

Columns:

- Name: short DNS name when available, otherwise host name, DNS name, or Tailnet IP.
- Tailnet IP: first `TailscaleIPs` value.
- Status: online or offline.
- Last Seen: `LastSeen` when available.
- Role: badges for exit node option and advertised subnet routes.
- Advertised Subnets: `PrimaryRoutes`, shown as comma-separated CIDRs.
- Probe: a button for one-shot connectivity probing.
- Probe Result: latest result for that row.

Filters:

- All
- Online
- Advertising subnets

Each row has a `Probe` button. Clicking it probes only that peer and updates that row. Page load does not automatically ping all peers.

Probe result labels:

- `Direct`: Tailscale ping reached the peer directly.
- `DERP`: Tailscale ping used DERP relay.
- `Failed`: the probe command failed or the peer did not answer.
- `Unknown`: output did not match known direct or DERP patterns.

The first version does not include a `Probe all` button. That avoids accidental bursts of probes on larger tailnets.

## Data Flow

The LuCI view loads status data using:

```sh
/usr/sbin/tailscale status --json
```

The view parses peers in JavaScript and renders the table. It also polls status periodically, matching existing page patterns.

Manual probes use a helper command:

```sh
/usr/sbin/tailscale_peer_probe <peer>
```

The view calls the helper via `fs.exec()`. The helper validates the peer argument, runs `tailscale ping`, parses the output, and prints JSON.

Example helper output:

```json
{
  "peer": "hzsls-openwrt",
  "ok": true,
  "path": "direct",
  "latency_ms": 12.4,
  "summary": "direct 12.4 ms",
  "raw": "pong from hzsls-openwrt ..."
}
```

For DERP:

```json
{
  "peer": "jiaxing-idc-wg",
  "ok": true,
  "path": "derp",
  "latency_ms": 41.8,
  "relay": "litata",
  "summary": "DERP litata 41.8 ms",
  "raw": "pong from jiaxing-idc-wg via DERP(litata) ..."
}
```

For failure:

```json
{
  "peer": "missing-peer",
  "ok": false,
  "path": "failed",
  "summary": "tailscale ping failed",
  "raw": "..."
}
```

Exact parsing patterns will be covered by fixtures from the installed Tailscale version before implementation. The helper will preserve raw output so unfamiliar formats remain debuggable.

## Components

### LuCI view

Add:

```text
htdocs/luci-static/resources/view/tailscale/peers.js
```

Responsibilities:

- Fetch `tailscale status --json`.
- Render all peers.
- Apply client-side filters.
- Call `tailscale_peer_probe` for one selected peer.
- Display loading, success, and failure states per row.

### Probe helper

Add:

```text
root/usr/sbin/tailscale_peer_probe
```

Responsibilities:

- Accept exactly one peer argument.
- Validate the argument before running anything.
- Run `/usr/sbin/tailscale ping`.
- Classify direct, DERP, failed, or unknown.
- Output JSON only.

Argument validation:

- Length: 1 to 253 characters.
- Allowed characters: letters, numbers, `_`, `-`, `.`, `:`.
- No shell evaluation. The helper passes arguments as command arguments, not interpolated shell fragments.

### Menu and ACL

Update:

```text
root/usr/share/luci/menu.d/luci-app-tailscale.json
root/usr/share/rpcd/acl.d/luci-app-tailscale.json
```

ACL grants read-only exec access to:

```sh
/usr/sbin/tailscale_peer_probe
```

The feature remains read-only from LuCI's perspective.

## Error Handling

If `tailscale status --json` fails, the page shows a clear error and does not render stale peer rows.

If no peers exist, the page shows `No peers found`.

If a probe is already running for a row, that row's probe button is disabled until it completes.

If helper output is invalid JSON, the row shows `Failed` and includes a short error message.

If Tailscale is not running, both status loading and probe actions surface that state instead of silently failing.

## Tests

Add or update tests:

- Static package test confirms the new `peers.js`, menu entry, ACL entry, and helper exist.
- Shell tests for `tailscale_peer_probe` cover:
  - invalid peer arguments are rejected;
  - direct ping output is classified as `direct`;
  - DERP ping output is classified as `derp`;
  - failed ping output is classified as `failed`;
  - unknown successful output is classified as `unknown`.
- JavaScript syntax check includes `peers.js`.
- Shell syntax check includes `tailscale_peer_probe`.

## Deployment

Source changes go through the existing PR branch and release package flow.

For office OpenWrt hot deployment during development:

1. Backup current LuCI view and helper files under `/tmp`.
2. Upload `peers.js`, menu JSON, ACL JSON, and helper.
3. Reload only affected LuCI/rpcd metadata if needed.
4. Verify by reading the served LuCI static file over HTTP and calling the helper with a known peer.

No network reload, Tailscale restart, or firewall restart is part of this feature.

## Non-Goals

- No automatic probing of all peers on page load.
- No keepalive configuration changes.
- No Headscale API integration.
- No historical latency chart.
- No persistent storage of probe results.
