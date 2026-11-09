# Changelog

## [0.2.2-r4] - 2026-09-08

- Require SafeShield 0.3.20 or newer.

## [0.2.2-r3] - 2026-09-02

- Require SafeShield 0.3.19 or newer.

## [0.2.2-r2] - 2026-08-30

- Require SafeShield 0.3.17 or newer.

## [0.2.2-r1] - 2026-08-30

- Require SafeShield 0.3.15 or newer.

## [0.2.1-r2] - 2026-08-30

- Localize all current SafeShield `summary.code` states in LuCI (`idle`, `ready`, `refreshing`, `degraded`, `error`, `paused`, and `disabled`).
- Fall back to the backend `summary.message` for unknown summary codes.
- Require SafeShield 0.3.14-r8 or newer for summary code support.

## [0.2.1-r1] - 2026-08-29

- Require SafeShield 0.3.13 or newer.

## [0.2.0-r1] - 2026-08-20

- Use the public `safeshield` ubus management API as the only SafeShield control plane.
- Remove direct LuCI UCI writes for SafeShield lifecycle, license and configuration.
- Add enable/disable and manual refresh actions to Overview.
- Show local-rule apply timestamps and the current fast-apply state from `safeshield.status`.
- Add a Local Rules page backed by `rules_list`, `rule_add` and `rule_delete`.
- Wait for `last_local_apply` / `last_local_apply_failure` after rule mutations so the UI distinguishes file persistence from active DNS application.
- Stop exposing obsolete/non-public options such as local rule paths and dnsmasq file/instance settings.
- Fix physical fingerprint fields to match the current SafeShield status schema.
- Require SafeShield 0.3.10 or newer.
