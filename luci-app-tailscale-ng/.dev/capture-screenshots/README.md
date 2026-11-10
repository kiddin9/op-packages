# Capture Screenshots

The [capture.mjs](capture.mjs) script regenerates README screenshots to keep them up to date as the application's LuCI interface evolves. It automatically captures the application tabs at a consistent width, with height determined by their content. Synthetic data replaces router-specific information to avoid exposing personal details or private network information.

Run the commands below from the repository root.

## Requirements

- Node.js 20 or newer, npm, Bash and the SSH tools required by [Router SSH](../router-ssh/README.md).
- A reachable OpenWrt 25 router with Tailscale NG installed and LuCI using English and the Bootstrap theme, accessible over HTTP.
- SSH access that can manage temporary `rpcd` sessions. The default Router SSH user is `root`.

## Setup

Configure access following [Router SSH Setup](../router-ssh/README.md#setup), then install the capture dependencies:

```shell
npm --prefix .dev/capture-screenshots ci --ignore-scripts
npm --prefix .dev/capture-screenshots exec -- playwright install chromium --only-shell
```

The deployed application JS must match the working tree, including the package version. Use [Deploy Files](../deploy-files/README.md) to update it before capture when needed.

## Usage

```shell
npm --prefix .dev/capture-screenshots run capture
```

Successful runs replace `docs/images/tailscale-ng-auth.png`, `docs/images/tailscale-ng-settings.png` and `docs/images/tailscale-ng-status.png` directly, updating the images referenced by the main README. Failed capture checks leave the existing PNGs unchanged. The technical report is saved to `.dev/capture-screenshots/report.json` and ignored by Git.

The script loads the router's HTML, styles, JS and English translations. It substitutes the page title and router brand, mocks RPC data, menu and release checks, and blocks unknown requests. Router configuration is preserved. A separate browser context and a temporary five-minute LuCI session are created for each run; the session is removed on exit.

## Verification

The run checks deployed JS, hostname replacement, page errors, horizontal overflow, configuration preservation and session cleanup. It captures each tab twice around a background status refresh and requires identical PNG hashes. Unknown HTTP/RPC requests are also checked for blocking.

Check `success: true` in `report.json` and review the three PNGs in `docs/images/` for complete content and synthetic values. Width is fixed; no height is imposed on the full-page images. Other LuCI themes, versions, languages or operating systems may render differently.

## Configuration

- `BASH_PATH` — Optional Bash executable. Windows defaults to Git Bash under `ProgramFiles`; other systems use `bash` from `PATH`.
- `LUCI_URL` — Optional HTTP origin, including a custom port. Defaults to `http://<ROUTER_HOST>` from Router SSH's `target.env`.

Synthetic devices, users, addresses and command outputs belong in `fixtures.mjs`. Keep the JSON and text responses consistent. Viewport width and browser settings are defined in `capture.mjs`; the package version is read from `Makefile`.

## Cleanup

Delete `.dev/capture-screenshots/report.json` to discard the technical report, or `.dev/capture-screenshots/node_modules/` to remove local dependencies. Both are ignored by Git. PNGs in `docs/images/` are tracked project documentation. Playwright stores its downloaded browser in the user's cache outside the repository.
