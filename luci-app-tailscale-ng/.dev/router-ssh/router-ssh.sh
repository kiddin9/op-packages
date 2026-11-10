#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TARGET_ENV_FILE="$SCRIPT_DIR/target.env"
DEFAULT_PROJECT_KEY="$SCRIPT_DIR/.ssh/id_ed25519"
SSH_KEY_COMMENT="luci-app-tailscale-ssh"
EFFECTIVE_KEY_PATH=""
AUTH_ERROR_FILE=""
AUTH_METHOD=""
SELECTED_KEY=""
PUBLIC_KEY=""
INTERACTIVE=0
OPERATION=""
EXEC_COMMAND=""
EXEC_STDIN=0
RECURSIVE=0
OP_ARGS=()
SESSION_DIR=""
CLIENT_LOG=""
IDENTITY_OPTS=()
IDENTITY_ORIGINALS=()
IDENTITY_INDEX=0

usage() {
  cat <<'EOF'
Usage:
  router-ssh.sh [--interactive] exec-command [--] 'command on the router'
  router-ssh.sh [--interactive] exec-command < script.sh
  router-ssh.sh [--interactive] put-files [-r|--recursive] [--] LOCAL... REMOTE
  router-ssh.sh [--interactive] get-files [-r|--recursive] [--] REMOTE... LOCAL
  router-ssh.sh [--interactive] open-session

Read target.env next to this script. Remote file paths must be absolute.
Multiple sources require a destination directory. -r includes directories.
SSH tries the configured identities during the actual operation.
There is no preliminary network probe, and operations are never retried after authentication.
open-session keeps one remote shell until exit or EOF. It uses a terminal when
stdin and stdout are terminals; otherwise commands can be streamed over stdin.
Ordinary runs never prompt for passwords; --interactive requires your terminal.
Exit codes: 1 = local error, 2 = user action required. Commands and sessions
preserve the remote status (255 also indicates an SSH failure); transfers return SCP status.
EOF
}

