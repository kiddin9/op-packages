#!/bin/sh
. /usr/lib/hijpass/app-logger.sh

log_debug "$0"

GEO_SITE_PATH=/usr/share/v2ray/geosite.dat
GEO_IP_PATH=/usr/share/v2ray/geoip.dat
RULESET_PATH=/etc/hijpass/ruleset
GEOSITE_TAG_LIST="$(uci -q get hijpass.@shunt[0].geosite_ruleset)"
GEOIP_TAG_LIST="$(uci -q get hijpass.@shunt[0].geoip_ruleset)"

is_geo_type() {
  [ "$1" = "geosite" ] || [ "$1" = "geoip" ]
}

is_safe_geo_arg() {
  [ -n "$1" ] && echo "$1" | grep -Eq "^[A-Za-z0-9_.:,/!-]+$" >/dev/null 2>&1
}

extract() {
  local path
  local type="$1"
  if ! is_geo_type "$type"; then
    echo "Invalid geo type" >&2
    exit 1
  fi
  path="$(getGeoPath "$1")"
  shift
  [ $# -gt 0 ] || exit 1
  for item in "$@"; do
    is_safe_geo_arg "$item" || exit 1
  done
  geoview -type "$type" -action extract -input "$path" -list "$@" | tr 'A-Z' 'a-z'
}

lookup() {
  local path
  if ! is_geo_type "$1" || ! is_safe_geo_arg "$2"; then
    echo "Invalid argument" >&2
    exit 1
  fi
  path="$(getGeoPath "$1")"
  geoview -type "$1" -action lookup -input "$path" -value "$2" | tr 'A-Z' 'a-z'
}

convert() {
  [ -z "$2" ] && return
  local path
  local type="$1"
  is_geo_type "$type" || return 1
  path="$(getGeoPath "$1")"
  for tag in $2; do
    if ! is_safe_geo_arg "$tag"; then
      log_warn "Skip invalid $type tag: $tag"
      continue
    fi
    geoview -type "$type" -action convert -format ruleset -input "$path" -regex -list "$tag" -output "$RULESET_PATH/$type-$tag.srs" \
      && log_info "Convert $type:$tag to ruleset successfully"
  done
}

getGeoPath() {
  case $1 in
    geosite)
      echo $GEO_SITE_PATH
      ;;
    geoip)
      echo $GEO_IP_PATH
      ;;
  esac
}

main() {
  local action="$1"
  shift
  case $action in
    -e | --extract)
      extract "$@"
      ;;
    -t | --convert)
      [ -d $RULESET_PATH ] || mkdir -p $RULESET_PATH
      convert "geosite" "$GEOSITE_TAG_LIST"
      convert "geoip" "$GEOIP_TAG_LIST"
      ;;
    -l | --lookup)
      lookup "$@"
      ;;
    *)
      echo "Usage: $0 [-e|--extract] [-l|--lookup]"
      ;;
  esac
}

main "$@"
