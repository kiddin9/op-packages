# Utils Structure

The first directory level shows dependency direction. The second level shows
the feature or base capability.

Dependency direction:

`actions -> feature -> base`

Current structure:

- `actions/save-apply`: Save & Apply orchestration, prechecks, and stale generated file cleanup.
- `feature/shunt`: shunt UCI section parsing, shunt rule parsing, and shunt config file generation.
- `feature/proxy`: proxy node UCI section parsing and generated proxy config files.
- `feature/firewall`: firewall form helpers and nft rules viewer behavior.
- `feature/log`: log page data sources, actions, and rendering helpers.
- `feature/overview`: overview page service actions and connectivity test behavior.
- `feature/rule`: rule update and rule query panel behavior.
- `base/luci`: LuCI-facing helpers for form controls, service status, UCI helpers, validation, and notifications.
- `base/files`: generated file paths, file content normalization, and JSON output helpers.

Core adapter selection lives in `core/adapter.ts`, next to the concrete core
builders.

Public utility APIs should export one `XxxUtils` object from the bottom of the
file. Keep standalone functions private to the file unless there is a strong
reason to expose them.

Boundary rules:

- `base` must not import `feature`, `actions`, `core`, or `views`.
- `feature/*/section.ts` should not import `core/adapter.ts` or `actions`.
- `feature/*/config-file.ts` may import `core/adapter.ts`.
- `actions` may compose `feature`, `base`, and `core`, but must not import `views`.

If parsing code needs config generation or save/apply behavior, move that code
into the feature's `config-file.ts` or into `actions/save-apply` instead of
importing back into `section.ts`.
