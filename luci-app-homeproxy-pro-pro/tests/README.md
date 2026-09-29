# luci-app-homeproxy tests

Automated checks for the pieces that `sing-box check` cannot validate: the
share-link parsers, the UCI→JSON generators and the LuCI form definitions.

## Running

```sh
tests/run.sh
```

* The **LuCI form snapshots** run locally and only need `node`. They re-render
  the node/server views through a mock LuCI runtime and diff the result against
  `tests/snapshots/*.json`.
* The **ucode tests** need `ucode`; the generator cases additionally run
  `sing-box check`, so they need sing-box ≥ 1.14 as well (available on an
  OpenWrt/ImmortalWrt target). `tests/run.sh` picks its branch in this order:

  1. **local toolchain** — if both `ucode` and `sing-box` are on `PATH`, the
     layer runs here, gated on sing-box ≥ 1.14;
  2. **ssh** — otherwise, if `$HP_TEST_HOST` is set, the checkout is copied to
     that machine and run there;
  3. **skip** — otherwise the layer is skipped with a clear message.

  The local toolchain is checked **first** on purpose: the testbed is the
  documented way to run this layer off-target, so an unset `$HP_TEST_HOST` must
  not shadow it. A skip is reported as `SKIP`, never as a pass: the run ends
  with exit 3 and a `PARTIAL:` line unless `HP_ALLOW_PARTIAL=1` is set.

  ```sh
  tests/toolchain/build-ucode-linux.sh        # Linux host, then:
  export PATH="$HOME/.local/ucode-testbed/bin:$PATH"
  tests/run.sh                                # branch 1

  HP_TEST_HOST=root@<test-machine> tests/run.sh   # branch 2
  HP_TEST_DIR=/tmp/hp-tests          tests/run.sh
  ```

  `tests/run.sh` will not ssh into any guessed address, and the production
  router (`192.168.1.1` or anything in `192.168.1.1:*`) is refused by the
  on-target workflow regardless.

### Test statistics

The guard / check / test-file counts quoted in the top-level `README.md` are
measured, not hand-maintained: `tests/print-stats.sh` prints one `key=value`
line each and is the number's single source.

```sh
sh tests/print-stats.sh
# guards=<n>
# checks=<n>
# test_files=<n>
```

`checks` costs one `tests/arch-guard.sh` run, because that is where the total is
counted; the script propagates the guard's exit status, so a red guard cannot be
reported as a green statistic. `test_files` counts files under `tests/` minus the
gitignored `.DS_Store`, which keeps the number the same before and after the
commit that adds a test file (and equal to `git ls-files tests | wc -l`).

### The staging policy: never install

The ssh path **copies the checkout and runs it in place**. It never installs the
package and never runs `apk` or `opkg` on the target. That is a rule, not a
preference.

Installing on a live device runs the package manager, which rewrites
`/etc/config/homeproxy` from the feed package — and on 2026-09-15 that destroyed
the test machine's node configuration. There was no backup and no snapshot, and
six nodes plus the `dns`, `server` and `subscription` sections were
unrecoverable. Staging cannot do that: everything it writes lives under
`$HP_TEST_DIR` and nothing outlives the run.

Two consequences are printed rather than left to be discovered. `tests/run.sh`
reports both versions before staging:

```
== target and source versions (staging; the package is not installed) ==
  source  : 28.9.1.14-r1
  target  : luci-app-homeproxy-26.236.50544~cb5d434
  sing-box: 1.14.1
```

* the target may have a different build of the app installed, or none. **What is
  tested is the checkout, not what the device runs** — so "it passes on the
  device" never means "the installed package is good".
* `sing-box` on the target is whatever the target has. The local branch gates on
  ≥ 1.14; the staging branch records the version instead, because it cannot
  install one.

If a test genuinely needs the installed package, that is a different test and
needs a different safety story (a config backup, taken first, on the device).

`tests/run.sh` exits non-zero if anything fails. The ucode part can also be run
on its own on a target:

```sh
sh tests/ucode/run.sh "$PWD"
```

### The standard device regression

One command, no install, safe to run against a target that is also in use:

```sh
HP_TEST_HOST=root@<test-machine> sh tests/run.sh          # stage + run everywhere
HP_TEST_HOST=root@<test-machine> HP_REQUIRE_FW4=0 sh tests/run.sh   # target without firewall4
```

