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
  OpenWrt/ImmortalWrt target). When the host running `tests/run.sh` has neither,
  the checkout is copied over ssh to `$HP_TEST_HOST` (default
  `root@192.168.1.1`) and the tests run there:

  ```sh
  HP_TEST_HOST=root@192.168.1.1 tests/run.sh
  HP_TEST_DIR=/tmp/hp-tests      tests/run.sh
  ```

`tests/run.sh` exits non-zero if anything fails. The ucode part can also be run
on its own on a target:

```sh
sh tests/ucode/run.sh "$PWD"
```

## What is covered

| Path | Checks |
| --- | --- |
| `tests/i18n-coverage.py` | Reports how many `po/templates/homeproxy.pot` strings have a non-fuzzy, non-empty `po/zh_Hans/homeproxy.po` translation. Technical tokens that stay as-is are listed in `tests/i18n-ignore.txt`; anything else missing produces a warning annotation (`--warn-below 100` by default) and a job-summary entry. Run by `.github/workflows/i18n.yml` on push/PR and before a release. |
| `tests/luci-form-snapshot.js` | Dumps every option (name, kind, title, description, depends, values, datatype/default/…) of the node and server views. Diffs against `tests/snapshots/{node,server}.json`, so a refactor that changes a field or its visibility fails. |
| `tests/ucode/test_homeproxy_utils.uc` | `executeCommand()` return shape, stderr/exit-code capture, binary detection, and a descriptor-leak check (200 calls). |
| `tests/ucode/test_homeproxy_utils_inject.uc` | The failure path of `executeCommand()`: the script stages a copy of `homeproxy.uc` whose `system()` call is replaced by `die()`, then checks that the exception still propagates and that neither descriptor leaks. |
| `tests/ucode/test_fw4_names.sh` | Keeps the fw4 chain/set inventory in `scripts/fw4_names.sh` (used by `init.d/homeproxy` to clean up on stop) in sync with the objects declared in `scripts/firewall_post.ut`. |
| `tests/ucode/test_parse_uri.uc` | Per-scheme assertions on the `parse_uri()` result: anytls, http/https, hysteria, hysteria2/hy2, snell, socks(4/4a/5/5h), shadowsocks (SIP002 base64 + plain + plugin, Shadowrocket), trojan (ws/grpc), tuic, vless (reality/ws/http/httpupgrade), vmess (ws/h2/httpupgrade/grpc) and SIP008 objects, plus the rejection paths (unsupported kcp/quic, no QUIC support, invalid port, unknown scheme). |
| `tests/ucode/test_generators.sh` | Runs `generate_client.uc`/`generate_server.uc` against the UCI fixtures in `tests/fixtures/generators/` inside a scratch directory (the `uci` cursor and `HP_DIR`/`RUN_DIR` are redirected) and validates each result with `sing-box check`. |

`tests/ucode/mocks/homeproxy.uc` is a test double for the real module: only
`validation()` is stubbed (the real one runs `/sbin/validate_data`, which does
not exist outside OpenWrt), everything else is a copy of the production code.

## Adding cases

* New share link → add an `expect_fields(...)` case to `test_parse_uri.uc`.
* New protocol option that reaches the generator → extend the fixtures in
  `tests/fixtures/generators/`, keeping values schema-valid so `sing-box check`
  still passes.
* Intentional LuCI form change → regenerate the snapshots:

  ```sh
  node tests/luci-form-snapshot.js . node   > tests/snapshots/node.json
  node tests/luci-form-snapshot.js . server > tests/snapshots/server.json
  ```
