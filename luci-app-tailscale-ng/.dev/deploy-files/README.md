# Deploy Files

The [deploy-files.sh](deploy-files.sh) script deploys working-tree application changes to a test router without building a package. It copies mapped files, applies and verifies permissions, and runs the application's post-deploy steps.

Run the commands below from the repository root in Bash (Git Bash on Windows).

## Requirements

- Bash, Git and the OpenSSH tools required by [Router SSH](../router-ssh/README.md).
- An OpenWrt router with LuCI and `tailscale` installed.

## Setup

Configure router access following [Router SSH Setup](../router-ssh/README.md#setup). Deployment uses its target config, keys and authentication flow.

## Usage

Deploy the mapped files:

```bash
bash .dev/deploy-files/deploy-files.sh
```

The default `deploy` mode validates the mapping and router requirements, copies files, applies and verifies permissions, then substitutes the application version, runs the application's UCI defaults and restarts `rpcd`. Existing application configuration is preserved. Dependencies are not installed.

Add `--interactive` in your own terminal if router access needs password-based key installation. The option is passed to Router SSH; ordinary runs never prompt for passwords.

Use [Router SSH](../router-ssh/README.md#usage) directly to run commands or scripts, upload or download other files, or keep a shell session open.

## Verification

Review the output for copied and preserved files and failed operations. Check that the updated LuCI page loads, settings and login are preserved, and the Tailscale service works.

## Configuration

Each row in [mapping.tsv](mapping.tsv) contains tab-separated columns:

1. Local path relative to `.dev/deploy-files/`.
2. Absolute destination file path on the router.
3. File permissions, such as `644` or `755`.
4. Policy: `overwrite` (default if omitted) or `keep-if-exists`.

`keep-if-exists` copies only missing files; a failed remote check stops deployment. Blank lines, `#` comments and extra tabs for alignment are supported. Duplicate destinations are rejected.

Router requirements and post-deploy commands are defined at the top of [deploy-files.sh](deploy-files.sh). Connection settings belong in Router SSH's local `target.env`.

## Cleanup

Run `bash .dev/deploy-files/deploy-files.sh clean` to remove mapped `overwrite` files from the router. It preserves `keep-if-exists` files and does not restore a previous installation. Failed deployments may leave partially updated files; review the error before repeating the operation.