log() { printf '%s\n' "$*" >&2; }
step() { printf '[STEP] %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
is_tty() { [[ -t 0 && -t 1 ]]; }
remote_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
load_target_env() {
  [[ -f "$TARGET_ENV_FILE" ]] || die "Target config is missing: $TARGET_ENV_FILE"
  # shellcheck source=/dev/null
  source "$TARGET_ENV_FILE"

  ROUTER_HOST="$(trim "${ROUTER_HOST:-}")"
  ROUTER_USER="$(trim "${ROUTER_USER:-root}")"
  ROUTER_PORT="$(trim "${ROUTER_PORT:-22}")"
  SSH_KEY_PATH="$(trim "${SSH_KEY_PATH:-}")"

  [[ -n "$ROUTER_HOST" ]] || die "ROUTER_HOST is required in $TARGET_ENV_FILE"
  [[ -n "$ROUTER_USER" ]] || die "ROUTER_USER is required in $TARGET_ENV_FILE"
  [[ "$ROUTER_HOST" =~ ^[a-zA-Z0-9_:][a-zA-Z0-9_.:%-]*$ ]] || die "Invalid ROUTER_HOST: $ROUTER_HOST"
  [[ "$ROUTER_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]] || die "Invalid ROUTER_USER: $ROUTER_USER"
  [[ "$ROUTER_PORT" =~ ^[0-9]{1,5}$ ]] || die "Invalid ROUTER_PORT: $ROUTER_PORT"
  (( 10#$ROUTER_PORT >= 1 && 10#$ROUTER_PORT <= 65535 )) || die "ROUTER_PORT must be between 1 and 65535"
}

resolve_key_path() {
  local_path "${SSH_KEY_PATH:-$DEFAULT_PROJECT_KEY}" "$APP_ROOT"
}

prepare_runtime_key() {
  local key_path="$1" target
  IDENTITY_INDEX=$((IDENTITY_INDEX + 1))
  target="$SESSION_DIR/identity-$IDENTITY_INDEX"
  cat "$key_path" > "$target"
  chmod 600 "$target"
  if [[ -f "${key_path}.pub" ]]; then printf '%s\n' "$(< "${key_path}.pub")" > "${target}.pub"; fi
  if [[ -f "${key_path}-cert.pub" ]]; then printf '%s\n' "$(< "${key_path}-cert.pub")" > "${target}-cert.pub"; fi
  EFFECTIVE_KEY_PATH="$target"
  if command -v cygpath >/dev/null 2>&1; then EFFECTIVE_KEY_PATH="$(cygpath -w "$target")"; fi
}

build_ssh_opts() {
  SSH_OPTS=(-p "$ROUTER_PORT" "${CONNECTION_OPTS[@]}" -o BatchMode=yes -o PreferredAuthentications=publickey -o LogLevel=DEBUG1 "${IDENTITY_OPTS[@]}")
  SCP_OPTS=(-O -P "$ROUTER_PORT" -p -S "$SESSION_DIR/ssh-client" "${CONNECTION_OPTS[@]}" -o BatchMode=yes -o PreferredAuthentications=publickey -o LogLevel=DEBUG1 "${IDENTITY_OPTS[@]}")
}

ensure_public_key() {
  local key_path="$1" public_file="${1}.pub"
  require_cmd ssh-keygen
  if [[ ! -f "$key_path" ]]; then
    [[ "$key_path" == "$DEFAULT_PROJECT_KEY" ]] || die "Configured SSH key does not exist: $key_path"
    # Key generation is the last resort, after every existing access method failed.
    (umask 077; mkdir -p "$(dirname -- "$key_path")"; ssh-keygen -t ed25519 -N "" -f "$key_path" -C "$SSH_KEY_COMMENT" > /dev/null)
    log "Generated project key: $key_path"
  fi
  prepare_runtime_key "$key_path"
  if PUBLIC_KEY="$(ssh-keygen -y -P '' -f "$EFFECTIVE_KEY_PATH" 2> "$AUTH_ERROR_FILE")"; then
    :
  elif [[ "$INTERACTIVE" == 1 ]]; then
    log "Unlock the existing SSH key in this terminal if prompted."
    PUBLIC_KEY="$(ssh-keygen -y -f "$EFFECTIVE_KEY_PATH")" || die "Cannot read the existing SSH key: $key_path"
  elif [[ -f "$public_file" ]] && ssh-keygen -lf "$public_file" > /dev/null 2>&1; then
    PUBLIC_KEY="$(cat "$public_file")"
    log "The existing key may need unlocking in ssh-agent before deployment can succeed."
  else
    cat "$AUTH_ERROR_FILE" >&2
    printf 'ACTION REQUIRED: cannot read the public part of the existing key. Unlock it in ssh-agent or use --interactive in your terminal. The requested operation has not started.\n' >&2
    exit 2
  fi
  [[ "$(printf '%s\n' "$PUBLIC_KEY" | awk 'NF { n++ } END { print n+0 }')" == 1 ]] || die "Expected one public key: $public_file"
  # Derive a missing .pub file instead of replacing an existing private key.
  if [[ ! -f "$public_file" ]] || [[ "$(cat "$public_file")" != "$PUBLIC_KEY" ]]; then
    (umask 077; printf '%s\n' "$PUBLIC_KEY" > "$public_file")
  fi
}

print_retry_command() {
  printf '  bash %q' "$SCRIPT_DIR/router-ssh.sh" >&2
  [[ "${1:-}" != interactive ]] || printf ' --interactive' >&2
  printf ' %s' "$OPERATION" >&2
  [[ "$RECURSIVE" == 0 ]] || printf ' --recursive' >&2
  printf ' --' >&2
  if [[ "$EXEC_STDIN" == 1 ]]; then
    printf ' < your-script.sh' >&2
  else
    if [[ ${#OP_ARGS[@]} -gt 0 ]]; then printf ' %q' "${OP_ARGS[@]}" >&2; fi
  fi
  printf '\n' >&2
}
print_access_help() {
  local key_path="$1"
  printf '\nACTION REQUIRED: SSH access to %s@%s:%s is not configured.\n' "$ROUTER_USER" "$ROUTER_HOST" "$ROUTER_PORT" >&2
  printf 'The requested operation has not started.\nPublic key file: %s.pub\n\n%s\n\n' "$key_path" "$PUBLIC_KEY" >&2
  printf 'Option 1: open LuCI -> System -> Administration -> SSH-Keys.\nPaste the public key shown above, click Add key, then repeat:\n' >&2
  print_retry_command
  printf '\nOption 2: run in your own terminal and enter the router password when SSH asks:\n' >&2
  if [[ "$EXEC_STDIN" == 1 ]]; then
    printf '  bash %q --interactive exec-command true\n' "$SCRIPT_DIR/router-ssh.sh" >&2
    printf 'Then repeat the original script invocation.\n' >&2
  else
    print_retry_command interactive
  fi
}

install_key_interactively() {
  local command
  log "SSH access is not configured. Enter the router password in this terminal when SSH asks."
  command="set -e; umask 077; mkdir -p /etc/dropbear; touch /etc/dropbear/authorized_keys; if grep -qxF $(remote_quote "$PUBLIC_KEY") /etc/dropbear/authorized_keys; then :; else result=\$?; [ \"\$result\" -eq 1 ] || exit \"\$result\"; printf '%s\\n' $(remote_quote "$PUBLIC_KEY") >> /etc/dropbear/authorized_keys; fi; chmod 700 /etc/dropbear; chmod 600 /etc/dropbear/authorized_keys"
  # shellcheck disable=SC2029
  if ! LC_ALL=C ssh -p "$ROUTER_PORT" "${CONNECTION_OPTS[@]}" -o BatchMode=no -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no "$ROUTER_USER@$ROUTER_HOST" "$command"; then
    die "Interactive SSH key installation failed. The requested operation has not started."
  fi
  log "Public key installed. Continuing the requested operation without a separate probe."
}

run_remote_command() {
  local command="$EXEC_COMMAND" status=0
  [[ "$EXEC_STDIN" == 0 ]] || command='sh -s'
  step "Exec: running the remote command ($AUTH_METHOD)"
  # Preserve user stdin and remote output without executing a preliminary probe.
  # shellcheck disable=SC2029
  LC_ALL=C ssh -E "$CLIENT_LOG" "${SSH_OPTS[@]}" "$ROUTER_USER@$ROUTER_HOST" "$command" || status=$?
  return "$status"
}

run_open_session() {
  local -a options=()
  local i status=0
  # The common non-terminal setting belongs to individual commands and SCP.
  # An actual shell session chooses its terminal mode from the caller's streams.
  for ((i=0; i<${#SSH_OPTS[@]}; i++)); do
    if [[ "${SSH_OPTS[$i]}" == -o && "${SSH_OPTS[$((i+1))]:-}" == RequestTTY=no ]]; then
      i=$((i+1))
      continue
    fi
    options+=("${SSH_OPTS[$i]}")
  done
  if is_tty; then
    step "Session: opening a terminal on $ROUTER_USER@$ROUTER_HOST; use exit or Ctrl+D to close"
    LC_ALL=C ssh -E "$CLIENT_LOG" "${options[@]}" -tt "$ROUTER_USER@$ROUTER_HOST" || status=$?
  else
    step "Session: opening a command stream on $ROUTER_USER@$ROUTER_HOST; use exit or EOF to close"
    LC_ALL=C ssh -E "$CLIENT_LOG" "${options[@]}" -T "$ROUTER_USER@$ROUTER_HOST" 'sh -s' || status=$?
  fi
  return "$status"
}

local_path() {
  local value="$1" base="${2:-$PWD}"
  if command -v cygpath >/dev/null 2>&1; then value="$(cygpath -u "$value")"; fi
  [[ "$value" == /* ]] || value="$base/$value"
  printf '%s' "$value"
}

remote_source_path() {
  # Legacy SCP checks returned names against this path as a shell pattern.
  # Backslash escapes protect both the remote shell and that filename check.
  local value="$1" character result="" i
  for ((i=0; i<${#value}; i++)); do
    character="${value:i:1}"
    case "$character" in
      [a-zA-Z0-9_./-]) result+="$character" ;;
      *) result+="\\$character" ;;
    esac
  done
  printf '%s' "$result"
}

transfer_files() {
  local host="$ROUTER_HOST" destination source status=0
  local -a files=() options=()
  [[ "$host" != *:* ]] || host="[$host]"
  options=("${SCP_OPTS[@]}")
  [[ "$RECURSIVE" == 0 ]] || options+=(-r)
  destination="${OP_ARGS[${#OP_ARGS[@]}-1]}"
  if [[ "$OPERATION" == put-files ]]; then
    for source in "${OP_ARGS[@]:0:${#OP_ARGS[@]}-1}"; do files+=("$(local_path "$source")"); done
    destination="$ROUTER_USER@$host:$(remote_quote "$destination")"
  else
    for source in "${OP_ARGS[@]:0:${#OP_ARGS[@]}-1}"; do files+=("$ROUTER_USER@$host:$(remote_source_path "$source")"); done
    destination="$(local_path "$destination")"
  fi
  step "$OPERATION: transferring ${#files[@]} source(s) ($AUTH_METHOD)"
  LC_ALL=C scp "${options[@]}" -- "${files[@]}" "$destination" || status=$?
  return "$status"
}

parse_args() {
  if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then usage; exit 0; fi
  if [[ "${1:-}" == --interactive ]]; then INTERACTIVE=1; shift; fi
  OPERATION="${1:-}"
  [[ $# -gt 0 ]] || { usage >&2; exit 1; }
  shift
  case "$OPERATION" in exec-command|put-files|get-files|open-session) ;; *) die "Unknown command: $OPERATION. Use --help." ;; esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interactive) INTERACTIVE=1; shift ;;
      -r|--recursive)
        [[ "$OPERATION" == put-files || "$OPERATION" == get-files ]] || die "--recursive only applies to file transfers"
        RECURSIVE=1; shift
        ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  OP_ARGS=("$@")
  if [[ "$OPERATION" == open-session ]]; then
    [[ $# == 0 ]] || die "open-session accepts no command arguments; send commands through stdin"
  elif [[ "$OPERATION" == exec-command ]]; then
    [[ $# -le 1 ]] || die "exec-command accepts one quoted command, or a script on stdin."
    if [[ $# == 0 ]]; then
      EXEC_STDIN=1
      [[ ! -t 0 ]] || die "Provide a command, or redirect a script on stdin."
    else
      EXEC_COMMAND="$1"
      [[ -n "$EXEC_COMMAND" ]] || die "The remote command must not be empty"
    fi
  else
    [[ $# -ge 2 ]] || die "$OPERATION requires source(s) and a destination"
    require_cmd scp
    local source destination="${OP_ARGS[${#OP_ARGS[@]}-1]}"
    for source in "${OP_ARGS[@]}"; do
      [[ "$source" != *$'\n'* && "$source" != *$'\r'* ]] || die "Legacy SCP does not support filenames containing newlines"
    done
    if [[ "$OPERATION" == put-files ]]; then
      [[ "$destination" == /* ]] || die "Remote destination must be an absolute path"
      for source in "${OP_ARGS[@]:0:${#OP_ARGS[@]}-1}"; do
        source="$(local_path "$source")"
        if [[ -d "$source" ]]; then
          [[ "$RECURSIVE" == 1 ]] || die "Directory upload requires --recursive: $source"
        else
          [[ -f "$source" ]] || die "Local source does not exist: $source"
        fi
      done
    else
      for source in "${OP_ARGS[@]:0:${#OP_ARGS[@]}-1}"; do [[ "$source" == /* ]] || die "Remote source must be an absolute path: $source"; done
    fi
  fi
}

main() {
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  parse_args "$@"
  if [[ "$INTERACTIVE" == 1 ]] && ! is_tty; then
    printf 'ACTION REQUIRED: --interactive needs your own terminal. The requested operation has not started.\n' >&2
    exit 2
  fi
  require_cmd ssh
  load_target_env
  init_direct_state
  prepare_identities
  local status=0
  run_operation || status=$?
  [[ "$status" != 0 ]] || return 0
  if ! authentication_rejected; then report_failure "$status"; return "$status"; fi

  # Only a client-side authentication rejection proves the operation never ran.
  ensure_public_key "$SELECTED_KEY"
  if [[ "$INTERACTIVE" == 0 ]]; then print_access_help "$SELECTED_KEY"; exit 2; fi
  install_key_interactively
  prepare_identities
  status=0
  run_operation || status=$?
  [[ "$status" != 0 ]] || return 0
  if authentication_rejected; then print_access_help "$SELECTED_KEY"; exit 2; fi
  report_failure "$status"
  return "$status"
}

init_direct_state() {
  mkdir -p "$HOME/.ssh"
  SESSION_DIR="$(mktemp -d "$HOME/.ssh/router-ssh.XXXXXX")"
  CLIENT_LOG="$SESSION_DIR/client.log"
  AUTH_ERROR_FILE="$SESSION_DIR/key-error.log"
  export ROUTER_SSH_CLIENT_LOG="$CLIENT_LOG"
  if [[ "$OPERATION" == put-files || "$OPERATION" == get-files ]]; then
    ROUTER_SSH_REAL_CLIENT="$(command -v ssh)"
    export ROUTER_SSH_REAL_CLIENT
    # shellcheck disable=SC2016 # These variables belong to the generated wrapper.
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'exec "$ROUTER_SSH_REAL_CLIENT" -E "$ROUTER_SSH_CLIENT_LOG" "$@"' > "$SESSION_DIR/ssh-client"
    chmod 700 "$SESSION_DIR/ssh-client"
  fi
}

cleanup() {
  if [[ -n "$SESSION_DIR" ]]; then
    rm -f -- "$SESSION_DIR/"*
    rmdir -- "$SESSION_DIR"
  fi
  return 0
}

add_identity() {
  local candidate="$1" copy_key="${2:-0}" previous
  [[ "$candidate" != \~/* ]] || candidate="$HOME/${candidate:2}"
  if [[ "$candidate" == [a-zA-Z]:* ]] && command -v cygpath >/dev/null 2>&1; then candidate="$(cygpath -u "$candidate")"; fi
  [[ -f "$candidate" ]] || return 0
  for previous in "${IDENTITY_ORIGINALS[@]}"; do [[ "$previous" != "$candidate" ]] || return 0; done
  IDENTITY_ORIGINALS+=("$candidate")
  EFFECTIVE_KEY_PATH="$candidate"
  if [[ "$copy_key" == 1 ]]; then prepare_runtime_key "$candidate"; fi
  IDENTITY_OPTS+=(-i "$EFFECTIVE_KEY_PATH")
}

prepare_identities() {
  local explicit="" line
  IDENTITY_OPTS=()
  IDENTITY_ORIGINALS=()
  CONNECTION_OPTS=(
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=8
    -o ConnectionAttempts=1
    # Send SSH keepalives after 15s of silence; allow 3 unanswered requests.
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=3
    -o ControlMaster=no
    -o ControlPath=none
    -o ClearAllForwardings=yes
    -o RequestTTY=no
  )
  if [[ -n "$SSH_KEY_PATH" ]]; then
    explicit="$(resolve_key_path)"
    [[ -f "$explicit" ]] || die "SSH_KEY_PATH does not point to a file: $explicit. Correct the config; no key was generated."
    add_identity "$explicit" 1
  fi
  add_identity "$DEFAULT_PROJECT_KEY" 1
  # -G evaluates local SSH configuration without making a network connection.
  # Preserve default identity files which adding an explicit -i would replace.
  if ! LC_ALL=C ssh -G -p "$ROUTER_PORT" "${CONNECTION_OPTS[@]}" "$ROUTER_USER@$ROUTER_HOST" > "$SESSION_DIR/effective-config" 2> "$AUTH_ERROR_FILE"; then
    cat "$AUTH_ERROR_FILE" >&2
    die "Cannot evaluate local SSH configuration"
  fi
  while IFS= read -r line; do
    case "$line" in identityfile\ *) add_identity "${line#identityfile }" ;; esac
  done < "$SESSION_DIR/effective-config"
  SELECTED_KEY="${explicit:-$DEFAULT_PROJECT_KEY}"
  AUTH_METHOD="SSH identities and agent"
  build_ssh_opts
}

run_operation() {
  : > "$CLIENT_LOG"
  case "$OPERATION" in
    exec-command) run_remote_command ;;
    open-session) run_open_session ;;
    put-files|get-files) transfer_files ;;
  esac
}

authentication_completed() {
  grep -Eq 'Authenticated to |Authentication succeeded \(' "$CLIENT_LOG"
}

authentication_rejected() {
  ! authentication_completed && grep -Eq 'Permission denied|Authentication failed|No more authentication methods' "$CLIENT_LOG"
}

report_failure() {
  local status="$1"
  if ! authentication_completed || [[ "$status" == 255 ]]; then
    grep -Ev '^(debug[123]: |Authenticated to )' "$CLIENT_LOG" >&2 || true
  fi
  if [[ "$status" == 255 ]]; then
    log "ERROR: SSH returned 255. The operation may have started; it was not retried."
  elif [[ "$OPERATION" == put-files || "$OPERATION" == get-files ]]; then
    log "ERROR: transfer failed; partial destination files may exist. It was not retried."
  fi
  return 0
}

main "$@"
