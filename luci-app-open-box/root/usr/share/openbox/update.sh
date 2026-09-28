#!/bin/sh
# Open-Box 更新/回退脚本
set -eu
umask 022

REPO="liandu2024/Open-Box"
INSTALL_ROOT="/opt/open-box"
STATUS_PATH="/tmp/openbox-update.status"
CANCEL_FLAG="/tmp/openbox-update.cancel"
UPDATE_LOG="/tmp/openbox-update.log"
STATUS_PID="$$"

DETACH=0
ROLLBACK_MODE=0
CHANNEL="direct"
MIRROR_PREFIX=""
PROBE_CHANNEL=""
CANCEL_MODE=0

info() { echo "[open-box] $*"; }
warn() { echo "[open-box] 警告:$*" >&2; }
die() {
	echo "[open-box] 错误:$*" >&2
	write_status failed "" "" "$*"
	exit 1
}

write_status() {
	[ -n "$STATUS_PID" ] || return 0
	_ws_tmp="$STATUS_PATH.$$.tmp"
	{
		echo "pid=$STATUS_PID"
		echo "stage=$1"
		echo "bytes=${2:-}"
		echo "total=${3:-}"
		echo "message=${4:-}"
	} > "$_ws_tmp" 2>/dev/null && mv -f "$_ws_tmp" "$STATUS_PATH" 2>/dev/null || true
}

check_cancel() {
	if [ -e "$CANCEL_FLAG" ]; then
		write_status cancelled "" "" "已取消更新"
		exit 0
	fi
}

while [ $# -gt 0 ]; do
	case "$1" in
		--detach) DETACH=1; shift ;;
		--rollback) ROLLBACK_MODE=1; shift ;;
		--cancel) CANCEL_MODE=1; shift ;;
		--direct) CHANNEL="direct"; MIRROR_PREFIX=""; shift ;;
		--mirror)
			CHANNEL="mirror"
			shift
			if [ $# -ge 1 ]; then
				case "$1" in
					--*) ;;
					*) MIRROR_PREFIX="$1"; shift ;;
				esac
			fi
			;;
		--probe)
			shift
			PROBE_CHANNEL="$1"
			shift
			;;
		*) shift ;;
	esac
done

if [ "$CANCEL_MODE" = "1" ]; then
	touch "$CANCEL_FLAG" 2>/dev/null || true
	echo "requested"
	exit 0
fi

if [ -n "$PROBE_CHANNEL" ]; then
	start_time=$(date +%s%N 2>/dev/null || date +%s)
	target="https://github.com/$REPO/releases/latest/download/open-box-linux-x64.tar.gz.sha256"
	if [ "$PROBE_CHANNEL" != "direct" ]; then
		case "$PROBE_CHANNEL" in
			http://*|https://*) target="${PROBE_CHANNEL%/}/$target" ;;
			*) target="https://${PROBE_CHANNEL%/}/$target" ;;
		esac
	fi
	if curl -fsSL --connect-timeout 8 --max-time 15 -o /dev/null "$target" 2>/dev/null || 	   wget -q --timeout=15 -O /dev/null "$target" 2>/dev/null; then
		end_time=$(date +%s%N 2>/dev/null || date +%s)
		ms=$(( (end_time - start_time) / 1000000 2>/dev/null || 100 ))
		[ "$ms" -le 0 ] && ms=80
		echo "ok $ms ms"
	else
		echo "fail 连接超时或无法访问"
	fi
	exit 0
fi

if [ "$DETACH" = "1" ]; then
	: > "$UPDATE_LOG" 2>/dev/null || true
	write_status starting "" "" ""
	rm -f "$CANCEL_FLAG" 2>/dev/null || true
	_args=""
	[ "$ROLLBACK_MODE" = "1" ] && _args="$_args --rollback"
	if [ "$CHANNEL" = "mirror" ]; then
		_args="$_args --mirror $MIRROR_PREFIX"
	else
		_args="$_args --direct"
	fi
	nohup sh "$0" $_args >"$UPDATE_LOG" 2>&1 </dev/null &
	echo "升级已在后台启动，进度见 $STATUS_PATH"
	exit 0
fi

write_status probing "" "" ""
check_cancel

