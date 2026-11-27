#!/usr/bin/env bash
# Resolve the toolchain pins for the honk commit pinned by the package Makefile.
#
#   ./honk/honk_toolchain.sh [--src DIR] [Makefile]
#
# Prints HONK_SRC_URL / HONK_SRC_VERSION plus BPF_LINKER_VERSION / SHA256, read
# from that commit's .github/ci/pins.env (or from --src when the source is
# already checked out), and ZIG_VERSION, which is always "latest": honk stopped
# pinning Zig in 2a23ce8736, so any current release builds the same way.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR=""
MAKEFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC_DIR="${2:?--src needs a directory}"; shift 2 ;;
    *) MAKEFILE="$1"; shift ;;
  esac
done
MAKEFILE="${MAKEFILE:-${HONK_MAKEFILE:-$SCRIPT_DIR/Makefile}}"

[ -f "$MAKEFILE" ] || { echo "ERROR: Makefile not found: $MAKEFILE" >&2; exit 1; }

URL=$(sed -n 's/^[[:space:]]*HONK_SRC_URL:=//p' "$MAKEFILE" | head -n 1)
REV=$(sed -n 's/^[[:space:]]*HONK_SRC_VERSION:=//p' "$MAKEFILE" | head -n 1)
[ -n "$URL" ] && [ -n "$REV" ] || {
  echo "ERROR: HONK_SRC_URL / HONK_SRC_VERSION missing in $MAKEFILE" >&2
  exit 1
}

if [ -n "$SRC_DIR" ]; then
  SRC_DIR="$(cd "$SRC_DIR" && pwd)"
  PINS_FILE="$SRC_DIR/.github/ci/pins.env"
  [ -f "$PINS_FILE" ] || {
    echo "ERROR: $SRC_DIR is not a honk checkout with .github/ci/pins.env" >&2
    exit 1
  }
else
  REPO_PATH="${URL#https://github.com/}"
  REPO_PATH="${REPO_PATH%.git}"
  PINS_FILE="$(mktemp)"
  trap 'rm -f "$PINS_FILE"' EXIT
  curl -fsSL --retry 3 "https://raw.githubusercontent.com/${REPO_PATH}/${REV}/.github/ci/pins.env" > "$PINS_FILE" || {
    echo "ERROR: failed to fetch .github/ci/pins.env for ${REV}" >&2
    exit 1
  }
fi

BPF_LINKER_VERSION=$(sed -n 's/^BPF_LINKER_VERSION=//p' "$PINS_FILE" | head -n 1)
BPF_LINKER_SHA256=$(sed -n 's/^BPF_LINKER_SHA256=//p' "$PINS_FILE" | head -n 1)
[ -n "$BPF_LINKER_VERSION" ] && [ -n "$BPF_LINKER_SHA256" ] || {
  echo "ERROR: BPF_LINKER_VERSION / BPF_LINKER_SHA256 missing in $PINS_FILE" >&2
  exit 1
}

ZIG_VERSION=latest

printf 'HONK_SRC_URL=%s\nHONK_SRC_VERSION=%s\nBPF_LINKER_VERSION=%s\nBPF_LINKER_SHA256=%s\nZIG_VERSION=%s\n' \
  "$URL" "$REV" "$BPF_LINKER_VERSION" "$BPF_LINKER_SHA256" "$ZIG_VERSION"