`HP_REQUIRE_FW4` defaults to `1` on this branch and is validated as `0`/`1`;
the on-target workflow's `require_fw4` input maps onto it. Both the script and
the workflow print which value was used, so a fw4 layer that reported `NOT RUN`
is visible rather than inferred.

Installing the package and reloading the router is **not** part of this command.
If a change needs that (anything in `/etc/init.d/homeproxy`,
`scripts/runtime/*.sh`, or the generation path), do it as a separate, deliberate
step — and take `/etc/config/homeproxy` plus `/etc/homeproxy` aside first, with
the previous release's package kept for re-install. `apk` keeps a modified
conffile and drops a `<file>.apk-new` next to it; check `md5sum` on the config
before and after and delete the `.apk-new` files only once that matches.

## The off-target toolchain (Linux only)

The ucode layer needs a Linux host: ucode's `uci`/`ubus` modules link against
the OpenWrt libraries, `utpl` renders the fw4 template through the `fw4` ucode
module, and `sing-box check` rejects the Linux-only `routing_mark` field
everywhere else. The toolchain is therefore built from source into a private
prefix **on Linux**:

```sh
sh tests/toolchain/build-ucode-linux.sh
export PATH="$HOME/.local/ucode-testbed/bin:$PATH"
tests/run.sh
```

There is deliberately no macOS variant. One existed, and to make the fixtures
pass on Darwin it rewrote `routing_mark` to `null` inside the generator copy —
so the one field that keeps sing-box's proxy connection out of the nft redirect
chain was deleted before every test, and the regression that deleted it in
production (see guard 32) stayed invisible. A host that cannot validate the
generated configuration says so instead of weakening it.

On a development machine, run the whole suite in a Linux container:

```sh
docker run --rm -v "$PWD:/w" -w /w debian:stable-slim sh -c '
  apt-get update -qq &&
  apt-get install -y -qq --no-install-recommends build-essential ca-certificates
    cmake curl gettext git libjson-c-dev libmd-dev libssl-dev meson ninja-build
    pkg-config python3 zlib1g-dev &&
  sh tests/toolchain/build-ucode-linux.sh &&
  PATH="$HOME/.local/ucode-testbed/bin:$PATH" sh tests/run.sh'
```

The script installs into `~/.local/ucode-testbed` and removes nothing outside
that directory plus the clone/build scratch tree (`/tmp/ucode-build` by
default), so dropping the prefix undoes it completely. It builds:

| Component | Why |
| --- | --- |
| `libubox`, `libuci`, `libubus` | ucode's `uci`/`ubus`/`uloop` plugins need them |
| `libmd` | the `digest` module (`ucode-mod-digest` in the package Makefile) |
| `ucode` | the interpreter itself, plus `utpl`/`ucc`. Pinned to the revision ImmortalWrt/OpenWrt snapshots ship as `2026.01.16~85922056` — see "Why ucode is pinned" below |
| `liblucihttp` | `luci.http` is a thin wrapper over this C module and `homeproxy.uc` imports it |
| `luci` ucode sources | `http.uc`, `sys.uc`, … installed to `<prefix>/share/ucode/luci` like OpenWrt does |
| `sing-box` | the official 1.14.0 release binary; the fixtures are validated with `sing-box check` and the package targets 1.14 |

The script ends with a module import check (`lucihttp`, `luci.http`,
`luci.sys`, `uci`, `ubus`, `digest`, …), a check that `utpl` exists and that the
ucode grammar is still the strict one the package targets, and a
`urldecode_params()` behaviour assertion. It exits non-zero if any of them fail.

`tests/run.sh` refuses to run the fixtures against an older `sing-box`
(`FAIL: sing-box >= 1.14 required`), so keep the prefix first in `PATH`.

### What a host without the toolchain reports

The pure-shell, node and python suites still run, and `tests/run.sh` ends with
**exit 3 and `PARTIAL: … the ucode layer did not run`** rather than a pass: a
skipped layer is not evidence. `HP_ALLOW_PARTIAL=1` turns that run back into
"the subset passed" (exit 0) for callers that only want the fast layers; CI
does not set it, so a toolchain that fails to build there fails the job.

### Why ucode is pinned

