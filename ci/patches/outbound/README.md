# outbound patches (self-owned)

Fixes we carry on top of `OUTBOUND_COMMIT` because upstream has not merged them.
The assemble workflows apply every `NNNN-*.patch` here with `git apply` right
after fetching outbound; an empty directory is skipped.

## Current state: two patches

| patch | what | why it is here |
|-------|------|----------------|
| 0002 | REALITY client sends version bytes `[26,7,28]` instead of `[1,8,10]` | Xray-core 26.7.11+ defaults the server's `minClientVer` to `26.3.27`, so our version bytes are rejected; see below |
| 0003 | anytls link parser also accepts `insecure` next to the spellings `dialer.AllowInsecureFromQuery` already covers | anytls links in the wild spell the skip-verify flag several ways; with any other spelling the client silently kept certificate verification on and the node dial failed. Compatibility fix, not a confirmed root cause of any open issue; see below |

### 0003 background

The anytls parser hardcoded `u.Query().Get("insecure") == "1"` and never
called `dialer.AllowInsecureFromQuery`, which the other TLS dialers share and
which accepts `allowInsecure` / `allow_insecure` / `allowinsecure` /
`skipVerify`. The two key sets never intersected — anytls understood only
`insecure`, the helper only the other spellings — so a link using any spelling
outside `insecure=1` imported fine and then failed the dial with a certificate
verification error (e.g. `x509: certificate signed by unknown authority`
against a self-signed server): the node shows up but every latency probe
reports it dead.

Issue #57 was the first report of this class: its log shows a certificate
**hostname mismatch** (`x509: certificate is valid for *.dydyyd.com, not
gateway.icloud.com`), because its link carried `allowInsecure=1` and
verification therefore stayed on. #57 was fixed on the converter side only (our
Clash converter now writes `insecure=1`), so links taken straight from an
airport panel into daed's web UI still have no protection.

A certificate error on its own does not prove this bug: expired certificates,
hostname mismatches and a wrong device clock all produce one. The
distinguishing part is that the link's skip-verify flag was spelled something
other than `insecure=1`.

0003 keeps the shared helper untouched: adding `insecure` to it would newly
switch off certificate verification for HTTP/trojan/TUIC/juicity links whose
query happens to carry that key, which those protocols do not accept today.
Instead anytls accepts both families itself:
`dialer.AllowInsecureFromQuery(q) || ParseBool(q.Get("insecure"))`. Absent,
`insecure=0` and unparsable values keep verification on.

Evidence gathered locally before writing the patch (self-signed anytls server,
sing-box 1.13.4, direct dial through outbound's anytls dialer):

| link query | pin as-is | with 0003 |
|---|---|---|
| `insecure=1` | dial OK | dial OK |
| `allowInsecure=1` | verification fails | dial OK |
| `insecure=true` | verification fails | dial OK |
| `skipVerify=true` | verification fails | dial OK |
| `insecure=0` / absent / `insecure=bogus` | verification fails | verification fails |

("verification fails" means the self-signed test server rejected the
handshake. Nodes with a valid certificate were not part of this test and are
unaffected by the patch either way.)

What this does **not** establish: issue #108 reports nodes that are
`NOT ALIVE` with no certificate error in the log, so its root cause is still
unconfirmed. This patch only changes behaviour for links whose flag spelling is
not `insecure=1` **and** whose server certificate would not validate; a link
that already carries `insecure=1`, or a node with a valid certificate, behaves
exactly as before. Treat 0003 as removing a known compatibility hole, not as
the #108 fix.

Tests: `TestInsecureFromQuery` (spellings, defaults, invalid values, conflicting
parameters) and `TestParseAnytlsURLHonorsInsecureAliases` in
`dialer/anytls/anytls_test.go`.

Shipping gate: the patch only lands in a binary after
`assemble-{dae,daed}-src.yml` re-freezes the tarball. That job writes
`PKG_SOURCE`, `PKG_HASH` and `PKG_RELEASE` into `dae/Makefile` and
`daed/Makefile` in its own commit — so do not hand-bump the release here, and
before any candidate build confirm the assemble commit really changed
`PKG_SOURCE` (a "no change" run means the patch never reached the tarball and
the built package still carries the unfixed parser).

### 0001: absorbed upstream (2026.10.18 bump, `OUTBOUND_COMMIT=1cf3439`)

The SSR obfs fix from 0001 is now in the perf line itself, so the patch was
deleted. Upstream implements it as `netproxy.UnwrapIntrinsicConn`
(`netproxy/unwrap.go`, peels the full wrapper chain up to depth 8) used by
`TcpConn.Write`, plus the regression test
`TestTcpConnFirstWriteReachesSSRObfsCipher` in `ssr_obfs_test.go` (real SSR
transport stack, covers the buffered-wrapper case). The old patch's local
one-layer `unwrapConn` helper and its `ssr_cipher_test.go` are superseded.

History: the fix first existed upstream as a side commit (`d5d9708`, later
rebased to `5797872`) that was never merged into the perf branch we track,
which is why it was carried as a patch (and why it regressed on 2026-08-13
when a bump moved the pin to a perf-branch commit without it). The r11
optimization line folded it into `perf/complete-optimizations`, so the pin now
carries it. If a future pin ever drops it, this note and the upstream test are
the trail — re-add the patch.

### 0002 background

The REALITY client writes its own three version bytes into the encrypted
handshake. Xray-core 26.7.11+ (commit `af7eb68`) defaults the server's
`realitySettings.minClientVer` to `26.3.27` when unset, so 26.7.x servers using
that default reject dae/daed REALITY connections into the fallback decoy
(`REALITY: processed invalid connection`). Sending `[26,7,28]` passes any
current default gate. This is a temporary compatibility measure, not a protocol
requirement:

- Xray-core main has already reverted the default gate in commit `47cfe999`,
  but no release carries that change yet, and 26.7.x servers already deployed
  keep it.
- Re-evaluate (and delete) this patch only when outbound itself adopts an
  appropriate version-byte strategy, or when the project's compatibility scope
  explicitly drops 26.7.x servers — not merely because a newer Xray release
  appears. A server operator can still reject us by explicitly configuring a
  lower `maxClientVer`; that is their choice and nothing on our side fixes it.

The REALITY protocol library is identical between Xray-core 26.3.27 and
26.7.28, so patched clients remain fully compatible with older servers.

## Apply by hand

```sh
git checkout -B carry <OUTBOUND_COMMIT>
git apply ci/patches/outbound/*.patch
go test ./protocol/shadowsocks_stream/ ./transport/tls/
```

## When upstream absorbs a patch

`git apply` fails loudly and the assemble build stops. Inspect the failing patch
before deleting it: for 0001, confirm the wrapper-peeling fix is in the new
base (as `netproxy.UnwrapIntrinsicConn`, not the old local `unwrapConn`
helper); for 0002, follow the re-evaluation conditions above.
