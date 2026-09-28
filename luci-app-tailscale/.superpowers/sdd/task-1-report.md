# Task 1 Report: Tailscale peer observability helper

## Completed
- Added `tests/tailscale_peer_probe_test.sh` with RED-first coverage for:
  - successful direct peer latency output
  - successful DERP peer relay + latency
  - unknown format handling
  - ping failure path
  - invalid peer input
  - missing argument usage response
- Added `root/usr/sbin/tailscale_peer_probe` implementation.
- Extended `tests/package_release_test.sh` assertions for:
  - helper file existence
  - ACL references to `tailscale_peer_probe`
  - "Peer probe" comment marker in helper

## Test results
- `sh tests/tailscale_peer_probe_test.sh` -> **pass**
- `sh tests/package_release_test.sh` -> **fail** at `assert_contains "tailscale_peer_probe" root/usr/share/rpcd/acl.d/luci-app-tailscale.json`

## Commit
- `08259ed` (`Add Tailscale peer probe helper`)

## Remaining concern
- The package release test failure is expected for Task 1 because ACL/menu registration is not yet implemented in later tasks.

## Review Findings Fix (Task 1 Follow-up)
- Removed the premature ACL assertion from `tests/package_release_test.sh` so Task 1 static tests no longer validate ACL registration.
- Expanded `json_escape` in `root/usr/sbin/tailscale_peer_probe` to escape control characters in raw output: backslash, double quote, tab, carriage return, and newline.
- Extended `tests/tailscale_peer_probe_test.sh` with a multiline control-peer output case covering escaped `\"`, `\\`, `\\t`, `\\r`, and `\\n`, and an explicit single-line JSON output assertion.

### Verification commands
- `sh tests/tailscale_peer_probe_test.sh`
  - Output: `tailscale_peer_probe tests passed`
- `sh tests/package_release_test.sh`
  - Output: `package release tests passed`