`UCODE_REV` in the toolchain script is the revision the ImmortalWrt/OpenWrt
snapshot ships (`2026.01.16~85922056`). That ucode is stricter than current
upstream HEAD: it requires a terminating `;` after `export function ... }` and
rejects object and array destructuring, both of which upstream relaxed
afterwards (`openwrt/openwrt@main` pins `b885dd0f`, whose own test suite uses
the semicolon-free form). Building ucode from the default branch therefore
compiles code that no router accepts, which is how five refactor modules
shipped unparseable while CI stayed green.

`tests/ucode/test_ucode_grammar.sh` pins the *dialect* rather than trusting the
revision: it asserts the toolchain still rejects the two constructs and still
accepts the ones the package uses. It runs at the end of the toolchain build
and as the first step of `tests/ucode/run.sh`, so a permissive toolchain fails
loudly instead of turning into a green run. Set
`HP_ALLOW_PERMISSIVE_UCODE=1` to demote that to a warning while deliberately
probing a newer ucode.

**If the canary reports `exported_function_without_semicolon compiles, but the
target ucode rejects it`, the problem is usually the local build, not the pin.**
A testbed built before `UCODE_REV` was introduced tracks upstream HEAD and is
too permissive; rebuild it with `tests/toolchain/build-ucode-linux.sh` and the
canary passes. This is worth doing rather than reaching
for `HP_ALLOW_PERMISSIVE_UCODE=1`: on a permissive toolchain the canary's
"rejected" probes pass for the wrong reason, and a real
missing-`;`/destructuring regression would go unnoticed — which is precisely
how the generator subtree shipped unloadable.

### What the local testbed cannot cover

Nothing is skipped any more. The suite used to report four checks as `SKIP` on
a development host, and those skips are exactly what let a non-compiling
`update_subscriptions.uc` (and, once that was fixed, a destructuring statement)
reach a device:

| Was skipped | Now |
| --- | --- |
| `scripts/update_subscriptions.uc` | compiled like every other source; `luci.sys` comes from the toolchain |
| `scripts/firewall_pre.uc` | compiled; its `homeproxy` import resolves through `-L` |
| `rpcd/ucode/luci.homeproxy` | compiled from a copy whose absolute `/etc/homeproxy/...` imports are rewritten to the checkout |
| `tests/ucode/test_firewall_template.sh` | runs; `utpl` is a symlink to `ucode` and ships with the toolchain |

A missing `utpl`, or any other gap in the toolchain, now FAILS instead of
silently reducing coverage.

The one remaining `NOT RUN` is honest rather than a skip: the render half of
`tests/ucode/test_firewall_template.sh` needs the device-only `fw4` ucode
module. Its source-level half always runs, and it checks the actual
precondition of the bug that test exists for (nothing but the shebang may
precede the `{%-` tag, otherwise the trimmed newline glues the first generated
statement onto a comment). Stubbing `fw4` would let the render run everywhere,
but the assertions would then be about a ruleset the real `fw4` never
produced — see that script's header for the reasoning.

It is not left as a bare skip, though: `HP_REQUIRE_FW4=1` turns the skip into a
failure, and `tests/run.sh` defaults it to 1 in the ssh branch. A target always
has firewall4, so the one environment able to run the render must run it — and a
target that somehow cannot now fails instead of quietly reporting `NOT RUN`. The
default can be turned off for a target that legitimately lacks fw4
(`HP_REQUIRE_FW4=0`, or `require_fw4: false` on the on-target workflow).

Two further host differences are bridged so the remaining checks still run:

* **`/sbin/validate_data`** — `homeproxy.uc` shells out to this OpenWrt helper
  for hostname/address/port validation. `tests/toolchain/validate-data.sh`
  reproduces the caller's contract (exit 0 = valid) using the same validation
  code as the parser unit tests; `tests/ucode/run.sh` exports it as
  `HP_VALIDATE_DATA` when `/sbin/validate_data` is absent, and
  `tests/ucode/test_generators.sh` substitutes it while staging the generator.
* **`routing_mark`** — a Linux-only `SO_MARK` socket option in sing-box (1.14
  has no portable `set_mark` route action), so redirect/tproxy configs cannot
  pass `sing-box check` outside Linux. This is a property of the *host*, not of
  the product: the ucode layer runs on Linux (the toolchain, CI and the target
  all are), and the assertion that the mark is emitted reads the generated JSON
  instead of asking the local sing-box about it. The suite used to rewrite the
  generated field to `null` on Darwin instead — which is how the regression
  that deleted it in production stayed invisible (see guard 32).

## What is covered

