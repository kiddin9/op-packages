#!/bin/sh

[ -z "$2" ] && exit 1

CLIENT_DIR=$(uci -q get hijpass.@hijpass[0].client_dir || echo '/etc/hijpass/client')
SERVER_DIR=$(uci -q get hijserver.@hijserver[0].server_dir || echo '/etc/hijpass/server')

is_safe_section_id() {
  case "$1" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_safe_keep_path() {
  local dir="$1"
  local section_id="$2"
  local keep_path="$3"

  [ -z "$keep_path" ] && return 0
  case "$keep_path" in
    "$dir"/*-"$section_id".json) return 0 ;;
    *) return 1 ;;
  esac
}

remove_node_file() {
  local dir="$1"
  local section_id="$2"
  local keep_path="$3"

  if ! is_safe_section_id "$section_id" || ! is_safe_keep_path "$dir" "$section_id" "$keep_path"; then
    echo "Invalid argument" >&2
    exit 1
  fi

  for file in "${dir}/"*-"${section_id}".json; do
    [ -e "$file" ] || continue
    [ -n "$keep_path" ] && [ "$file" = "$keep_path" ] && continue
    rm -f "$file"
  done
}

case "$1" in
"proxy")
  remove_node_file "$CLIENT_DIR" "$2" "$3"
  ;;
"server")
  remove_node_file "$SERVER_DIR" "$2" "$3"
  ;;
*)
  exit 1
  ;;
esac
