#!/usr/bin/env bash
# Resolve the toolchain pins for the honk commit pinned by the package Makefile.
#
#   ./honk/honk_toolchain.sh [--src DIR] [Makefile]
#
# Prints HONK_SRC_URL / HONK_SRC_VERSION plus BPF_LINKER_VERSION / SHA256 and
# ZIG_VERSION, read from that commit's .github/ci/pins.env and release.yml (or
# from --src when the source is already checked out).
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
  RELEASE_FILE="$SRC_DIR/.github/workflows/release.yml"
  [ -f "$PINS_FILE" ] && [ -f "$RELEASE_FILE" ] || {
    echo "ERROR: $SRC_DIR is not a honk checkout with .github metadata" >&2
    exit 1
  }
else
  REPO_PATH="${URL#https://github.com/}"
  REPO_PATH="${REPO_PATH%.git}"
  RAW="https://raw.githubusercontent.com/${REPO_PATH}/${REV}"
  fetch() {
    curl -fsSL --retry 3 "$1" || { echo "ERROR: failed to fetch $1" >&2; exit 1; }
  }
  PINS_FILE="$(mktemp)"
  RELEASE_FILE="$(mktemp)"
  trap 'rm -f "$PINS_FILE" "$RELEASE_FILE"' EXIT
  fetch "${RAW}/.github/ci/pins.env" > "$PINS_FILE"
  fetch "${RAW}/.github/workflows/release.yml" > "$RELEASE_FILE"
fi

BPF_LINKER_VERSION=$(sed -n 's/^BPF_LINKER_VERSION=//p' "$PINS_FILE" | head -n 1)
BPF_LINKER_SHA256=$(sed -n 's/^BPF_LINKER_SHA256=//p' "$PINS_FILE" | head -n 1)
[ -n "$BPF_LINKER_VERSION" ] && [ -n "$BPF_LINKER_SHA256" ] || {
  echo "ERROR: BPF_LINKER_VERSION / BPF_LINKER_SHA256 missing in $PINS_FILE" >&2
  exit 1
}

ZIG_VERSION=$(awk '
  /setup-zig/ { seen = 1; next }
  seen && /^[[:space:]]*version:[[:space:]]*/ {
    sub(/^[[:space:]]*version:[[:space:]]*/, "")
    gsub(/[[:space:]"]/, "")
    print
    exit
  }
' "$RELEASE_FILE")
[ -n "$ZIG_VERSION" ] || { echo "ERROR: no setup-zig version in $RELEASE_FILE" >&2; exit 1; }

printf 'HONK_SRC_URL=%s\nHONK_SRC_VERSION=%s\nBPF_LINKER_VERSION=%s\nBPF_LINKER_SHA256=%s\nZIG_VERSION=%s\n' \
  "$URL" "$REV" "$BPF_LINKER_VERSION" "$BPF_LINKER_SHA256" "$ZIG_VERSION"
