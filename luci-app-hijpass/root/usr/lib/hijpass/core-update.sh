#!/bin/sh

# 用法:
#   core-update.sh version <sing-box|xray>   — 输出本地版本号（JSON）
#   core-update.sh latest  <sing-box|xray>   — 输出官方最新版本号（JSON）
#   core-update.sh update  <sing-box|xray>   — 从 GitHub 下载最新版并替换

. /usr/lib/hijpass/app-logger.sh

ACTION="$1"
CORE="$2"

SINGBOX_BIN="/usr/bin/sing-box"
XRAY_BIN="/usr/bin/xray"
UPDATE_TMP_DIR=""

json_error() {
    printf '{"success":false,"error":"%s"}\n' "$1"
}

case "$ACTION" in
    version|latest|update) ;;
    *)
        echo "Usage: $0 <version|latest|update> <sing-box|xray>" >&2
        exit 1
        ;;
esac

case "$CORE" in
    sing-box|xray) ;;
    *)
        json_error "unknown core"
        exit 1
        ;;
esac

# ── 检测架构，sing-box 和 xray 的文件名规则不同 ─────────────────────
# sing-box: linux-amd64 / linux-arm64 / linux-armv7 / linux-mips-softfloat ...
# xray:     linux-64    / linux-arm64-v8a / linux-arm32-v7a / linux-mips32 ...
detect_arch() {
    local machine="$1"   # core name: sing-box or xray
    local m="$2"
    if [ "$machine" = "xray" ]; then
        case "$m" in
            x86_64)        echo "linux-64" ;;
            aarch64|arm64) echo "linux-arm64-v8a" ;;
            armv7l)        echo "linux-arm32-v7a" ;;
            armv6l)        echo "linux-arm32-v6" ;;
            mips)          echo "linux-mips32" ;;
            mipsle)        echo "linux-mips32le" ;;
            mips64)        echo "linux-mips64" ;;
            mips64le)      echo "linux-mips64le" ;;
            *)             return 1 ;;
        esac
    else
        # sing-box
        case "$m" in
            x86_64)        echo "linux-amd64" ;;
            aarch64|arm64) echo "linux-arm64" ;;
            armv7l)        echo "linux-armv7" ;;
            armv6l)        echo "linux-armv6" ;;
            mips)          echo "linux-mips-softfloat" ;;
            mipsle)        echo "linux-mipsle-softfloat" ;;
            mips64)        echo "linux-mips64" ;;
            mips64le)      echo "linux-mips64le" ;;
            *)             return 1 ;;
        esac
    fi
}

# ── 获取本地版本 ─────────────────────────────────────────────────────
get_local_version() {
    local bin version
    case "$CORE" in
        sing-box)
            bin="$SINGBOX_BIN"
            if [ -x "$bin" ]; then
                version=$("$bin" version 2>/dev/null | grep -oE 'sing-box version [0-9]+\.[0-9]+\.[0-9]+[^ ]*' | awk '{print $3}')
            fi
            ;;
        xray)
            bin="$XRAY_BIN"
            if [ -x "$bin" ]; then
                version=$("$bin" version 2>/dev/null | grep -oE 'Xray [0-9]+\.[0-9]+\.[0-9]+[^ ]*' | awk '{print $2}')
            fi
            ;;
        *)
            printf '{"error":"unknown core: %s"}\n' "$CORE"
            exit 1
            ;;
    esac
    printf '{"core":"%s","version":"%s"}\n' "$CORE" "${version:-unknown}"
}

# ── 获取 GitHub 最新版本号 ────────────────────────────────────────────
get_release_repo() {
    case "$CORE" in
        sing-box) echo "SagerNet/sing-box" ;;
        xray)     echo "XTLS/Xray-core" ;;
        *)        return 1 ;;
    esac
}

get_latest_version() {
    local repo url latest
    repo=$(get_release_repo) || return 1
    url="https://api.github.com/repos/${repo}/releases/latest"
    latest=$(curl -sf --max-time 10 "$url" | jq -r '.tag_name // empty')
    echo "$latest"
}

get_latest_version_json() {
    local latest
    latest=$(get_latest_version)

    if [ -z "$latest" ]; then
        json_error "fetch latest version failed"
        exit 1
    fi

    printf '{"core":"%s","version":"%s"}\n' "$CORE" "$latest"
}

get_asset_sha256() {
    local tag asset repo digest
    tag="$1"
    asset="$2"
    repo=$(get_release_repo) || return 1
    digest=$(curl -sf --max-time 10 \
        "https://api.github.com/repos/${repo}/releases/tags/${tag}" | \
        jq -r --arg asset "$asset" \
            '.assets[] | select(.name == $asset and .state == "uploaded") | .digest // empty' | \
        head -1)

    echo "$digest" | grep -Eq '^sha256:[0-9a-fA-F]{64}$' || return 1
    echo "${digest#sha256:}" | tr 'A-F' 'a-f'
}

verify_archive_checksum() {
    local archive tag asset expected actual
    archive="$1"
    tag="$2"
    asset="$3"

    expected=$(get_asset_sha256 "$tag" "$asset") || return 1
    actual=$(sha256sum "$archive" 2>/dev/null | awk '{print $1}')
    [ -n "$actual" ] && [ "$actual" = "$expected" ]
}

