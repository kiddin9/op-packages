#!/usr/bin/env bash
# Build dae (kdae) for an OpenWrt arch/target triple.
#
#   ./dae/build_dae_core.sh [--if-needed] <arch|target_triple> [output_file] [source_dir]
#
# --if-needed: skip when the output exists and its .stamp matches the target
# (or has no stamp, i.e. a prebuilt artifact); rebuild on a target mismatch.
set -euo pipefail

IF_NEEDED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --if-needed) IF_NEEDED=1; shift ;;
    *) break ;;
  esac
done

TARGET_IN="${1:?usage: $0 [--if-needed] <arch|target_triple> [output_file] [source_dir]}"
OUT_FILE="${2:-}"
SRC_DIR="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${PATH:-}:/usr/local/go/bin:${HOME:-}/go/bin"

case "$TARGET_IN" in
  x86_64|amd64|x86_64-unknown-linux-musl|x86_64-openwrt-linux*)
    GO_ARCH=amd64
    STAMP_TARGET=x86_64-linux
    ELF_EXPECT="x86-64"
    ;;
  aarch64|aarch64_generic|arm64|aarch64-unknown-linux-musl|aarch64-openwrt-linux*)
    GO_ARCH=arm64
    STAMP_TARGET=aarch64-linux
    ELF_EXPECT="ARM aarch64"
    ;;
  *)
    echo "ERROR: unsupported arch: $TARGET_IN" >&2
    exit 1
    ;;
esac

