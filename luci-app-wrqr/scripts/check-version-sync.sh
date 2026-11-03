#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
make_name="$(sed -n 's/^PKG_NAME:=//p' "$root/Makefile" | head -n 1)"
make_version="$(sed -n 's/^PKG_VERSION:=//p' "$root/Makefile" | head -n 1)"
make_arch="$(sed -n 's/^PKGARCH:=//p' "$root/Makefile" | head -n 1)"
[ "$make_name" = "$PKG_NAME" ]
[ "$make_version" = "$PKG_VERSION" ]
[ "$make_arch" = "$PKG_ARCH" ]
