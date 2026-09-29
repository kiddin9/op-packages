#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MAPPING_FILE="$SCRIPT_DIR/mapping.tsv"
TARGET_ENV_FILE="$SCRIPT_DIR/target.env"
DEFAULT_PROJECT_KEY="$SCRIPT_DIR/.ssh/id_ed25519"
RUNTIME_KEY_TO_CLEAN=""

declare -a MAP_SRC=()
declare -a MAP_DST=()
declare -a MAP_MODE=()

POST_SYNC_COMMANDS=(
  "/etc/init.d/rpcd restart >/dev/null 2>&1 || true"
)

usage() {
  cat <<'EOF'
Usage:
  ./deploy/deploy.sh
  ./deploy/deploy.sh deploy
  ./deploy/deploy.sh clean
EOF
}

log() { printf '%s\n' "$*"; }
step() { printf '[STEP] %s\n' "$*"; }

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_tty() { [[ -t 0 && -t 1 ]]; }

remote_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

cleanup_runtime_key() {
  if [[ -n "$RUNTIME_KEY_TO_CLEAN" && -f "$RUNTIME_KEY_TO_CLEAN" ]]; then
    rm -f "$RUNTIME_KEY_TO_CLEAN" 2>/dev/null || true
  fi
}

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
  [[ -n "$ROUTER_PORT" ]] || die "ROUTER_PORT is required in $TARGET_ENV_FILE"
}