OUT_FILE="${OUT_FILE:-$SCRIPT_DIR/files/dae.bin}"
case "$OUT_FILE" in
  /*) ;;
  *) OUT_FILE="$PWD/$OUT_FILE" ;;
esac

if [ "$IF_NEEDED" = 1 ] && [ -f "$OUT_FILE" ]; then
  if [ ! -f "$OUT_FILE.stamp" ]; then
    echo "==> using prebuilt dae (no stamp): $OUT_FILE"
    exit 0
  fi
  if [ "$(cat "$OUT_FILE.stamp")" = "$STAMP_TARGET" ]; then
    echo "==> dae is up to date: $OUT_FILE"
    exit 0
  fi
  echo "==> dae target changed, rebuilding: $OUT_FILE"
fi

rm -f "$OUT_FILE" "$OUT_FILE.stamp"

MAKEFILE="${DAE_MAKEFILE:-$SCRIPT_DIR/Makefile}"
[ -f "$MAKEFILE" ] || { echo "ERROR: Makefile not found: $MAKEFILE" >&2; exit 1; }

DAE_SRC_URL="$(sed -n 's/^[[:space:]]*DAE_SRC_URL:=//p' "$MAKEFILE" | head -n 1)"
DAE_SRC_VERSION="$(sed -n 's/^[[:space:]]*DAE_SRC_VERSION:=//p' "$MAKEFILE" | head -n 1)"
DAE_SHORT_VERSION="${DAE_SRC_VERSION:0:7}"

[ -n "$DAE_SRC_URL" ] && [ -n "$DAE_SRC_VERSION" ] || {
  echo "ERROR: DAE_SRC_URL / DAE_SRC_VERSION missing in $MAKEFILE" >&2
  exit 1
}

if [ -z "$SRC_DIR" ]; then
  SRC_DIR="$SCRIPT_DIR/dae-src"
  CACHED_REV=$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || true)
  if [ -d "$SRC_DIR/control/kern" ] && [ "$CACHED_REV" = "$DAE_SRC_VERSION" ]; then
    echo "==> Reusing $SRC_DIR at ${DAE_SRC_VERSION}"
  else
    if [ -n "$CACHED_REV" ]; then
      echo "==> dae-src is at ${CACHED_REV}, expected ${DAE_SRC_VERSION}; refetching..."
    fi
    rm -rf "$SRC_DIR"
    echo "==> Fetching dae source (${DAE_SRC_URL} @ ${DAE_SRC_VERSION})..."
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$DAE_SRC_URL"
    git -C "$SRC_DIR" fetch --depth 1 origin "$DAE_SRC_VERSION"
    git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
  fi
  git -C "$SRC_DIR" submodule sync --recursive >/dev/null
  git -C "$SRC_DIR" submodule update --init --recursive --depth 1
fi

SRC_DIR="$(cd "$SRC_DIR" && pwd)"
echo "==> Source: $SRC_DIR"
echo "==> Target: linux/$GO_ARCH ($STAMP_TARGET)"

command -v go >/dev/null 2>&1 || { echo "ERROR: go not found in PATH" >&2; exit 1; }

BPF_CLANG="${BPF_CLANG:-${CLANG:-}}"
if [ -z "$BPF_CLANG" ]; then
  for c in clang clang-18 clang-17 clang-16 clang-15; do
    if command -v "$c" >/dev/null 2>&1; then
      BPF_CLANG="$c"
      break
    fi
  done
fi
[ -n "$BPF_CLANG" ] && command -v "$BPF_CLANG" >/dev/null 2>&1 || {
  echo "ERROR: clang not found in PATH" >&2
  exit 1
}

BPF_STRIP="${BPF_STRIP:-${STRIP:-}}"
if [ -z "$BPF_STRIP" ]; then
  for s in llvm-strip llvm-strip-18 llvm-strip-17 llvm-strip-16 llvm-strip-15; do
    if command -v "$s" >/dev/null 2>&1; then
      BPF_STRIP="$(command -v "$s")"
      break
    fi
  done
fi
if [ -n "$BPF_STRIP" ]; then
  BPF_STRIP_FLAG="-strip=${BPF_STRIP}"
else
  echo "==> WARNING: llvm-strip not found; generating unstripped eBPF objects" >&2
  BPF_STRIP_FLAG="-no-strip"
fi

cd "$SRC_DIR"

export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
echo "==> $(go version)"
echo "==> clang: $BPF_CLANG ($($BPF_CLANG --version | head -n 1))"

rm -f control/bpf_bpf*.go control/bpf_bpf*.o \
      control/directstats_bpf*.go control/directstats_bpf*.o \
      trace/bpf_*_bpf*.go trace/bpf_*_bpf*.o

(
  unset GOOS GOARCH GOARM GOAMD64
  export BPF_CLANG="$BPF_CLANG"
  export BPF_STRIP_FLAG="$BPF_STRIP_FLAG"
  export BPF_CFLAGS="-O2 -Wall -Werror -DMAX_MATCH_SET_LEN=1024"
  export BPF_TARGET="bpfel,bpfeb"
  export BPF_TRACE_TARGET="$GO_ARCH"

  echo "==> Generating eBPF artifacts (control + direct_stats + trace)..."
  go generate ./common/consts/ebpf.go
  go generate ./control/control.go
  go generate ./trace/trace.go
)

DAE_GOEXPERIMENT=$(sed -n 's/^DEFAULT_GOEXPERIMENT := //p' "$SRC_DIR/Makefile" 2>/dev/null | head -n 1)
DAE_GOEXPERIMENT="${DAE_GOEXPERIMENT:-newinliner,simd,heapminimum512kib,randomizedheapbase64}"

mkdir -p "$(dirname "$OUT_FILE")"
TMP_BIN="$(mktemp "${OUT_FILE}.tmp.XXXXXX")"
trap 'rm -f "$TMP_BIN"' EXIT

echo "==> Building dae for linux/$GO_ARCH (GOEXPERIMENT=$DAE_GOEXPERIMENT)..."
CGO_ENABLED=0 \
GOOS=linux \
GOARCH="$GO_ARCH" \
GOEXPERIMENT="$DAE_GOEXPERIMENT" \
go build -tags trace -trimpath -buildvcs=false -pgo=auto \
  -ldflags "-s -w -buildid= -X github.com/daeuniverse/dae/cmd.Version=${DAE_SHORT_VERSION:-unstable} -X github.com/daeuniverse/dae/common/consts.MaxMatchSetLen_=1024" \
  -o "$TMP_BIN" .

[ -f "$TMP_BIN" ] || { echo "ERROR: expected output not found at $TMP_BIN" >&2; exit 1; }

FILE_DESC=$(file -b "$TMP_BIN")
case "$FILE_DESC" in
  ELF*statically\ linked*) ;;
  *) echo "ERROR: output is not a statically linked ELF binary: $FILE_DESC" >&2; exit 1 ;;
esac
case "$FILE_DESC" in
  *"$ELF_EXPECT"*) ;;
  *) echo "ERROR: unexpected arch ($ELF_EXPECT expected): $FILE_DESC" >&2; exit 1 ;;
esac

chmod +x "$TMP_BIN"
mv -f "$TMP_BIN" "$OUT_FILE"
printf '%s\n' "$STAMP_TARGET" > "$OUT_FILE.stamp"

echo "==> Build succeeded: $OUT_FILE"
echo "==> $FILE_DESC"
ls -lh "$OUT_FILE"
