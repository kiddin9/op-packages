#!/bin/sh
# Open-Box 一键安装脚本
set -eu
umask 022

REPO="liandu2024/Open-Box"
INSTALL_ROOT="/opt/open-box"
CHANNEL="mirror"
MIRROR_PREFIX="https://ghfast.top"
PANEL_PORT="3036"

info() { echo "[open-box] $*"; }
warn() { echo "[open-box] 警告:$*" >&2; }
die() { echo "[open-box] 错误:$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
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
    --direct)
      CHANNEL="direct"
      MIRROR_PREFIX=""
      shift
      ;;
    --port)
      shift
      [ $# -ge 1 ] || die "--port 后面要跟端口号"
      PANEL_PORT="$1"
      shift
      ;;
    *) shift ;;
  esac
done

detect_arch() {
  RAW_ARCH=$(uname -m 2>/dev/null || true)
  case "$RAW_ARCH" in
    x86_64) ARCH="x64" ;;
    aarch64) ARCH="arm64" ;;
    *) die "不支持的 CPU 架构:${RAW_ARCH:-未知}。Open-Box 目前仅支持 x86_64 与 aarch64(arm64)。" ;;
  esac
}

detect_arch

if [ -f "/etc/config/openbox" ]; then
  p=$(uci -q get openbox.main.port 2>/dev/null || true)
  [ -n "$p" ] && PANEL_PORT="$p"
fi

TMP_DL=$(mktemp -d /tmp/openbox-inst.XXXXXX 2>/dev/null || echo "/tmp/openbox-inst.$$")
mkdir -p "$TMP_DL"
trap 'rm -rf "$TMP_DL"' EXIT INT TERM

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

info "下载校验和与发布包: $ASSET ..."
curl -fsSL -o "$TMP_DL/$ASSET.sha256" "$(build_url "$SHA_URL")" 2>/dev/null || wget -q -O "$TMP_DL/$ASSET.sha256" "$(build_url "$SHA_URL")" || die "下载校验文件失败"
curl -fsSL -o "$TMP_DL/$ASSET" "$(build_url "$ASSET_URL")" 2>/dev/null || wget -q -O "$TMP_DL/$ASSET" "$(build_url "$ASSET_URL")" || die "下载发布包失败"

info "校验 SHA256 ..."
( cd "$TMP_DL" && sha256sum -c "$ASSET.sha256" >/dev/null 2>&1 ) || die "安装包校验失败 (SHA256 不匹配)"

info "解包到 $INSTALL_ROOT ..."
mkdir -p "$INSTALL_ROOT"
tar -xzf "$TMP_DL/$ASSET" -C "$INSTALL_ROOT" || die "解包失败"
chown -R 0:0 "$INSTALL_ROOT" 2>/dev/null || true

mkdir -p "$INSTALL_ROOT/data"
printf '%s
' "$PANEL_PORT" > "$INSTALL_ROOT/data/panel-port"
if [ "$CHANNEL" = "mirror" ]; then
  printf 'mirror
%s
' "$MIRROR_PREFIX" > "$INSTALL_ROOT/data/channel"
else
  printf 'direct
' > "$INSTALL_ROOT/data/channel"
fi

cp -f "$INSTALL_ROOT/openwrt/initd/openbox" /etc/init.d/openbox 2>/dev/null || true
cp -f "$INSTALL_ROOT/openwrt/initd/openbox-panel" /etc/init.d/openbox-panel 2>/dev/null || true
chmod +x /etc/init.d/openbox /etc/init.d/openbox-panel 2>/dev/null || true

if [ -f "$INSTALL_ROOT/openwrt/bin/open-box" ]; then
  chmod +x "$INSTALL_ROOT/openwrt/bin/open-box" 2>/dev/null || true
  ln -sf "$INSTALL_ROOT/openwrt/bin/open-box" /usr/bin/open-box 2>/dev/null || true
fi

if [ -d "$INSTALL_ROOT/openwrt/luci/htdocs/luci-static/resources/view/openbox" ]; then
  mkdir -p /www/luci-static/resources/view/openbox
  cp -f "$INSTALL_ROOT/openwrt/luci/htdocs/luci-static/resources/view/openbox/"*.js /www/luci-static/resources/view/openbox/ 2>/dev/null || true
fi

if [ -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json" ]; then
  mkdir -p /usr/share/luci/menu.d
  cp -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json" /usr/share/luci/menu.d/ 2>/dev/null || true
fi

if [ -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json" ]; then
  mkdir -p /usr/share/rpcd/acl.d
  cp -f "$INSTALL_ROOT/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json" /usr/share/rpcd/acl.d/ 2>/dev/null || true
fi

rm -rf /tmp/luci-*cache* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

/etc/init.d/openbox-panel enable >/dev/null 2>&1 || true
/etc/init.d/openbox-panel restart >/dev/null 2>&1 || true

info "Open-Box 核心组件安装完成！"