resolve_key_path() {
  local p
  if [[ -n "$SSH_KEY_PATH" ]]; then
    p="$SSH_KEY_PATH"
  else
    p="$DEFAULT_PROJECT_KEY"
  fi
  if [[ "$p" != /* ]]; then
    p="$APP_ROOT/$p"
  fi
  printf '%s' "$p"
}

confirm_generate_key() {
  local path="$1"
  if [[ "${DEPLOY_AUTO_YES:-0}" == "1" ]]; then
    return 0
  fi
  if ! is_tty; then
    die "SSH key is missing: $path. Generate it manually: ssh-keygen -t ed25519 -N '' -f '$path' -C 'luci-app-tailscale-deploy'"
  fi
  printf 'Project SSH key not found: %s\n' "$path"
  printf 'Generate it now? [y/N]: '
  local answer
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || die "SSH key generation declined. Aborting."
}

ensure_local_key() {
  local key_path="$1"
  local key_dir
  key_dir="$(dirname -- "$key_path")"
  mkdir -p "$key_dir"
  if [[ ! -f "$key_path" ]]; then
    confirm_generate_key "$key_path"
    ssh-keygen -t ed25519 -N "" -f "$key_path" -C "luci-app-tailscale-deploy" >/dev/null
    log "Generated SSH key: $key_path"
  fi
  [[ -f "${key_path}.pub" ]] || die "Public key is missing: ${key_path}.pub"
}

runtime_key_path() {
  local key_path="$1"
  local perm
  perm="$(stat -c '%a' "$key_path" 2>/dev/null || true)"
  if [[ "$perm" == "600" || "$perm" == "400" ]]; then
    printf '%s' "$key_path"
    return 0
  fi
  local runtime_dir="$HOME/.ssh"
  local runtime_key="$runtime_dir/luci-app-tailscale-deploy-${$}.key"
  mkdir -p "$runtime_dir"
  cat "$key_path" > "$runtime_key"
  chmod 700 "$runtime_dir" 2>/dev/null || true
  chmod 600 "$runtime_key" 2>/dev/null || true
  RUNTIME_KEY_TO_CLEAN="$runtime_key"
  printf '%s' "$runtime_key"
}

build_ssh_opts() {
  local key_path="$1"
  SSH_OPTS=(
    -p "$ROUTER_PORT"
    -i "$key_path"
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o ConnectionAttempts=1
  )
  SCP_OPTS=(
    -P "$ROUTER_PORT"
    -i "$key_path"
    -p
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o ConnectionAttempts=1
  )
}

remote() { ssh "${SSH_OPTS[@]}" "$ROUTER_USER@$ROUTER_HOST" "$1"; }

print_manual_key_install() {
  local key_path="$1"
  local pub
  pub="$(cat "${key_path}.pub")"
  printf '\nManual SSH key installation required for %s@%s.\n' "$ROUTER_USER" "$ROUTER_HOST" >&2
  printf 'Run on router:\n' >&2
  printf 'mkdir -p /etc/dropbear\n' >&2
  printf 'touch /etc/dropbear/authorized_keys\n' >&2
  printf "grep -qxF %s /etc/dropbear/authorized_keys || echo %s >> /etc/dropbear/authorized_keys\n" "$(remote_quote "$pub")" "$(remote_quote "$pub")" >&2
  printf 'chmod 700 /etc/dropbear\n' >&2
  printf 'chmod 600 /etc/dropbear/authorized_keys\n\n' >&2
  printf 'Public key:\n%s\n\n' "$pub" >&2
}

ensure_router_key_auth() {
  local key_path="$1"
  local pub
  pub="$(cat "${key_path}.pub")"
  if remote "true" >/dev/null 2>&1; then
    return 0
  fi
  if ssh -p "$ROUTER_PORT" -o ConnectTimeout=8 -o ConnectionAttempts=1 "$ROUTER_USER@$ROUTER_HOST" \
    "mkdir -p /etc/dropbear; touch /etc/dropbear/authorized_keys; grep -qxF $(remote_quote "$pub") /etc/dropbear/authorized_keys || echo $(remote_quote "$pub") >> /etc/dropbear/authorized_keys; chmod 700 /etc/dropbear; chmod 600 /etc/dropbear/authorized_keys" >/dev/null 2>&1; then
    if remote "true" >/dev/null 2>&1; then
      log "Project key published to router: ${key_path}.pub"
      return 0
    fi
  fi
  print_manual_key_install "$key_path"
  die "Router key authentication is not configured for key: $key_path"
}

load_mapping() {
  [[ -f "$MAPPING_FILE" ]] || die "Mapping file is missing: $MAPPING_FILE"
  MAP_SRC=()
  MAP_DST=()
  MAP_MODE=()

  local line_no=0 line src dst mode src_abs
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue

    IFS=$'\t' read -r src dst mode _extra <<<"$line"
    src="$(trim "${src:-}")"
    dst="$(trim "${dst:-}")"
    mode="$(trim "${mode:-}")"

    [[ -n "$src" && -n "$dst" && -n "$mode" ]] || die "Invalid mapping at line $line_no in $MAPPING_FILE"
    [[ "$dst" == /* ]] || die "Destination path must be absolute at line $line_no: $dst"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "Invalid mode at line $line_no: $mode"

    src_abs="$SCRIPT_DIR/$src"
    [[ -f "$src_abs" ]] || die "Source file not found at line $line_no: $src_abs"

    MAP_SRC+=("$src")
    MAP_DST+=("$dst")
    MAP_MODE+=("$mode")
  done <"$MAPPING_FILE"

  [[ ${#MAP_SRC[@]} -gt 0 ]] || die "Mapping has no entries: $MAPPING_FILE"
}

validate_git_exec_bits() {
  local i src mode repo_rel git_mode
  for ((i=0; i<${#MAP_SRC[@]}; i++)); do
    src="${MAP_SRC[$i]}"
    mode="${MAP_MODE[$i]}"
    [[ "$mode" == "755" || "$mode" == "0755" ]] || continue
    repo_rel="${src#../}"
    git_mode="$(git -C "$APP_ROOT" ls-files --stage -- "$repo_rel" | awk '{print $1}')"
    [[ -n "$git_mode" ]] || die "Expected executable file is not tracked by git: $repo_rel"
    [[ "$git_mode" == "100755" ]] || die "Expected git mode 100755 for $repo_rel, got $git_mode"
  done
}

ensure_remote_dirs() {
  local i dir
  for ((i=0; i<${#MAP_DST[@]}; i++)); do
    dir="$(dirname -- "${MAP_DST[$i]}")"
    remote "mkdir -p $(remote_quote "$dir")"
  done
}

copy_files() {
  local i src_abs dst
  step "Copy: ${#MAP_SRC[@]} files -> target"
  ensure_remote_dirs
  for ((i=0; i<${#MAP_SRC[@]}; i++)); do
    src_abs="$SCRIPT_DIR/${MAP_SRC[$i]}"
    dst="${MAP_DST[$i]}"
    log "COPY ${MAP_SRC[$i]} -> $dst"
    scp "${SCP_OPTS[@]}" "$src_abs" "$ROUTER_USER@$ROUTER_HOST:$dst" >/dev/null
  done
}

symbolic_to_octal() {
  local s="$1" p d1=0 d2=0 d3=0
  p="${s:1:9}"
  [[ "${p:0:1}" == "r" ]] && d1=$((d1 + 4))
  [[ "${p:1:1}" == "w" ]] && d1=$((d1 + 2))
  [[ "${p:2:1}" =~ [xst] ]] && d1=$((d1 + 1))
  [[ "${p:3:1}" == "r" ]] && d2=$((d2 + 4))
  [[ "${p:4:1}" == "w" ]] && d2=$((d2 + 2))
  [[ "${p:5:1}" =~ [xst] ]] && d2=$((d2 + 1))
  [[ "${p:6:1}" == "r" ]] && d3=$((d3 + 4))
  [[ "${p:7:1}" == "w" ]] && d3=$((d3 + 2))
  [[ "${p:8:1}" =~ [xt] ]] && d3=$((d3 + 1))
  printf '%d%d%d' "$d1" "$d2" "$d3"
}

remote_mode() {
  local dst="$1" out
  out="$(remote "if command -v stat >/dev/null 2>&1; then stat -c '%a' $(remote_quote "$dst") 2>/dev/null; else ls -ld $(remote_quote "$dst") 2>/dev/null | awk '{print \$1}'; fi" || true)"
  out="$(printf '%s' "$out" | tr -d '\r\n')"
  if [[ "$out" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s' "${out#0}"
    return 0
  fi
  if [[ "$out" =~ ^[-dlcbps][rwxstST-]{9}$ ]]; then
    symbolic_to_octal "$out"
    return 0
  fi
  printf ''
}

set_perms() {
  step "Permissions: set modes for ${#MAP_DST[@]} files on target"
  local i dst expected actual normalized
  for ((i=0; i<${#MAP_DST[@]}; i++)); do
    dst="${MAP_DST[$i]}"
    expected="${MAP_MODE[$i]}"
    normalized="${expected#0}"
    actual="$(remote_mode "$dst")"
    if [[ -z "$actual" ]]; then
      log "CHMOD $normalized $dst"
      remote "chmod $expected $(remote_quote "$dst")"
      continue
    fi
    if [[ "$actual" != "$normalized" ]]; then
      log "CHMOD $normalized $dst"
      remote "chmod $expected $(remote_quote "$dst")"
    else
      log "MODE_OK $normalized $dst"
    fi
  done
}

run_post_sync() {
  step "Post: running post-sync commands"
  local cmd
  for cmd in "${POST_SYNC_COMMANDS[@]}"; do
    log "POST $cmd"
    remote "$cmd"
  done
}

run_uci_defaults() {
  step "Defaults: running /etc/uci-defaults/40_luci-app-tailscale-ng"
  remote "if [ -f /etc/uci-defaults/40_luci-app-tailscale-ng ]; then sh /etc/uci-defaults/40_luci-app-tailscale-ng; else echo 'SKIP: /etc/uci-defaults/40_luci-app-tailscale-ng not found'; fi"
}

clean_target_files() {
  step "Clean: remove mapped files on target"
  local i dst
  for ((i=0; i<${#MAP_DST[@]}; i++)); do
    dst="${MAP_DST[$i]}"
    log "REMOVE $dst"
    remote "rm -f $(remote_quote "$dst")"
  done
}

main() {
  trap cleanup_runtime_key EXIT
  local run_mode="deploy"
  if [[ $# -gt 1 ]]; then
    die "Too many arguments. Use: ./deploy/deploy.sh [deploy|clean]"
  fi
  if [[ $# -eq 1 ]]; then
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      deploy|clean)
        run_mode="$1"
        ;;
      *)
        die "Unknown mode: $1. Use: deploy or clean"
        ;;
    esac
  fi

  require_cmd ssh
  require_cmd scp
  require_cmd git

  load_mapping
  validate_git_exec_bits
  load_target_env

  local active_key effective_key
  active_key="$(resolve_key_path)"
  ensure_local_key "$active_key"
  effective_key="$(runtime_key_path "$active_key")"
  build_ssh_opts "$effective_key"
  ensure_router_key_auth "$active_key"

  step "Auth: checking SSH access to $ROUTER_USER@$ROUTER_HOST"
  remote "true" >/dev/null
  if [[ "$run_mode" == "clean" ]]; then
    clean_target_files
    log "DONE: clean completed successfully"
    return 0
  fi
  copy_files
  set_perms
  run_uci_defaults
  run_post_sync
  log "DONE: deploy pipeline completed successfully"
}

main "$@"
