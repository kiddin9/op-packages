#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-$REPO_DIR/luci-app-honk/root/etc/honk/dashboard}"
UPSTREAM_REPO="Zakkaus/doona"

echo "==> Updating embedded Doona dashboard..."
echo "Target directory: $TARGET_DIR"

# 1. Fetch latest release tag
RELEASES_HTML="$(curl -fsSL --retry 3 --connect-timeout 10 "https://github.com/${UPSTREAM_REPO}/releases" 2>/dev/null || true)"
LATEST_TAG="$(printf "%s" "$RELEASES_HTML" | grep -o 'releases/tag/[^"/]*' | head -n 1 | sed 's|releases/tag/||')"

if [ -z "$LATEST_TAG" ]; then
    echo "Warning: Could not detect latest tag from GitHub releases HTML. Trying git ls-remote..."
    LATEST_TAG="$(git ls-remote --tags "https://github.com/${UPSTREAM_REPO}.git" | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}' | sort -V | tail -n 1)"
fi

[ -n "$LATEST_TAG" ] || { echo "Error: Failed to resolve latest release tag for ${UPSTREAM_REPO}" >&2; exit 1; }
echo "Latest release tag: $LATEST_TAG"

# 2. Resolve asset download URL (handling both doona-X.X.X.tar.gz and doona-vX.X.X.tar.gz)
ASSETS_HTML="$(curl -fsSL --retry 3 --connect-timeout 10 "https://github.com/${UPSTREAM_REPO}/releases/expanded_assets/${LATEST_TAG}" 2>/dev/null || true)"
ASSET_PATH="$(printf "%s" "$ASSETS_HTML" | grep -o "/${UPSTREAM_REPO}/releases/download/[^\"]*\\.tar\\.gz" | grep -v 'fonts' | head -n 1 || true)"

TAG_NO_V="${LATEST_TAG#[vV]}"
DOWNLOAD_URL=""

if [ -n "$ASSET_PATH" ]; then
    DOWNLOAD_URL="https://github.com${ASSET_PATH}"
    echo "Found upstream asset: $ASSET_PATH"
else
    # Inferred fallback: try without 'v' first (doona-0.1.0-beta.2.tar.gz), then with 'v'
    DOWNLOAD_URL="https://github.com/${UPSTREAM_REPO}/releases/download/${LATEST_TAG}/doona-${TAG_NO_V}.tar.gz"
    echo "Inferred asset URL: $DOWNLOAD_URL"
fi

# 3. Download and extract
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_FILE="$TMP_DIR/doona.tar.gz"
echo "Downloading $DOWNLOAD_URL ..."

if ! curl -fsSL --retry 3 --connect-timeout 15 -o "$ARCHIVE_FILE" "$DOWNLOAD_URL" 2>/dev/null || [ ! -s "$ARCHIVE_FILE" ]; then
    # Try alternative format (switch between doona-v and doona-)
    ALT_URL=""
    case "$DOWNLOAD_URL" in
        *doona-v*)
            ALT_URL="$(echo "$DOWNLOAD_URL" | sed 's/doona-v/doona-/')"
            ;;
        *doona-[0-9]*)
            ALT_URL="$(echo "$DOWNLOAD_URL" | sed 's/doona-/doona-v/')"
            ;;
    esac
    if [ -n "$ALT_URL" ] && [ "$ALT_URL" != "$DOWNLOAD_URL" ]; then
        echo "Retrying with alternative asset name format: $ALT_URL"
        curl -fsSL --retry 3 --connect-timeout 15 -o "$ARCHIVE_FILE" "$ALT_URL"
    fi
fi

[ -s "$ARCHIVE_FILE" ] || { echo "Error: Downloaded package is empty or failed to download." >&2; exit 1; }

EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE_FILE" -C "$EXTRACT_DIR"

DEPLOY_SRC="$EXTRACT_DIR"
if [ ! -f "$DEPLOY_SRC/index.html" ] && [ -f "$EXTRACT_DIR/dist/index.html" ]; then
    DEPLOY_SRC="$EXTRACT_DIR/dist"
fi

[ -f "$DEPLOY_SRC/index.html" ] || { echo "Error: index.html not found in extracted archive." >&2; exit 1; }

# 4. Deploy to target directory
mkdir -p "$TARGET_DIR"
rm -rf "${TARGET_DIR:?}"/* "${TARGET_DIR:?}"/.[!.]* 2>/dev/null || true
cp -rf "$DEPLOY_SRC/"* "$TARGET_DIR/"
find "$TARGET_DIR" -type d -exec chmod 755 {} +
find "$TARGET_DIR" -type f -exec chmod 644 {} +

echo "==> Successfully embedded Doona dashboard (${LATEST_TAG}) into $TARGET_DIR"
ls -lh "$TARGET_DIR"