verify_binary() {
    local bin version
    bin="$1"

    [ -f "$bin" ] || return 1
    chmod +x "$bin" 2>/dev/null || return 1

    case "$CORE" in
        sing-box)
            version=$("$bin" version 2>/dev/null | grep -oE 'sing-box version [0-9]+\.[0-9]+\.[0-9]+[^ ]*' | awk '{print $3}')
            ;;
        xray)
            version=$("$bin" version 2>/dev/null | grep -oE 'Xray [0-9]+\.[0-9]+\.[0-9]+[^ ]*' | awk '{print $2}')
            ;;
    esac

    [ -n "$version" ]
}

fail_update() {
    local message="$1"
    [ -n "$UPDATE_TMP_DIR" ] && rm -rf "$UPDATE_TMP_DIR"
    log_error "$message"
    json_error "$message"
    exit 1
}

install_verified_binary() {
    local src dest tmp_dest backup_file
    src="$1"
    dest="$2"
    tmp_dest="${dest}.new.$$"
    backup_file="${UPDATE_TMP_DIR}/${CORE}.bak"

    verify_binary "$src" || fail_update "binary verification failed"
    cp "$src" "$tmp_dest" || {
        rm -f "$tmp_dest"
        fail_update "install copy failed"
    }
    chmod +x "$tmp_dest" || {
        rm -f "$tmp_dest"
        fail_update "install chmod failed"
    }

    if [ -f "$dest" ]; then
        cp "$dest" "$backup_file" || {
            rm -f "$tmp_dest"
            rm -f "$backup_file"
            fail_update "backup failed"
        }
    fi

    if ! mv "$tmp_dest" "$dest"; then
        rm -f "$tmp_dest"
        [ -f "$backup_file" ] && cp "$backup_file" "$dest"
        fail_update "install failed"
    fi
    rm -f "$backup_file"
}

# ── 下载并安装最新版 ─────────────────────────────────────────────────
do_update() {
    local host_arch arch latest_tag download_url tmp_dir asset_name
    host_arch=$(uname -m)
    if ! arch=$(detect_arch "$CORE" "$host_arch"); then
        fail_update "unsupported architecture: $host_arch"
    fi
    log_info "Fetching latest $CORE release..."
    latest_tag=$(get_latest_version)

    if [ -z "$latest_tag" ]; then
        log_error "Failed to fetch latest version for $CORE"
        json_error "fetch latest version failed"
        exit 1
    fi

    log_info "Latest $CORE version: $latest_tag, arch: $arch"
    tmp_dir=$(mktemp -d) || {
        json_error "create temp dir failed"
        exit 1
    }
    UPDATE_TMP_DIR="$tmp_dir"

    case "$CORE" in
        sing-box)
            local version_num candidate_arch downloaded
            version_num=$(echo "$latest_tag" | sed 's/^v//')
            downloaded=""
            for candidate_arch in "${arch}-musl" "$arch"; do
                asset_name="sing-box-${version_num}-${candidate_arch}.tar.gz"
                download_url="https://github.com/SagerNet/sing-box/releases/download/${latest_tag}/${asset_name}"
                log_info "Downloading $download_url ..."
                if curl -sfL --max-time 120 -o "$tmp_dir/sing-box.tar.gz" "$download_url"; then
                    downloaded="1"
                    arch="$candidate_arch"
                    break
                fi
            done
            if [ -z "$downloaded" ]; then
                fail_update "download failed"
            fi
            verify_archive_checksum "$tmp_dir/sing-box.tar.gz" "$latest_tag" "$asset_name" || \
                fail_update "archive checksum verification failed"
            # busybox tar 不支持 --wildcards，先全量解压再 find
            if ! tar -xzf "$tmp_dir/sing-box.tar.gz" -C "$tmp_dir" 2>/dev/null; then
                fail_update "archive extraction failed"
            fi
            local extracted
            extracted=$(find "$tmp_dir" -type f -name "sing-box" | head -1)
            if [ -z "$extracted" ]; then
                fail_update "binary not found in archive"
            fi
            install_verified_binary "$extracted" "$SINGBOX_BIN"
            ;;
        xray)
            asset_name="Xray-${arch}.zip"
            download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_tag}/${asset_name}"
            log_info "Downloading $download_url ..."
            if ! curl -sfL --max-time 120 -o "$tmp_dir/xray.zip" "$download_url"; then
                fail_update "download failed"
            fi
            verify_archive_checksum "$tmp_dir/xray.zip" "$latest_tag" "$asset_name" || \
                fail_update "archive checksum verification failed"
            # xray zip 根目录直接包含 xray 二进制；重定向 stdout 避免污染 JSON 输出
            unzip -o "$tmp_dir/xray.zip" xray -d "$tmp_dir" >/dev/null 2>&1
            if [ ! -f "$tmp_dir/xray" ]; then
                fail_update "binary not found in archive"
            fi
            install_verified_binary "$tmp_dir/xray" "$XRAY_BIN"
            ;;
    esac

    rm -rf "$tmp_dir"
    UPDATE_TMP_DIR=""
    log_info "$CORE updated to $latest_tag"
    printf '{"success":true,"version":"%s"}\n' "$latest_tag"
}

# ── 入口 ─────────────────────────────────────────────────────────────
case "$ACTION" in
    version) get_local_version ;;
    latest)  get_latest_version_json ;;
    update)  do_update ;;
esac
