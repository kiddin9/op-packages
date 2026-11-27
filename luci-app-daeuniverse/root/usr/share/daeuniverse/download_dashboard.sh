#!/bin/sh
# Download and install Dashboard for DAE Universe

TARGET_DIR="${1:-}"
DOWNLOAD_URL="${2:-}"
TARGET_TYPE="${3:-}"

LOG_FILE="/tmp/daeuniverse_dashboard_download.log"
STATUS_FILE="/tmp/daeuniverse_dashboard_download.status"
LOCK_DIR="/tmp/daeuniverse_dashboard_download.lock"
TMP_DIR="/tmp/dashboard_dl_$$"
cleanup() {
    rm -rf "$TMP_DIR"
    if [ "${OWNS_LOCK:-0}" = "1" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

set_status() {
    echo "$1" > "$STATUS_FILE"
    log "STATUS -> $1"
}

if [ -z "$TARGET_DIR" ] || [ -z "$DOWNLOAD_URL" ]; then
    : > "$LOG_FILE"
    log "Error: usage: $0 <target-dir> <archive-url> [target-type]"
    set_status "FAILED"
    exit 1
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        log "Error: another download task is already running (PID $old_pid)."
        exit 1
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || exit 1
fi
echo "$$" > "$LOCK_DIR/pid"
OWNS_LOCK=1

: > "$LOG_FILE"

set_status "DOWNLOADING"
log "Deploying dashboard to: $TARGET_DIR"
log "Download URL: $DOWNLOAD_URL"

download_file() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -s -S -k -L -f --connect-timeout 15 --max-time 180 -o "$output" "$url" >> "$LOG_FILE" 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget --no-check-certificate -T 15 -t 3 -O "$output" "$url" >> "$LOG_FILE" 2>&1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch --no-check-certificate --timeout 15 -O "$output" "$url" >> "$LOG_FILE" 2>&1
    else
        log "Error: No download tool found (curl, wget, or uclient-fetch)!"
        return 1
    fi
}

fetch_text() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -s -k -L -f --connect-timeout 8 --max-time 15 "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget --no-check-certificate -q -T 8 -t 1 -O - "$url" 2>/dev/null
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch --no-check-certificate -q --timeout 8 -O - "$url" 2>/dev/null
    fi
}

case "$DOWNLOAD_URL" in
    *github.com/Zakkaus/doona|*github.com/Zakkaus/doona/)
        PREFIX="${DOWNLOAD_URL%%https://github.com/*}"
        log "Checking latest release..."

        IS_LITE=0
        case "$TARGET_TYPE" in
            *lite*) IS_LITE=1 ;;
        esac
        case "$TARGET_DIR" in
            *lite*) IS_LITE=1 ;;
        esac

        RESOLVED_URL=""
        MAX_RETRIES=3
        attempt=1

        while [ "$attempt" -le "$MAX_RETRIES" ]; do
            RELEASES_HTML=$(fetch_text "${PREFIX}https://github.com/Zakkaus/doona/releases")
            [ -n "$RELEASES_HTML" ] || [ -z "$PREFIX" ] || RELEASES_HTML=$(fetch_text "https://github.com/Zakkaus/doona/releases")
            LATEST_TAG=$(printf "%s" "$RELEASES_HTML" | grep -o '/Zakkaus/doona/releases/tag/[^"/]*' | head -n 1 | sed 's|/Zakkaus/doona/releases/tag/||')
            if [ -z "$LATEST_TAG" ]; then
                RELEASES_HTML=$(fetch_text "${PREFIX}https://github.com/Zakkaus/doona/releases.atom")
                [ -n "$RELEASES_HTML" ] || [ -z "$PREFIX" ] || RELEASES_HTML=$(fetch_text "https://github.com/Zakkaus/doona/releases.atom")
                LATEST_TAG=$(printf "%s" "$RELEASES_HTML" | grep -o 'Zakkaus/doona/releases/tag/[^<"]*' | head -n 1 | sed 's|Zakkaus/doona/releases/tag/||')
            fi

            if [ -n "$LATEST_TAG" ]; then
                log "Latest tag: $LATEST_TAG"
                TAG_NO_V="${LATEST_TAG#[vV]}"
                ASSETS_HTML=$(fetch_text "${PREFIX}https://github.com/Zakkaus/doona/releases/expanded_assets/$LATEST_TAG")
                [ -n "$ASSETS_HTML" ] || [ -z "$PREFIX" ] || ASSETS_HTML=$(fetch_text "https://github.com/Zakkaus/doona/releases/expanded_assets/$LATEST_TAG")
                if [ "$IS_LITE" -eq 1 ]; then
                    ASSET_PATH=$(printf "%s" "$ASSETS_HTML" | grep -o '/Zakkaus/doona/releases/download/[^"]*/doona-lite-[^"]*\.tar\.gz' | head -n 1)
                    if [ -n "$ASSET_PATH" ]; then
                        RESOLVED_URL="https://github.com${ASSET_PATH}"
                        log "Found package: $ASSET_PATH"
                    else
                        RESOLVED_URL="https://github.com/Zakkaus/doona/releases/download/${LATEST_TAG}/doona-lite-${TAG_NO_V}.tar.gz"
                        log "Inferred package URL: $RESOLVED_URL"
                    fi
                else
                    ASSET_PATH=$(printf "%s" "$ASSETS_HTML" | grep -o '/Zakkaus/doona/releases/download/[^"]*/doona-[^"]*\.tar\.gz' | grep -v 'fonts' | grep -v 'lite' | grep -v 'precompressed' | head -n 1)
                    if [ -n "$ASSET_PATH" ]; then
                        RESOLVED_URL="https://github.com${ASSET_PATH}"
                        log "Found package: $ASSET_PATH"
                    else
                        RESOLVED_URL="https://github.com/Zakkaus/doona/releases/download/${LATEST_TAG}/doona-${TAG_NO_V}.tar.gz"
                        log "Inferred package URL: $RESOLVED_URL"
                    fi
                fi
                break
            fi

            log "Failed to fetch latest tag (attempt $attempt/$MAX_RETRIES). Retrying in 2s..."
            sleep 2
            attempt=$((attempt + 1))
        done

        if [ -n "$RESOLVED_URL" ]; then
            DOWNLOAD_URL="${PREFIX}${RESOLVED_URL}"
            log "Resolved URL: $DOWNLOAD_URL"
        else
            log "Error: Failed to obtain latest release version after $MAX_RETRIES attempts."
            set_status "FAILED"
            exit 1
        fi
        ;;