| Path | Checks |
| --- | --- |
| `tests/i18n-coverage.py` | Reports how many `po/templates/homeproxy.pot` strings have a non-fuzzy, non-empty `po/zh_Hans/homeproxy.po` translation. Technical tokens that stay as-is are listed in `tests/i18n-ignore.txt`; anything else missing fails the run (`--fail-below 100`) and adds a job-summary entry. The release workflow (`build.yml`) deliberately warns instead of failing, so a translation gap cannot block packaging - the PR gates already catch it. |
| `tests/luci-form-snapshot.js` | Dumps every option (name, kind, title, description, depends, values, datatype/default/…) of the node, client and server views. Diffs against `tests/snapshots/{node,client,server}.json`, so a refactor that changes a field or its visibility fails. |
| `tests/ucode/test_homeproxy_utils.uc` | `executeCommand()` return shape, stderr/exit-code capture, binary detection, and a descriptor-leak check (200 calls). |
| `tests/ucode/test_resource_blob_sha.sh` | `resource_blob_sha.uc`, the digest the resource updater verifies downloads with. The expected values are git's own (`git hash-object` on the same bytes), covering the two cases an implementation gets wrong quietly: the empty file (a real blob id, not "no digest") and content whose byte length differs from its character count. Unreadable input must produce *no* digest and exit non-zero - the updater treats an empty answer as "cannot verify" and refuses, so a made-up digest would turn an unreadable file into a passing check. Re-checks the repository's real resource files against git when the host has it. |
| `tests/ucode/test_homeproxy_utils_inject.uc` | The failure path of `executeCommand()`: the script stages a copy of `homeproxy.uc` whose `system()` call is replaced by `die()`, then checks that the exception still propagates and that neither descriptor leaks. |
| `tests/ucode/test_tls_transport.uc` | Direct calls into `buildTLSObject()` / `buildTransportObject()`: client-vs-server-only fields (no `insecure` on a server inbound, no `utls` on a server, `public_key` only on the client and `private_key` only on the server for reality), the ECH client/server split, and the `validateHomeProxyPath()` gate on `cert_path` / `key_path`. This is the boundary the generator fixtures only exercised end-to-end, so it is where the "server emitted insecure=true" and "reality key on the wrong side" classes of bug get named. |
| `tests/ucode/test_subscription_fetcher.uc` | `subscription/fetcher.uc` against a shimmed `wGETVerbose`: empty content logs a **redacted** URL and returns `{content:null,error}`; non-empty content returns the body and logs nothing. The redaction assertions are what stop the subscription token from reappearing in `homeproxy.log`: the userinfo, the **path** (providers hand out `https://host:port/<user>/<token>` with no query string) and the query string are all gone, while the host and port survive so the message still says which endpoint failed. The mocks carry verbatim copies of `redactUrl()`, and arch-guard 35 fails when one of them drifts from `homeproxy.uc`. |
| `tests/ucode/test_migrate_config.sh` | Runs `migrate_config.uc` (36 checks) against a sandboxed UCI file that needs every migration step it can see at once — the 1.14 DNS renames, the legacy `dns_server.address` split, `rcode://` → predefined rule, `rule_set_ipcidr_match_source` rename, `block-out`/`block-dns` → `action='reject'`, `auto_firewall` redistribution, and the `block-dns` default-server replacement. The staged copy's cursor is redirected at the sandbox; the runner aborts if that rewrite stops matching rather than letting the migration touch the live `/etc/config`. |
| `tests/ucode/test_firewall_pre.sh` | Behaviour tests for `firewall_pre.uc` (8 scenarios, one process each because the script has no exports): the tun accept pair, the per-server accept rules, the explicit-network narrowing, and — most importantly — that an invalid port or network skips the server with a WARN instead of interpolating garbage into an nft statement, which would make nft reject the entire ruleset. |
| `tests/ucode/test_fw4_names.sh` | Keeps the fw4 chain/set inventory in `scripts/fw4_names.sh` (used by `init.d/homeproxy` to clean up on stop) in sync with the objects declared in `scripts/firewall_post.ut`. |
| `tests/ucode/test_parse_uri.uc` | Per-scheme assertions on the `parse_uri()` result: anytls, http/https, hysteria, hysteria2/hy2, snell, socks(4/4a/5/5h), shadowsocks (SIP002 base64 + plain + plugin, Shadowrocket), trojan (ws/grpc), tuic, vless (reality/ws/http/httpupgrade), vmess (ws/h2/httpupgrade/grpc) and SIP008 objects, plus the rejection paths (unsupported kcp/quic, no QUIC support, invalid port, unknown scheme). |
| `tests/ucode/test_parser_normalize.uc` | Asserts that `parser/normalize.uc` correctly maps the parser's flat UCI-key output to the canonical Node shape (`tls`, `transport`, `multiplex`, `common`, `credentials`, `protocol_options`); pins the contract between the parser, the Loader's `PROTOCOL_OPTIONS` (now derived from `parser/mapping.uc`) and the Adapter. |
| `tests/ucode/test_parser_flatten.uc` | Round-trip invariant for the canonical-Node pipeline: `flatten(normalize(parse_uri(uri)))` must equal the parser's flat UCI dict field-for-field for every supported scheme. This is what stops the parser, the Loader's `PROTOCOL_OPTIONS` (now derived from `parser/mapping.uc`) and the Repository's flatten from drifting apart. |
| `tests/ucode/test_subscription_repository.uc` | Integration test for `subscription/repository.uc`: stages a sandboxed UCI file with a user node, a kept subscription node, and a dropped subscription node, then runs `Repository.apply_nodes` and asserts (a) the user node is untouched, (b) the kept node has the new fields and no stale fields, (c) the dropped node is gone, (d) a brand-new node is added under `md5(group+label)`. PR-03 added the `apply_main_node_refs` paths (urltest prune + missing-target switch + reset-to-nil) and the `scrub_stale_urltest_refs` pass to the same test. |
| `tests/ucode/test_generators.sh` | Runs `generate_client.uc`/`generate_server.uc` against the UCI fixtures in `tests/fixtures/generators/` inside a scratch directory (the `uci` cursor and `HP_DIR`/`RUN_DIR` are redirected) and validates each result with `sing-box check`. The `redirect` case is the product's default `proxy_mode` and asserts, from the emitted JSON, that every dialling outbound carries the runtime `routing_mark`. |
| `tests/toolchain/build-ucode-linux.sh` | Builds the local ucode toolchain described above; not part of `tests/run.sh`. |
| `tests/toolchain/validate-data.sh` | Off-target stand-in for `/sbin/validate_data`, used through `HP_VALIDATE_DATA`; not part of `tests/run.sh`. |
| `tests/ucode/test_ucode_grammar.sh` | Pins the ucode dialect: the toolchain must reject `export function ... }` without `;` and object/array destructuring, and must accept the constructs the package uses (`?.`/`??`, object spread, computed keys, template literals). |
| `tests/ucode/test_generators.sh` (wireguard case) | Asserts the WireGuard fixture keeps its private key, peer public key and local address list, so the endpoint builder cannot silently regress to reading flat UCI option names. |
| `tests/ucode/test_golden_outbounds.sh` | Builds one outbound per protocol from `tests/fixtures/generators/outbounds.uci` and diffs the result against `tests/snapshots/generator/outbounds.json`, so a field change for any protocol is a reviewable diff. Regenerate with `HP_UPDATE_SNAPSHOTS=1`. |
| `tests/ucode/test_golden_inbounds.sh` | PR-04: the server-side counterpart. Builds one inbound per protocol from `tests/fixtures/generators/server.uci` and diffs the result against `tests/snapshots/generator/inbounds.json`. The ACME `data_directory` is normalised to `<HP_DIR>/certs` so the snapshot is portable across hosts. Before this existed the server path had no snapshot at all, which is how the fixture's unused `listen_port` option survived. Regenerate with `HP_UPDATE_SNAPSHOTS=1`. |
| `tests/ucode/test_inbound_adapter.uc` | PR-04: `InboundFactory`'s protocol-shape decisions — snell / shadowsocks must get no `users[]` block (a snell users entry is read as an extra user key and makes sing-box reject the section), vless / vmess keep `flow` / `alterId` per-user, the snell listener set omits `udp_fragment` / `udp_timeout` / `network`, the server-only TLS tail (key material, ECH key, REALITY private key + handshake, ACME) reaches `buildTLSObject()`, hysteria v1 emits `obfs` as a string while hysteria2 emits the object, and the per-protocol credential requirements are enforced. |
| `tests/ucode/test_protocol_inventory.sh` | Cross-checks the protocol surface: every type named by `parse_uri.uc`, `CREDENTIALS`, `PROTOCOL_OPTIONS`, `REQUIRED_CREDENTIALS`, `OPTION_FIELDS` and the golden snapshot must agree. This is the check that catches "added a protocol to one table and forgot another". |
| `tests/frontend-protocol-inventory.js` | The frontend's single ordered protocol table (`homeproxy.js`'s `protocols`) against the backend tables that decide what the generators can build: every offered type must be modelled (`PROTOCOL_TO_UCI` on the client side, `INBOUND_CREDENTIALS` on the server side), every outbound-capable protocol (`OPTION_FIELDS`, `REQUIRED_CREDENTIALS`) must be selectable in the node form, both rendered orders are pinned, and protocols the backend models but no form offers must be listed as deliberate decisions. This is the check that would have caught `snell`: it had a form block, a credentials row and a golden outbound, but was missing from the node form's value list so it could not be selected. Node-only, no ucode needed. |
| `tests/frontend-rpc-inventory.js` | The frontend RPC boundary: exactly one `rpc.declare` site (inside `homeproxy.js`'s `rpcCall`), no view wrapping a call in `L.resolveDefault`, `rpcCall` itself catching and falling back and reporting, and no view left with an unused `require rpc`. Source-level on purpose - the behaviour it protects needs a browser, but "nobody reintroduces a second declaration site" does not. Comments are stripped before matching, because a naive grep matches the doc comment that quotes the old idiom. |
| `tests/frontend-validators.js` | Drives the shared form validators with a fake form context. The snapshots cannot cover these: a `validate` callback is a function, and the dump skips function-valued properties. Sharing the password validator between the node and server forms added the 2022-blake3 key-length check to the node form, which the server form had and the node form did not - a client could save a key that makes the generated configuration fail to decode. Reverse-proved: deleting that branch fails six checks. |
| `tests/lib/luci-module.js` | The off-target LuCI module loader (`'require x as y';` rewritten into a dependency lookup), shared by the snapshot renderer and the frontend invariant tests. Its default `_()` returns a LuCI String object with `.format`, because the form code calls both halves. |
| `tests/runtime/test_config_transaction.sh` | The `runtime/` helpers `init.d/homeproxy` leans on: the known-good copy, the fallback when generation produced nothing, the rollback, and the health probe. Pure shell, runs anywhere. |
| `tests/runtime/test_dns_snippets.sh` | The dnsmasq snippet writer's incremental behaviour (review L6). Counts `init.d/dnsmasq restart` calls through a stub and asserts that an identical second write does *not* restart (a restart flushes every client's DNS cache), while a changed resource list, routing mode, DNS port or `ipv6_support` setting does. Also pins that a mode change drops the snippet the previous mode produced, and that removing a resource list removes its snippet so the next call is stable again. Pure shell, runs anywhere. |
| `tests/runtime/test_health_probe.sh` | The functional health probes (`runtime/health.sh`): `hp_probe_dns` / `hp_probe_tcp` answer 0 / 1 / 2 and keep "cannot probe here" (no tool, no port) distinct from "the probe failed"; `hp_run_probes` *reports* by default and only fails the gate when `health_probe_strict` is on, and never fails it for a probe that could not run; `hp_config_port_for_tag` reads the probe ports out of the running configuration in both the generator's pretty shape and the compact one. `nslookup` and `nc` are stubbed, so it is pure shell and runs anywhere. |
| `tests/runtime/test_crontab_perms.sh` | `hp_crontab_drop()` (runtime/service.sh) edits `/etc/crontabs/root` through a temporary file, and `mv` replaces the file rather than its contents - so the new one inherited the shell's umask (0644) while procd creates the root crontab as 0600. The test drives the function against a sandboxed crontab and pins: the entry is dropped, other jobs survive, the mode is 0600 (including a file an older version had already loosened), a missing crontab is reported as a failure and is not created. Pure shell, runs anywhere. |
| `tests/runtime/test_resource_update.sh` | The content-verification path of `scripts/update_resources.sh`: the download URL is pinned to a commit, and the file is installed only when its git blob id matches the one GitHub reports for that path and commit. Drives all four outcomes (match, mismatch, no digest from the API, no local digest) with `wget` / `jsonfilter` / `ucode` / `uci` / `flock` stubbed and the script's absolute paths rewritten into a sandbox, asserting in each failure case that the installed list and its `.ver` are left untouched - the point of the check is that it refuses, so a driver that only walked the happy path would keep passing with the check deleted. Pure shell, runs anywhere. |
| `tests/runtime/test_runtime_extraction.sh` | Drives `init.d/homeproxy` through a stubbed environment (fake `ip` / `nft` / `fw4` / `ucode` / `sing-box` / `uci` / `netstat` / `nslookup` / `nc`, fake procd and jsonfilter state, fixture UCI) across five scenarios and diffs the resulting command + file trace against a baseline. Two baselines exist and are captured with the SAME harness, so the diff between them is exactly the intentional change: `tests/fixtures/runtime/trace.pre-pr05.txt` (the 517-line init script before PHASE 7 moved the plumbing out — the record that the extraction was behaviour-preserving) and `tests/fixtures/runtime/trace.golden.txt` (after the health-gate fix). Scenario D is the P0 regression: a candidate whose `mixed_port` is already taken must be rejected by the health gate, the previous known-good must survive, and the reload must roll back onto it. The generated fixture configuration is pretty-printed like the generator's own `%.J` output, because the runtime reads that file (`hp_config_ports`, `hp_config_port_for_tag`) and a compact fixture would test a shape production never writes. Pure shell, no ucode needed. Regenerate with `HP_UPDATE_GOLDEN=1` (optionally `HP_GOLDEN=` / `HP_INITD=` to target another baseline or revision). |

