#!/usr/bin/env bash
# Build honk-core for an OpenWrt arch/target triple.
#
#   ./honk/build_honk_core.sh [--if-needed] <arch|target_triple> [output_file] [source_dir]
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

if [ -f "${HOME:-}/.cargo/env" ]; then
  . "${HOME:-}/.cargo/env"
fi
export PATH="${HOME:-}/.cargo/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

case "$TARGET_IN" in
  x86_64|x86_64-unknown-linux-musl)
    RUST_TARGET=x86_64-unknown-linux-musl
    ZIG_TARGET=x86_64-linux-musl
    ;;
  aarch64|aarch64_generic|aarch64-unknown-linux-musl)
    RUST_TARGET=aarch64-unknown-linux-musl
    ZIG_TARGET=aarch64-linux-musl
    ;;
  *)
    echo "ERROR: unsupported arch: $TARGET_IN" >&2
    exit 1
    ;;
esac

OUT_FILE="${OUT_FILE:-$SCRIPT_DIR/files/honk-core.bin}"
case "$OUT_FILE" in
  /*) ;;
  *) OUT_FILE="$PWD/$OUT_FILE" ;;
esac

if [ "$IF_NEEDED" = 1 ] && [ -f "$OUT_FILE" ]; then
  if [ ! -f "$OUT_FILE.stamp" ]; then
    echo "==> using prebuilt honk-core (no stamp): $OUT_FILE"
    exit 0
  fi
  if [ "$(cat "$OUT_FILE.stamp")" = "$RUST_TARGET" ]; then
    echo "==> honk-core is up to date: $OUT_FILE"
    exit 0
  fi
  echo "==> honk-core target changed, rebuilding: $OUT_FILE"
fi

# Building: drop the old artifact so a failed build cannot be reused.
rm -f "$OUT_FILE" "$OUT_FILE.stamp"

MAKEFILE="${HONK_MAKEFILE:-$SCRIPT_DIR/Makefile}"
if [ -n "$SRC_DIR" ]; then
  eval "$("$SCRIPT_DIR/honk_toolchain.sh" --src "$SRC_DIR" "$MAKEFILE")"
else
  eval "$("$SCRIPT_DIR/honk_toolchain.sh" "$MAKEFILE")"
  SRC_DIR="$SCRIPT_DIR/honk-src"
  CACHED_REV=$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || true)
  if [ -d "$SRC_DIR/crates/honk-core" ] && [ "$CACHED_REV" = "$HONK_SRC_VERSION" ]; then
    echo "==> Reusing $SRC_DIR at ${HONK_SRC_VERSION}"
  else
    if [ -n "$CACHED_REV" ]; then
      echo "==> honk-src is at ${CACHED_REV}, expected ${HONK_SRC_VERSION}; refetching..."
    fi
    rm -rf "$SRC_DIR"
    echo "==> Fetching honk source (${HONK_SRC_URL} @ ${HONK_SRC_VERSION})..."
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$HONK_SRC_URL"
    git -C "$SRC_DIR" fetch --depth 1 origin "$HONK_SRC_VERSION"
    git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
  fi
fi

SRC_DIR="$(cd "$SRC_DIR" && pwd)"
echo "==> Source: $SRC_DIR"
echo "==> Target: $RUST_TARGET (zig: $ZIG_TARGET)"

command -v zig >/dev/null 2>&1 || { echo "ERROR: zig not found in PATH" >&2; exit 1; }
command -v bpf-linker >/dev/null 2>&1 || { echo "ERROR: bpf-linker not found in PATH" >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "ERROR: cargo not found in PATH" >&2; exit 1; }

ZIG_ACTUAL="$(zig version)"
if [ "$ZIG_ACTUAL" != "$ZIG_VERSION" ]; then
  echo "ERROR: zig ${ZIG_ACTUAL} does not match the honk pin ${ZIG_VERSION}" >&2
  exit 1
fi
echo "==> zig ${ZIG_ACTUAL}"

# bpf-linker 0.11.0 reports 0.0.0; its tarball is checked by sha256 at install time.
echo "==> $(bpf-linker --version 2>/dev/null | head -n 1)"

cd "$SRC_DIR"
EBPF_CHANNEL=$(sed -n 's/^channel[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' crates/honk-ebpf/rust-toolchain.toml 2>/dev/null | head -n 1)
EBPF_CHANNEL="${EBPF_CHANNEL:-nightly}"

if command -v rustup >/dev/null 2>&1; then
  rustup target add "$RUST_TARGET"
  rustup toolchain install "$EBPF_CHANNEL" --component rust-src,llvm-tools
fi

echo "==> Building honk-ebpf object..."
(
  cd crates/honk-ebpf
  cargo "+${EBPF_CHANNEL}" build --release -Zbuild-std=core --target bpfel-unknown-none
)

EBPF_OBJ="crates/honk-ebpf/target/bpfel-unknown-none/release/honk-ebpf"
[ -f "$EBPF_OBJ" ] || { echo "ERROR: eBPF object not found at $EBPF_OBJ" >&2; exit 1; }
if command -v readelf >/dev/null 2>&1; then
  readelf -S "$EBPF_OBJ" | grep -q '\.BTF' || { echo "ERROR: $EBPF_OBJ has no .BTF section" >&2; exit 1; }
fi

export ZIGCC_TARGET="$ZIG_TARGET"
L=$(printf '%s' "$RUST_TARGET" | tr '-' '_')
U=$(printf '%s' "$RUST_TARGET" | tr 'a-z-' 'A-Z_')
export "CC_${L}=$SRC_DIR/ci/zigcc"
export "CXX_${L}=$SRC_DIR/ci/zigcxx"
export "CARGO_TARGET_${U}_LINKER=$SRC_DIR/ci/zigcc"
if [[ "$RUST_TARGET" == *-musl ]]; then
  export "CARGO_TARGET_${U}_RUSTFLAGS=-C link-self-contained=no"
fi
export BINDGEN_EXTRA_CLANG_ARGS="$("$SRC_DIR/ci/zig-bindgen-env" "$ZIGCC_TARGET")"

echo "==> Building honk-core for $RUST_TARGET..."
cargo build --release --locked \
  -p honk-core \
  --no-default-features \
  --features ebpf,rprx,clash-api,native-api,jemalloc \
  --target "$RUST_TARGET"

BUILT_BIN="$SRC_DIR/target/$RUST_TARGET/release/honk-core"
[ -f "$BUILT_BIN" ] || { echo "ERROR: expected output not found at $BUILT_BIN" >&2; exit 1; }

FILE_DESC=$(file -b "$BUILT_BIN")
case "$FILE_DESC" in
  ELF*) ;;
  *) echo "ERROR: output is not an ELF binary: $FILE_DESC" >&2; exit 1 ;;
esac
if [[ "$RUST_TARGET" == *-musl ]] && [[ "$FILE_DESC" != *"statically linked"* ]]; then
  echo "ERROR: $RUST_TARGET binary is not statically linked: $FILE_DESC" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"
cp -f "$BUILT_BIN" "$OUT_FILE"
chmod +x "$OUT_FILE"
printf '%s\n' "$RUST_TARGET" > "$OUT_FILE.stamp"

echo "==> Build succeeded: $OUT_FILE"
echo "==> $FILE_DESC"
ls -lh "$OUT_FILE"
