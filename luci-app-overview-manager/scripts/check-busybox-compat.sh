#!/bin/sh

# Check the shell that actually lands on the router for constructs BusyBox does
# not provide. The test suite runs on GNU coreutils, which masks these: sort -o,
# base64, grep -P and find -printf all exist there and none exist on a stock
# OpenWrt image.
#
# The scan runs over a staged package tree so it can never drift from what is
# installed. When a busybox binary is available it also syntax-checks every
# script with BusyBox ash itself.

set -eu

fail() {
  printf 'check-busybox-compat: %s\n' "$*" >&2
  exit 1
}

stage="${1:?usage: check-busybox-compat.sh STAGE_DIR}"
[ -d "$stage" ] || fail "stage directory not found: $stage"

# Every regular file in the stage whose first line is a POSIX sh shebang.
shell_files() {
  find "$stage" -type f -print | sort | while IFS= read -r file; do
    case "$(head -n 1 "$file" 2>/dev/null)" in
      '#!/bin/sh' | '#!/bin/sh '* | '#!/bin/ash' | '#!/usr/bin/env sh') ;;
      *) continue ;;
    esac
    printf '%s\n' "$file"
  done
}

files="$(shell_files)"
[ -n "$files" ] || fail 'no shell scripts found in the stage'

# Each entry is "regex<TAB>explanation".
findings=''
scan() {
  pattern="$1"
  message="$2"
  hits="$(printf '%s\n' "$files" |
    xargs grep -nE "$pattern" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    findings="$findings
$message
$(printf '%s' "$hits" | sed "s|^$stage/||")"
  fi
}

# Absent from BusyBox, or present with different semantics.
scan '\bsort\b[^|;&]*(-o[[:space:]]|--output)' \
  'sort -o is not supported by BusyBox sort; redirect to a temporary file'
scan '\bbase64\b' \
  'base64 is not present on a stock OpenWrt image'
scan '\bgrep\b[^|;&]*(-[a-zA-Z]*P|--perl-regexp)' \
  'grep -P is not supported by BusyBox grep'
scan '\bfind\b[^|;&]*-printf' \
  'find -printf is not supported by BusyBox find'
scan '\bgensub[[:space:]]*\(' \
  'gensub() is a GNU awk extension'
scan '\bstat\b[^|;&]*--format' \
  'stat --format is GNU-only; BusyBox stat accepts -c'
scan '\breadlink\b[^|;&]*--canonicalize' \
  'readlink --canonicalize is GNU-only; BusyBox accepts -f'

# Bash-only syntax that ash rejects outright.
scan '\[\[' \
  '[[ ]] is a bash keyword; ash only has [ ]'
scan 'set[[:space:]]+-o[[:space:]]+pipefail' \
  'set -o pipefail is not supported by ash'
scan '\$\{[A-Za-z_][A-Za-z0-9_]*//' \
  '${var//pattern/replacement} is bash-only; use tr or sed'
scan '\$\{[A-Za-z_][A-Za-z0-9_]*\^\^' \
  '${var^^} is bash-only'
scan "\\\$'" \
  "\$'...' quoting is bash-only"
scan '\becho[[:space:]]+-e\b' \
  'echo -e is not portable; use printf'
scan '=\([[:space:]]*[^)]' \
  'arrays are bash-only'

if [ -n "$findings" ]; then
  printf 'BusyBox incompatibilities in the packaged shell:%s\n' "$findings" >&2
  exit 1
fi

# A real parser is stricter than any pattern list, so use one when present.
if command -v busybox >/dev/null 2>&1; then
  # The loop runs in a subshell, so it reports names and leaves failing to the
  # caller; parser diagnostics go to stderr on their own.
  rejected="$(printf '%s\n' "$files" | while IFS= read -r file; do
    busybox ash -n "$file" || printf '%s\n' "${file#"$stage"/}"
  done)"
  [ -z "$rejected" ] ||
    fail "BusyBox ash rejected: $(printf '%s' "$rejected" | tr '\n' ' ')"
  printf 'BusyBox compatibility OK (patterns and ash -n)\n'
else
  printf 'BusyBox compatibility OK (patterns only; busybox not installed)\n'
fi