**`HP_UPDATE_GOLDEN=1` is a baseline-update mode, not a test.** It copies the
trace the run just produced over the baseline and exits 0 *before* the golden
comparison and every behavioural assertion after it
(`tests/runtime/test_runtime_extraction.sh:682-687`), so the exit status of a
regenerating run says nothing about the diff it wrote. That is the "test bakes a
wrong output into a snapshot" risk the review named: the scenarios did run, but
only the review of the written file
(`git diff tests/fixtures/runtime/trace.golden.txt`) can tell whether the new
baseline is correct. `tests/ucode/test_golden_outbounds.sh` is arranged the other
way round on purpose - it asserts on the generated JSON first and only then
honours `HP_UPDATE_SNAPSHOTS=1` - which `test_runtime_extraction.sh` cannot do,
because its assertions all run after the trace is built.

### What the LuCI form snapshots cover

A snapshot records, for every option the form builds: kind, name, title,
description, dependency set, the `ListValue` value list, and the non-function
properties that were set on it.  Options are nested, so a `SectionValue`
option's nested form is included.

That last part was missing until it was fixed: `Option.toJSON()` skipped the
`subsection` key, which is where `SectionValue` keeps the nested form, so the
node form's entire body and client.js's rule sections were invisible.  The
measured effect of the fix:

