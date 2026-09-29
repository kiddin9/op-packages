# Deploy Tooling

This folder contains a deploy workflow to push files on router for testing based on `bash + ssh/scp`.

## Files

- `.deploy/deploy.sh` - main deploy script (single pipeline mode)
- `.deploy/mapping.tsv` - explicit file mapping (`src -> dst -> mode`)
- `.deploy/target.env.example` - target configuration template
- `.deploy/target.env` - local router access settings (ignored by git)

## Requirements

- Bash (Linux/macOS, or Git Bash/WSL on Windows)
- OpenSSH client tools in PATH: `ssh`, `scp`
- Git in PATH (used to validate executable bit in repository index)
- SSH key access to router

## Mapping Format (`mapping.tsv`)

Each row contains three columns separated by one or more tabs:

1. local path relative to `.deploy/`
2. absolute remote path on router
3. mode (for example `644`, `755`)

Notes:

- Empty lines are allowed.
- Comment lines start with `#`.
- You can align columns using extra tab characters.

## Target Configuration (`target.env`)

Create local config first:

```bash
cp deploy/target.env.example deploy/target.env
```

Expected variables:

- `ROUTER_HOST`
- `ROUTER_USER`
- `ROUTER_PORT`
- `SSH_KEY_PATH` (optional)

## SSH Key Bootstrap

- If `SSH_KEY_PATH` is set, deploy uses that key.
- If `SSH_KEY_PATH` is empty, deploy uses project key `.deploy/.ssh/id_ed25519`.
- If the project key does not exist, deploy prompts to generate it on first run.
- Deploy tries to publish the public key to `/etc/dropbear/authorized_keys`.
- If auto-publish is not possible, deploy exits with exact manual commands to install the key on router.
- For non-interactive runs, set `.deploy_AUTO_YES=1` to auto-confirm key generation.

## Usage

Run from `luci-app-tailscale-ng`:

```bash
./deploy/deploy.sh
./deploy/deploy.sh deploy
./deploy/deploy.sh clean
```

Modes:
- `deploy` (default) - auth + copy + chmod + rpcd restart
- `clean` - auth + remove mapped target files only

## Behavior

- Running `./deploy/deploy.sh` is same as `./deploy/deploy.sh deploy`.
- Uploads mapped files via `scp -p`
- Applies `chmod` only when remote mode differs from expected mode
- Runs post-sync commands after copy/perms (deploy mode only)
- Post-sync commands are defined in `.deploy.sh` (currently `rpcd restart`)
