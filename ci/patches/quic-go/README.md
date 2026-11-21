# quic-go perf patches (self-owned)

Reproducible copy of any olicesx quic-go performance delta that is **not yet in
our pinned base**, so the build never *depends* on the olicesx repo staying
alive. See `../../PERF-PATCHES.md` for the full lineage and refresh procedure.

## Current state: empty (nothing to carry)

`QUICGO_BASE_COMMIT` is `08e975ef39de` (`olicesx/quic-go`, branch
`fix/audit-remediation`), which already contains all four historical patches
this directory used to carry, plus the later QUIC security, buffer ownership
and GSO capacity fixes:

| was | effect | status |
|-----|--------|--------|
| 0001 | UDP GSO single-segment send fix | in base |
| 0002 | B-tree node pooling + frame sorter | in base |
| 0003 | return stream frames to pool on cancellation | in base |
| 0004 | RTT sample only for last ack-eliciting packet | in base |

They were removed when the base moved forward on 2026-07-31; re-applying them
would conflict. The 2026-08-28 base moved forward again because outbound now
requires `08e975ef39de`. The mechanism stays: drop `NNNN-*.patch` files here
and the assemble workflows pick them up automatically (an empty directory is
skipped).

## Why the base is a feature branch

The outbound fork pins quic-go by pseudo-version in its `go.mod`, and the
commit it needs currently lives on `fix/audit-remediation`, not on `main`.
`QUICGO_BASE_COMMIT` must equal that target — `auto-bump.yml` refuses to move
`OUTBOUND_COMMIT` when the two diverge, which is exactly the breakage that took
dae/daed builds down on 2026-07-31 (`ReleaseDatagram undefined`).

## Apply

```sh
git checkout -B perf <base>          # <base> = QUICGO_BASE_COMMIT
git am ci/patches/quic-go/*.patch    # no-op while this directory is empty
```

If a future base has drifted and a hunk fails, fall back to `git apply --3way`
or port the change by hand — the surface has historically been tiny
(frame_sorter.go, internal/ackhandler/sent_packet_handler.go,
internal/utils/tree/tree.go, send_stream.go, sys_conn_oob.go).