| Target | Options dumped | Snapshot size |
|---|---|---|
| `node.json` | 13 → **117** | 3.5 KB → 34.6 KB |
| `client.json` | 29 → **206** | 8.6 KB → 56.3 KB |
| `server.json` | 95 → 95 | 25.9 KB → 27.8 KB |

Before that fix, a change to the protocol picker - exactly the kind of change
PHASE 8 makes - was visible in `server.json` only.  That is why
`tests/frontend-protocol-inventory.js` also exists: it asserts the *meaning* of
the protocol table against the backend, which a structural snapshot cannot.

What the snapshots still cannot tell you: whether the form is *usable*. They
prove a change to the option tree is deliberate and reviewable; they say nothing
about whether the resulting page works in a browser.

`tests/ucode/mocks/homeproxy.uc` is a test double for the real module: only
`validation()` is stubbed (the real one runs `/sbin/validate_data`, which does
not exist outside OpenWrt), everything else is a copy of the production code.

Three further mocks exist because a test needs a narrower seam than the full
module:

* `tests/ucode/mocks/homeproxy_fetcher.uc` — replaces `wGETVerbose` with a
  stub that reads the canned response from a global, so the fetcher test never
  shells out to `wget`.
* `tests/ucode/mocks/homeproxy_firewall.uc` — `isEmpty` / `validation` plus a
  `RUN_DIR` read from a global, so `firewall_pre.uc` writes its nft fragments
  into a scratch dir.
