#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
stage="${BUILD_DIR:-$root/build/ipk}/stage"
mkdir -p "$root/dist"
"$root/scripts/check-version-sync.sh"
"$root/scripts/stage-package.sh" "$stage"
rm -f "$root/dist"/*.ipk "$root/dist/SHA256SUMS"
python3 "$root/scripts/pack-ipk.py" "$stage" "$root/dist"
(cd "$root/dist" && sha256sum ./*.ipk >SHA256SUMS)
