#!/bin/sh

set -eu

INCLUDE_DIR="${OVERVIEW_MANAGER_INCLUDE_DIR:-/www/luci-static/resources/view/status/include}"
UCI="${OVERVIEW_MANAGER_UCI:-uci}"
SELF="00_overview-manager.js"

files() {
  for path in "$INCLUDE_DIR"/*.js; do
    [ -f "$path" ] || continue
    basename "$path"
  done | sort
}

layout() {
  order="$("$UCI" -q get overview-manager.main.order 2>/dev/null || true)"
  hidden="$("$UCI" -q get overview-manager.main.hidden 2>/dev/null || true)"
  printf 'order=%s\nhidden=%s\n' "$order" "$hidden"
}

normalize_list() {
  value="${1:-}"
  result=""
  seen=" "
  old_ifs="$IFS"
  IFS=', '
  set -- $value
  IFS="$old_ifs"

  for name in "$@"; do
    [ -n "$name" ] || continue
    case "$name" in
      "$SELF" | *[!A-Za-z0-9_.-]* | *.js.js)
        printf 'Invalid widget name: %s\n' "$name" >&2
        return 1
        ;;
      *.js) ;;
      *)
        printf 'Invalid widget name: %s\n' "$name" >&2
        return 1
        ;;
    esac
    [ -f "$INCLUDE_DIR/$name" ] || {
      printf 'Widget is not installed: %s\n' "$name" >&2
      return 1
    }
    case "$seen" in
      *" $name "*) continue ;;
    esac
    result="${result:+$result }$name"
    seen="$seen$name "
  done
  printf '%s\n' "$result"
}

save() {
  order="$(normalize_list "${1:-}")"
  hidden="$(normalize_list "${2:-}")"

  "$UCI" -q set overview-manager.main=main
  "$UCI" -q set "overview-manager.main.order=$order"
  "$UCI" -q set "overview-manager.main.hidden=$hidden"
  "$UCI" -q commit overview-manager
  printf 'Layout saved.\n'
}

usage() {
  printf 'Usage: %s {files|layout|save ORDER HIDDEN}\n' "$0" >&2
  exit 2
}

case "${1:-}" in
  files) files ;;
  layout) layout ;;
  save) save "${2:-}" "${3:-}" ;;
  *) usage ;;
esac