* `tests/ucode/test_migrate_config.sh` rewrites the staged copy of
  `migrate_config.uc` so its cursor points at the sandbox. Whenever a test
  rewrites a staged copy, it must abort when the rewrite anchor stops
  matching — otherwise the sed no-ops and the script under test operates on
  the live `/etc/config`. Both `test_migrate_config.sh` and
  `test_firewall_pre.sh` do this.

### Files that still have no direct test

Deliberately, because a meaningful test would need more than the off-target
harness provides:

| Path | Why |
| --- | --- |
| `scripts/update_resources.sh` | The version query and the download are a GitHub API round-trip plus a jsdelivr fetch, so the verification path is driven by `tests/runtime/test_resource_update.sh` with `wget` / `jsonfilter` / `ucode` / `uci` / `flock` stubbed and the script's absolute paths rewritten into a sandbox: matching digest installs, a mismatch or a missing digest refuses and leaves the installed list and its `.ver` alone. The `*)` usage branch is covered by the shell syntax check. |
| `scripts/update_crond.sh` | A fixed list of invocations against hard-coded `/etc/homeproxy/scripts` paths. Covered by the shell syntax check. |
| `scripts/clean_log.sh` | `while true; do sleep 180; …` — testing the rotation needs the loop made injectable first. Covered by the shell syntax check. |
| `htdocs/.../view/homeproxy/status.js` | A LuCI view; its behaviour is only observable in a browser. |
| `init.d/homeproxy` | procd semantics need a real procd, and `service_started` only behaves correctly when procd really starts the instances — the offline harness models that, but it is a model. PR-05 shrank the file from 517 to 253 lines by moving the dnsmasq / fw4 / tproxy-TUN / service-plumbing into `scripts/runtime/{service,dns,firewall,net}.sh`; the trace test proves the move kept the command-and-file behaviour identical, and the shell syntax check covers every file. The health gate itself was verified on the ImmortalWrt test machine (see the plan's 2.14.8). |

## Architecture regression coverage

The old `test_demo_architecture.sh` compared the production `OutboundFactory`
against itself (via `generate_outbound()`, which delegates to it) and could
therefore never fail; it is gone, along with the `/* HP_TEST_HOOK */` marker it
relied on. Two tests replaced it:

* `tests/ucode/test_golden_outbounds.sh` pins the actual emitted JSON per
  protocol in `tests/snapshots/generator/outbounds.json`; PR-04 added the
  matching `tests/ucode/test_golden_inbounds.sh` for the server inbounds
  (`tests/snapshots/generator/inbounds.json`).
* `tests/ucode/test_protocol_inventory.sh` asserts that the parser, the model,
  the loader option table, the adapter tables and the golden snapshot all name
  the same set of protocols.

`root/etc/init.d/homeproxy` is exercised for what can be checked off-target:
`tests/ucode/run.sh` syntax-checks it and the `runtime/` helpers,
`tests/runtime/test_config_transaction.sh` covers the transaction semantics, and
`tests/runtime/test_runtime_extraction.sh` pins the orchestration order
(generate before teardown, known-good before firewall, cron before
`config_load`, early return before `mkdir`) against the pre-PR-05 trace.

procd itself is still only exercised on a target. **The paragraph below is a
historical record, not a target you can use**: `root@192.168.1.102` is the
author's former test machine, an address that is no longer part of the test
setup and that nothing in this tree defaults to. `tests/run.sh` reads
`$HP_TEST_HOST`, skips the layer when it is unset, and arch-guard 13 keeps it
that way - so treat what follows as "what was observed on 2026-09", not as
reproduction instructions.

PR-05 was verified on the ImmortalWrt test machine (`root@192.168.1.102`):
`start` brought up both
`sing-box-c` and `log-cleaner` instances (proving that a procd instance
registered from a *sourced module* works), `reload` passed the health gate and
refreshed known-good, and `stop` removed the instances, the TUN device, the ip
rules, the dnsmasq snippets and the live configuration while keeping the
known-good copy. That run is a manual step, not a CI job — see the plan's
PHASE 9 row for the on-target CI gap.

## Adding cases

* New share link → add an `expect_fields(...)` case to `test_parse_uri.uc`.
* New protocol option that reaches the generator → extend the fixtures in
  `tests/fixtures/generators/`, keeping values schema-valid so `sing-box check`
  still passes.
* Intentional LuCI form change → regenerate the snapshots:

  ```sh
  node tests/luci-form-snapshot.js . node   > tests/snapshots/node.json
  node tests/luci-form-snapshot.js . client > tests/snapshots/client.json
  node tests/luci-form-snapshot.js . server > tests/snapshots/server.json
  ```
