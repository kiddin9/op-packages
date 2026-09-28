# Task 3 Report: Tailscale Peers LuCI View

## Summary
- Added the read-only LuCI peers page at `admin/vpn/tailscale/peers`.
- The page loads `tailscale status --json`, lists all peers, supports `all`, `online`, and `advertising subnets` filters, and adds a per-peer `Probe` action that calls `/usr/sbin/tailscale_peer_probe`.
- Probe results render the path label as `Direct`, `DERP`, `Failed`, or `Unknown` with the helper summary.

## Changed Files
- `htdocs/luci-static/resources/view/tailscale/peers.js`
- `tests/package_release_test.sh`

## RED / GREEN
- RED: `sh tests/package_release_test.sh`
  - Result: `FAIL: missing required package file: htdocs/luci-static/resources/view/tailscale/peers.js`
- GREEN: `node --check htdocs/luci-static/resources/view/tailscale/peers.js`
  - Result: exit `0`
- GREEN: `sh tests/package_release_test.sh`
  - Result: `package release tests passed`

## Self-Review
- The page is read-only: no save/apply/reset handlers and no reload actions.
- The helper call is per-peer only; there is no bulk probe control.
- Status parsing reads all peers from `tailscale status --json`, not just subnet advertisers.
- Filter state, probe state, and result rendering are kept local to the view and survive polling refreshes.

## Concerns
- None.

## Task 3 Fix (2026-07-14)
- `loadPeerState()` now checks `res.code` after `tailscale status --json` execution; when `res.code !== 0`, it returns `{ ok: false, peers: [], error: <message> }` without parsing status.
- `refreshPeers()` now clears stale rows on failed refresh by setting `state.peers = []` and `state.error = next.error` when `next.ok === false`.
- Behavior remains read-only (no reload/restart/network side effects introduced).

### Verification
- Command: `node --check htdocs/luci-static/resources/view/tailscale/peers.js`
  - Result: syntax check passed (exit 0).
- Command: `sh tests/package_release_test.sh`
  - Result: `package release tests passed`.
