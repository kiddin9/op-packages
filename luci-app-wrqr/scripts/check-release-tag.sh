#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
[ "${1:?usage: check-release-tag.sh TAG}" = "v$PKG_VERSION" ] || {
  printf 'release tag must be v%s\n' "$PKG_VERSION" >&2
  exit 1
}