RAW_ARCH=$(uname -m 2>/dev/null || true)
case "$RAW_ARCH" in
	x86_64) ARCH="x64" ;;
	aarch64) ARCH="arm64" ;;
	*) die "不支持的 CPU 架构: $RAW_ARCH" ;;
esac

ASSET="open-box-linux-${ARCH}.tar.gz"
ASSET_URL="https://github.com/$REPO/releases/latest/download/$ASSET"
SHA_URL="$ASSET_URL.sha256"

build_url() {
	url="$1"
	if [ "$CHANNEL" = "mirror" ] && [ -n "$MIRROR_PREFIX" ]; then
		case "$MIRROR_PREFIX" in
			http://*|https://*) printf '%s/%s
' "${MIRROR_PREFIX%/}" "$url" ;;
			*) printf 'https://%s/%s
' "${MIRROR_PREFIX%/}" "$url" ;;
		esac
	else
		printf '%s
' "$url"
	fi
}

TMP_DL=$(mktemp -d /tmp/openbox-upd.XXXXXX 2>/dev/null || echo "/tmp/openbox-upd.$$")
mkdir -p "$TMP_DL"
trap 'rm -rf "$TMP_DL"' EXIT INT TERM

write_status downloading 0 100000000 "开始下载"
check_cancel

curl -fsSL -o "$TMP_DL/$ASSET.sha256" "$(build_url "$SHA_URL")" 2>/dev/null || wget -q -O "$TMP_DL/$ASSET.sha256" "$(build_url "$SHA_URL")" || die "下载校验和失败"
check_cancel

curl -fsSL -o "$TMP_DL/$ASSET" "$(build_url "$ASSET_URL")" 2>/dev/null || wget -q -O "$TMP_DL/$ASSET" "$(build_url "$ASSET_URL")" || die "下载升级包失败"
check_cancel

write_status verifying "" "" ""
( cd "$TMP_DL" && sha256sum -c "$ASSET.sha256" >/dev/null 2>&1 ) || die "校验失败 (SHA256 不匹配)"

write_status extracting "" "" ""
check_cancel

STAGE_DIR="$INSTALL_ROOT/.update-stage.$$"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
tar -xzf "$TMP_DL/$ASSET" -C "$STAGE_DIR" || die "解包失败"

write_status committing "" "" ""
/etc/init.d/openbox-panel stop >/dev/null 2>&1 || true
/etc/init.d/openbox stop >/dev/null 2>&1 || true

for comp in node panel bin openwrt; do
	if [ -e "$STAGE_DIR/$comp" ]; then
		rm -rf "$INSTALL_ROOT/$comp"
		mv "$STAGE_DIR/$comp" "$INSTALL_ROOT/$comp"
	fi
done
[ -e "$STAGE_DIR/meta.json" ] && mv "$STAGE_DIR/meta.json" "$INSTALL_ROOT/meta.json"
rm -rf "$STAGE_DIR"

cp -f "$INSTALL_ROOT/openwrt/initd/openbox" /etc/init.d/openbox 2>/dev/null || true
cp -f "$INSTALL_ROOT/openwrt/initd/openbox-panel" /etc/init.d/openbox-panel 2>/dev/null || true
chmod +x /etc/init.d/openbox /etc/init.d/openbox-panel 2>/dev/null || true

if [ -f "$INSTALL_ROOT/openwrt/bin/open-box" ]; then
	ln -sf "$INSTALL_ROOT/openwrt/bin/open-box" /usr/bin/open-box 2>/dev/null || true
fi
if [ -d "$INSTALL_ROOT/openwrt/luci/htdocs/luci-static/resources/view/openbox" ]; then
	cp -f "$INSTALL_ROOT/openwrt/luci/htdocs/luci-static/resources/view/openbox/"*.js /www/luci-static/resources/view/openbox/ 2>/dev/null || true
fi
if [ -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json" ]; then
	cp -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json" /usr/share/luci/menu.d/ 2>/dev/null || true
fi
if [ -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json" ]; then
	cp -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json" /usr/share/rpcd/acl.d/ 2>/dev/null || true
fi

rm -rf /tmp/luci-*cache* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

/etc/init.d/openbox-panel start >/dev/null 2>&1 || true
/etc/init.d/openbox start >/dev/null 2>&1 || true

write_status done "" "" "升级完成"
info "升级完成！"
