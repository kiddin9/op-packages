#!/bin/sh

set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

REPOSITORY="tpxcer/minigate"
LATEST_ROOT="https://github.com/${REPOSITORY}/releases/latest/download"
TMP_DIR=""
SOURCE_NAME=""
RELEASE_VERSION=""
EXPECTED_HASH=""
DOWNLOADER=""

info() {
    printf '[minigate] %s\n' "$*"
}

die() {
    printf '[minigate] 安装失败：%s\n' "$*" >&2
    exit 1
}

cleanup() {
    case "$TMP_DIR" in
        /tmp/minigate.*) rm -rf -- "$TMP_DIR" ;;
    esac
}

check_system() {
    [ "$(id -u)" = "0" ] || die "请使用 root 用户运行"
    [ -r /etc/openwrt_release ] || die "未检测到 OpenWrt / ImmortalWrt"
    command -v tar >/dev/null 2>&1 || die "系统缺少 tar"
    command -v awk >/dev/null 2>&1 || die "系统缺少 awk"
    command -v sha256sum >/dev/null 2>&1 || die "系统缺少 sha256sum"
}

detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        die "系统缺少 curl 和 wget"
    fi
}

fetch_to_file() {
    case "$DOWNLOADER" in
        curl)
            curl -fsSL --proto '=https' --tlsv1.2 \
                --connect-timeout 10 --max-time 180 --retry 2 --retry-delay 1 \
                -o "$2" "$1"
            ;;
        wget)
            wget -q -O "$2" "$1"
            ;;
    esac
}

valid_version() {
    printf '%s' "$1" | grep -Eq '^[0-9]{4}\.(0?[1-9]|1[0-2])\.(0?[1-9]|[12][0-9]|3[01])(-[1-9][0-9]*)?$'
}

read_release() {
    release_data=$(awk '
        $2 ~ /^minigate-v[0-9][0-9.]*(-[1-9][0-9]*)?-src\.tar\.gz$/ {
            count++
            hash=$1
            file=$2
        }
        END {
            if (count != 1) exit 1
            print hash " " file
        }
    ' "$1") || return 1

    EXPECTED_HASH=${release_data%% *}
    SOURCE_NAME=${release_data#* }
    RELEASE_VERSION=${SOURCE_NAME#minigate-v}
    RELEASE_VERSION=${RELEASE_VERSION%-src.tar.gz}

    [ "${#EXPECTED_HASH}" = "64" ] || return 1
    case "$EXPECTED_HASH" in
        *[!0-9a-fA-F]*) return 1 ;;
    esac
    valid_version "$RELEASE_VERSION"
}

verify_source() {
    actual_hash=$(sha256sum "$1" | awk '{print $1}')
    expected_lower=$(printf '%s' "$EXPECTED_HASH" | tr 'A-F' 'a-f')
    [ "$actual_hash" = "$expected_lower" ] || die "源码包 SHA-256 校验失败"

    if tar -tzf "$1" | awk '{
        path=$0
        sub(/^\.\//, "", path)
        if (path ~ /^\// || path ~ /(^|\/)\.\.(\/|$)/) bad=1
    } END { exit bad ? 0 : 1 }'; then
        die "源码包包含不安全路径"
    fi
}

verify_metadata() {
    source_dir="$1"
    grep -Fxq "PKG_VERSION:=${RELEASE_VERSION}" "$source_dir/Makefile" || return 1
    grep -Fxq "PKG_VERSION=\"${RELEASE_VERSION}\"" "$source_dir/scripts/build-ipk.sh" || return 1
    grep -Fxq "CURRENT_VERSION=\"${RELEASE_VERSION}\"" "$source_dir/root/usr/lib/minigate/update.sh" || return 1
    [ -f "$source_dir/install.sh" ] || return 1
}

download_release() {
    attempt=1
    while [ "$attempt" -le 3 ]; do
        sums_before="$TMP_DIR/SHA256SUMS.before"
        sums_after="$TMP_DIR/SHA256SUMS.after"

        fetch_to_file "$LATEST_ROOT/SHA256SUMS" "$sums_before" || die "无法下载 SHA256SUMS"
        read_release "$sums_before" || die "SHA256SUMS 中没有唯一、有效的 minigate 源码包"
        info "正在下载 minigate v${RELEASE_VERSION}"
        fetch_to_file "$LATEST_ROOT/$SOURCE_NAME" "$TMP_DIR/$SOURCE_NAME" || die "无法下载 $SOURCE_NAME"
        fetch_to_file "$LATEST_ROOT/SHA256SUMS" "$sums_after" || die "无法再次确认 SHA256SUMS"

        if cmp -s "$sums_before" "$sums_after"; then
            return 0
        fi

        info "下载期间发现新版本，正在重新获取"
        attempt=$((attempt + 1))
    done
    die "下载期间版本连续变化，请稍后重试"
}

restart_luci() {
    rm -rf /tmp/luci-*cache* 2>/dev/null || true
    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart
    fi
}

main() {
    check_system
    detect_downloader
    TMP_DIR=$(mktemp -d /tmp/minigate.XXXXXX) || die "无法创建临时目录"
    trap cleanup 0
    trap 'exit 1' 1 2 3 15

    download_release
    verify_source "$TMP_DIR/$SOURCE_NAME"
    info "SHA-256 校验通过"

    mkdir -p "$TMP_DIR/source"
    tar -xzf "$TMP_DIR/$SOURCE_NAME" -C "$TMP_DIR/source" || die "源码包解压失败"
    verify_metadata "$TMP_DIR/source" || die "源码包版本信息不一致"

    /bin/sh "$TMP_DIR/source/install.sh"
    restart_luci
    info "minigate v${RELEASE_VERSION} 安装完成"
}

main "$@"
