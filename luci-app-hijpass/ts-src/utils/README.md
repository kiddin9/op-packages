# Utils Structure

The first directory level shows dependency direction. The second level shows
the feature or base capability.

Dependency direction:

`actions -> feature -> base`

Current structure:

- `actions/save-apply`: Save & Apply orchestration, prechecks, and backend validation.
- `feature/shunt`: shunt UCI section parsing, rule validation, and editing.
- `feature/proxy`: proxy node editing, validation, and share links.
- `feature/config`: RPC snapshots for ucode JSON validation and preview, browser file draft storage, and file diffs.
- `feature/firewall`: firewall form helpers and nft rules viewer behavior.
- `feature/log`: log page data sources, actions, and rendering helpers.
- `feature/overview`: overview page service actions and connectivity test behavior.
- `feature/rule`: rule update and rule query panel behavior.
- `base/luci`: LuCI-facing helpers for form controls, service status, UCI helpers, validation, and notifications.
- `base/files`: JSON output helpers.

Proxy/shunt JSON construction lives in `root/usr/share/ucode/hijpass/coreconfig/`.
`backend.ts` wraps business RPC methods; the backend resolves file locations,
writes generated configurations, and delegates system operations to Shell.
Custom configuration editors remain user inputs.
`ts-src/modules/drafts.ts` coordinates session-scoped browser drafts with LuCI
Apply and Revert. Saving a file edit stores a browser draft; applying writes the
file through the authenticated `root/www/cgi-bin/hijpass-editor` endpoint.

Public utility APIs should export one `XxxUtils` object from the bottom of the
file. Keep standalone functions private to the file unless there is a strong
reason to expose them.

Boundary rules:

- `base` must not import `feature`, `actions`, or `views`.
- `feature/*/section.ts` should not import `actions`.
- `actions` may compose `feature` and `base`, but must not import `views`.

Configuration previews and save validation use `feature/config/backend.ts`.
Backend errors are surfaced by the existing notification/modal flow.
