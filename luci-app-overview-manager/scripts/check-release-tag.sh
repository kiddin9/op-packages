#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
tag="${1:?usage: check-release-tag.sh TAG}"
expected="v$PKG_VERSION"

[ "$tag" = "$expected" ] || {
  printf 'release tag mismatch: expected %s, got %s\n' "$expected" "$tag" >&2
  exit 1
}
printf 'release tag OK: %s\n' "$tag"