esac

normalize_target_dir() {
    case "$TARGET_DIR" in
        *..*) return 1 ;;
        /etc/daeuniverse/*) ;;
        *) return 1 ;;
    esac

    TARGET_DIR="${TARGET_DIR%/}"
    local base="${TARGET_DIR##*/}"
    case "$base" in
        ''|.|..) return 1 ;;
    esac

    mkdir -p /etc/daeuniverse 2>/dev/null || true
    local canon_root
    canon_root="$(cd /etc/daeuniverse 2>/dev/null && pwd -P)" || return 1
    TARGET_DIR="$canon_root/$base"

    [ -L "$TARGET_DIR" ] && return 1
    return 0
}

if ! normalize_target_dir; then
    log "Error: Invalid target directory (must be a direct subdirectory of /etc/daeuniverse): $TARGET_DIR"
    set_status "FAILED"
    exit 1
fi

log "Downloading package..."
mkdir -p "$TMP_DIR"
ARCHIVE_FILE="$TMP_DIR/package.tmp"

if ! download_file "$DOWNLOAD_URL" "$ARCHIVE_FILE" || [ ! -s "$ARCHIVE_FILE" ]; then
    log "Error: Download failed or file is empty."
    set_status "FAILED"
    exit 1
fi

log "Extracting archive..."
set_status "EXTRACTING"
EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

if case "$DOWNLOAD_URL" in *.tar.gz|*.tgz) true ;; *) false ;; esac; then
    if ! command -v tar >/dev/null 2>&1; then
        log "Error: 'tar' command not found!"
        set_status "FAILED"
        exit 1
    fi
    if ! tar -xzf "$ARCHIVE_FILE" -C "$EXTRACT_DIR" >> "$LOG_FILE" 2>&1; then
        log "Error: Failed to extract tar.gz archive."
        set_status "FAILED"
        exit 1
    fi
else
    if ! command -v unzip >/dev/null 2>&1; then
        log "Error: 'unzip' command not found! Please run 'opkg update && opkg install unzip'."
        set_status "FAILED"
        exit 1
    fi
    if ! unzip -o -q "$ARCHIVE_FILE" -d "$EXTRACT_DIR" >> "$LOG_FILE" 2>&1; then
        log "Error: Failed to unzip archive."
        set_status "FAILED"
        exit 1
    fi
fi

DEPLOY_SRC="$EXTRACT_DIR"
if [ ! -f "$DEPLOY_SRC/index.html" ]; then
    DEPLOY_SRC="$(find "$EXTRACT_DIR" -maxdepth 3 -name "index.html" -exec dirname {} + 2>/dev/null | head -n 1)"
fi

if [ -z "$DEPLOY_SRC" ] || [ ! -f "$DEPLOY_SRC/index.html" ]; then
    log "Error: index.html not found in extracted package."
    set_status "FAILED"
    exit 1
fi

log "Deploying files to $TARGET_DIR..."
mkdir -p "$TARGET_DIR"
rm -rf "${TARGET_DIR:?}"/* "${TARGET_DIR:?}"/.[!.]* 2>/dev/null || true
cp -rf "$DEPLOY_SRC/." "$TARGET_DIR/"
find "$TARGET_DIR" -type d -exec chmod 755 {} +
find "$TARGET_DIR" -type f -exec chmod 644 {} +

if [ -f "$TARGET_DIR/index.html" ]; then
    log "Installed successfully."
    set_status "SUCCESS"
    exit 0
else
    log "Error: Failed to deploy files to $TARGET_DIR."
    set_status "FAILED"
    exit 1
fi
