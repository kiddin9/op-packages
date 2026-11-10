#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
MAPPING_FILE="$SCRIPT_DIR/mapping.tsv"
ROUTER_SSH="$SCRIPT_DIR/../router-ssh/router-ssh.sh"
RUN_MODE=deploy
INTERACTIVE=0
MUTATION_STARTED=0
CURRENT_STEP=validation
ROUTER_OPTIONS=()
MAP_SRC=()
MAP_DST=()
MAP_MODE=()
MAP_POLICY=()

APP_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$APP_ROOT/Makefile" | tr -d '\r')"
ROUTER_TOOLS=(uci tailscale scp ls awk)
POST_SYNC_COMMANDS=(
  "sed -i 's/@APP_VERSION@/$APP_VERSION/g' /www/luci-static/resources/view/tailscale-ng/index.js"
  "sh /etc/uci-defaults/40_luci-app-tailscale-ng"
  "/etc/init.d/rpcd restart"
)

usage() {
  cat <<'EOF'
Usage:
  bash .dev/deploy-files/deploy-files.sh [deploy|clean] [--interactive]

Deploy is the default. It copies mapped files, applies permissions and runs
post-deploy commands. Clean removes overwrite files and preserves protected files.
Router access and file transfers are handled by ../router-ssh/router-ssh.sh.
Use Router SSH directly for commands, scripts, downloads and open sessions.
--interactive passes through to Router SSH for password-based key installation
in your own terminal. Ordinary runs never prompt for a password.
Exit codes: 0 = completed, 1 = local error, 2 = user action required.
Router SSH failures retain their original exit status.
EOF
}

