# Router SSH Tooling

The [router-ssh.sh](router-ssh.sh) script provides general-purpose SSH access for running commands and scripts, transferring files and working in an open remote shell. For application updates on a test router, use [Deploy Files](../deploy-files/README.md), which handles file deployment together with the application's required post-deploy steps.

Run the commands below from the repository root in Bash (Git Bash on Windows).

## Requirements

- Bash and an OpenSSH client (`ssh`). File transfers also need `scp`; key generation needs `ssh-keygen`.
- A reachable router with SSH access. Application packages and mapping files are not required.

## Setup

Create a local router config:

```bash
cp .dev/router-ssh/target.env.example .dev/router-ssh/target.env
```

Set `ROUTER_HOST`, `ROUTER_USER` and `ROUTER_PORT`. The template defaults to `root` on port `22`.

SSH tries the configured key, project key and normal SSH identities or agent during the actual operation. No separate network probe is performed. If authentication is rejected, the script preserves an existing key or creates a project key and prints its public part with installation instructions. Add it under **LuCI → System → Administration → SSH-Keys**, then repeat the operation.

Alternatively, add `--interactive` in your own terminal to install the public key using the router password and continue. Ordinary runs never prompt for passwords. Connection errors and failures after authentication do not cause automatic retries.

## Usage

### Individual Operations

```bash
bash .dev/router-ssh/router-ssh.sh exec-command 'logread -l 20'
bash .dev/router-ssh/router-ssh.sh exec-command < diagnostic.sh
bash .dev/router-ssh/router-ssh.sh put-files ./helper /tmp/helper
bash .dev/router-ssh/router-ssh.sh get-files /tmp/debug.log ./debug.log
```

Remote file paths must be absolute. Transfers accept multiple sources when the destination is a directory; add `--recursive` to copy directories. Individual commands preserve remote stdout, stderr and the exit status. Local connection messages go to stderr.

### Open Session

For multiple commands, prefer `open-session`: it keeps one SSH connection open without reauthenticating for each command.

```bash
bash .dev/router-ssh/router-ssh.sh open-session
```

In a terminal, this opens the router's normal interactive shell. Enter commands as needed and close it with `exit` or Ctrl+D. The working directory and variables persist within the session. Ctrl+C can interrupt a running remote command without closing the shell.

With redirected streams, the same mode runs `sh -s` without a prompt or terminal formatting. An agent can keep stdin open, send commands incrementally and read their output without reconnecting. Exit or close stdin to end the session. The process returns the shell's final exit status; individual command statuses can be read through `$?`.

File transfers remain independent `put-files` and `get-files` calls. They do not reuse the open shell. A disconnected session is not automatically reopened and its commands are not replayed.

## Verification

Run `exec-command 'uname -n'` to check the target. In an open session, verify the working directory with `pwd` and the last command's status with `echo $?`. A local setup error returns `1`, required user action returns `2`, and SSH may return `255` for a connection error or remote exit `255`.

## Configuration

- `SSH_KEY_PATH` — Optional key to include first; relative paths start at the repository root. On Windows, both `D:/...` and `D:\...` paths are accepted. An explicitly configured missing file is an error.
- `.ssh/id_ed25519` — Project key next to the script, used if present.

The script sets `ServerAliveInterval=15` and `ServerAliveCountMax=3` by default to detect unresponsive SSH connections.

Normal SSH configuration and agent access remain available. New host keys are accepted automatically; changed host keys stop the connection. Local `target.env` and `.ssh/` are ignored by the project's root `.gitignore`.

## Cleanup

Temporary key copies and SSH diagnostics are removed when the operation or session ends. Files transferred to the router remain until explicitly removed.