log() { printf '%s\n' "$*" >&2; }
step() { CURRENT_STEP="$*"; printf '[STEP] %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}
remote_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
router() { bash "$ROUTER_SSH" "${ROUTER_OPTIONS[@]}" "$@"; }
remote() { router exec-command -- "$1"; }

cleanup() {
  local status=$?
  if [[ "$status" != 0 && "$MUTATION_STARTED" == 1 ]]; then
    log "ERROR: $RUN_MODE stopped during: $CURRENT_STEP. Router files may already have changed."
  fi
  return 0
}

load_mapping() {
  [[ -f "$MAPPING_FILE" ]] || die "Mapping file is missing: $MAPPING_FILE"
  local line_no=0 line src dst mode policy extra src_abs previous
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="$(trim "$line")"
    [[ -n "$line" && "${line:0:1}" != '#' ]] || continue
    IFS=$'\t' read -r src dst mode policy extra <<< "$line"
    src="$(trim "${src:-}")"
    dst="$(trim "${dst:-}")"
    mode="$(trim "${mode:-}")"
    policy="$(trim "${policy:-overwrite}")"
    [[ -n "$src" && -n "$dst" && -n "$mode" && -z "${extra:-}" ]] || die "Invalid mapping at line $line_no: expected source, destination, mode and optional policy"
    [[ "$dst" == /* && "$dst" != / && "$dst" != */ ]] || die "Destination must be an absolute file path at line $line_no: $dst"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "Invalid mode at line $line_no: $mode"
    [[ "$policy" == overwrite || "$policy" == keep-if-exists ]] || die "Invalid policy at line $line_no: $policy"
    for previous in "${MAP_DST[@]}"; do [[ "$previous" != "$dst" ]] || die "Duplicate destination at line $line_no: $dst"; done
    src_abs="$SCRIPT_DIR/$src"
    if [[ "$RUN_MODE" == deploy ]]; then
      [[ -f "$src_abs" ]] || die "Source file not found at line $line_no: $src_abs"
    fi
    MAP_SRC+=("$src")
    MAP_DST+=("$dst")
    MAP_MODE+=("$mode")
    MAP_POLICY+=("$policy")
  done < "$MAPPING_FILE"
  [[ ${#MAP_SRC[@]} -gt 0 ]] || die "Mapping has no entries: $MAPPING_FILE"
}

warn_git_exec_bits() {
  local i src mode git_mode
  for ((i=0; i<${#MAP_SRC[@]}; i++)); do
    mode="${MAP_MODE[$i]}"
    [[ "$mode" == 755 || "$mode" == 0755 ]] || continue
    src="${MAP_SRC[$i]#../../}"
    git_mode="$(git -C "$APP_ROOT" ls-files --stage -- "$src" | awk '{print $1}')"
    if [[ "$git_mode" != 100755 ]]; then log "WARN git mode for mapped executable is ${git_mode:-untracked}, expected 100755: $src"; fi
  done
}

check_router() {
  step "Preflight: checking the router before $RUN_MODE"
  local command="[ -f /etc/openwrt_release ] || { echo 'ERROR: target is not an OpenWrt router' >&2; exit 1; };"
  if [[ "$RUN_MODE" == deploy ]]; then
    command+=" for tool in ${ROUTER_TOOLS[*]}; do command -v \"\$tool\" >/dev/null 2>&1 || { echo \"ERROR: missing router command: \$tool\" >&2; exit 1; }; done;"
    command+=" [ -d /www/luci-static/resources ] && [ -x /etc/init.d/rpcd ] || { echo 'ERROR: LuCI or rpcd is missing' >&2; exit 1; }"
  fi
  remote "$command"
}

copy_files() {
  local i src_abs dst policy state command='set -e;'
  step "Copy: ${#MAP_SRC[@]} mapped files -> router"
  for dst in "${MAP_DST[@]}"; do
    command+=" mkdir -p $(remote_quote "${dst%/*}/");"
  done
  remote "$command"
  for ((i=0; i<${#MAP_SRC[@]}; i++)); do
    src_abs="$SCRIPT_DIR/${MAP_SRC[$i]}"
    dst="${MAP_DST[$i]}"
    policy="${MAP_POLICY[$i]}"
    if [[ "$policy" == keep-if-exists ]]; then
      state="$(remote "if [ -f $(remote_quote "$dst") ] && [ ! -L $(remote_quote "$dst") ]; then printf exists; elif [ -e $(remote_quote "$dst") ] || [ -L $(remote_quote "$dst") ]; then echo 'ERROR: protected path is not a regular file' >&2; exit 1; else printf missing; fi")"
      case "$state" in
        exists) log "KEEP_EXISTS ${MAP_SRC[$i]} -> $dst"; continue ;;
        missing) log "COPY_MISSING ${MAP_SRC[$i]} -> $dst" ;;
        *) die "Unexpected response when checking protected file: $dst" ;;
      esac
    else
      log "COPY ${MAP_SRC[$i]} -> $dst"
    fi
    router put-files -- "$src_abs" "$dst"
  done
}

symbolic_mode() {
  local value="$((8#$1))" symbols=rwxrwxrwx result='' bit index character
  for ((bit=8; bit>=0; bit--)); do
    index=$((8 - bit))
    if (( value & (1 << bit) )); then character="${symbols:$index:1}"; else character=-; fi
    case "$bit" in
      6) if (( value & 04000 )); then if [[ "$character" == x ]]; then character=s; else character=S; fi; fi ;;
      3) if (( value & 02000 )); then if [[ "$character" == x ]]; then character=s; else character=S; fi; fi ;;
      0) if (( value & 01000 )); then if [[ "$character" == x ]]; then character=t; else character=T; fi; fi ;;
    esac
    result+="$character"
  done
  printf '%s' "$result"
}

set_perms() {
  step "Permissions: apply and verify mapped modes"
  local i dst mode expected command='set -e;'
  for ((i=0; i<${#MAP_DST[@]}; i++)); do
    dst="${MAP_DST[$i]}"
    mode="$(printf '%o' "$((8#${MAP_MODE[$i]}))")"
    expected="$(symbolic_mode "${MAP_MODE[$i]}")"
    command+=" chmod $mode $(remote_quote "$dst");"
    command+=" [ \"\$(ls -ld $(remote_quote "$dst") | awk '{print substr(\$1,2,9)}')\" = '$expected' ] || { echo $(remote_quote "ERROR: permission verification failed: $dst") >&2; exit 1; };"
  done
  remote "$command"
}

run_post_sync() {
  step "Post: running post-deploy commands"
  local cmd command='set -e;'
  for cmd in "${POST_SYNC_COMMANDS[@]}"; do
    log "POST $cmd"
    command+=" $cmd;"
  done
  remote "$command"
}

clean_target_files() {
  step "Clean: remove mapped overwrite files"
  local i dst command='set -e;'
  for ((i=0; i<${#MAP_DST[@]}; i++)); do
    dst="${MAP_DST[$i]}"
    if [[ "${MAP_POLICY[$i]}" == keep-if-exists ]]; then log "KEEP_CLEAN_SKIP $dst"; continue; fi
    log "REMOVE $dst"
    command+=" rm -f -- $(remote_quote "$dst");"
  done
  remote "$command"
}

main() {
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  local mode_seen=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; return 0 ;;
      --interactive) INTERACTIVE=1 ;;
      deploy|clean)
        [[ "$mode_seen" == 0 ]] || die "Specify only one mode: deploy or clean"
        RUN_MODE="$1"; mode_seen=1
        ;;
      *) die "Unknown argument: $1. Use Router SSH for commands, scripts and transfers; use --help for deployment usage." ;;
    esac
    shift
  done
  [[ -f "$ROUTER_SSH" ]] || die "Router SSH tooling is missing: $ROUTER_SSH"
  [[ "$INTERACTIVE" == 0 ]] || ROUTER_OPTIONS+=(--interactive)
  load_mapping
  if [[ "$RUN_MODE" == deploy ]]; then require_cmd git; warn_git_exec_bits; fi
  check_router
  MUTATION_STARTED=1
  if [[ "$RUN_MODE" == clean ]]; then
    clean_target_files
    log 'DONE: clean completed successfully'
    return 0
  fi
  copy_files
  set_perms
  run_post_sync
  log 'DONE: deploy completed successfully'
}

main "$@"
