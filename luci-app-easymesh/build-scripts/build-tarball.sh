#!/bin/bash
set -e

SRC="/home/zamimondol/easymesh-build/src/luci-app-easymesh"
OUT="/home/zamimondol/easymesh-build/output"
BUILD="/tmp/easymesh-tarball"
PO2LMO="/home/zamimondol/easymesh-build/sdk-24.10/staging_dir/hostpkg/bin/po2lmo"

VERSION="2.4.1-r1"

mkdir -p "$OUT"
rm -rf "$BUILD"
mkdir -p "$BUILD"

# =========================================================
# Main app tarball
# =========================================================
echo "==> Building main tarball..."

STAGE="$BUILD/stage-main"
mkdir -p "$STAGE"

# luasrc/  ->  usr/lib/lua/luci/
mkdir -p "$STAGE/usr/lib/lua/luci"
cp -a "$SRC/luasrc/." "$STAGE/usr/lib/lua/luci/"

# root/  ->  ./ (etc/init.d/easymesh, etc/config/easymesh, etc/uci-defaults/, usr/share/...)
if [ -d "$SRC/root" ]; then
    cp -a "$SRC/root/." "$STAGE/"
fi

# htdocs/ (if present) -> www/
if [ -d "$SRC/htdocs" ]; then
    mkdir -p "$STAGE/www"
    cp -a "$SRC/htdocs/." "$STAGE/www/"
fi

# Remove stray files
find "$STAGE" -name '*.luadoc' -delete
find "$STAGE" -name '.git*' -delete 2>/dev/null || true

# Build the tarball with clean permissions
cd "$STAGE"
find . -type d -exec chmod 755 {} \;
find . -type f -exec chmod 644 {} \;
chmod 755 etc/init.d/easymesh 2>/dev/null || true

tar czf "$OUT/luci-app-easymesh-${VERSION}-all.tar.gz" \
    --numeric-owner --owner=0 --group=0 \
    --sort=name \
    --mtime='2026-09-11 00:00:00' \
    -C "$STAGE" \
    ./etc ./usr 2>/dev/null || \
tar czf "$OUT/luci-app-easymesh-${VERSION}-all.tar.gz" \
    --numeric-owner --owner=0 --group=0 \
    -C "$STAGE" .

echo "    Created: $OUT/luci-app-easymesh-${VERSION}-all.tar.gz"
ls -lh "$OUT/luci-app-easymesh-${VERSION}-all.tar.gz"

# Show what's inside
echo ""
echo "    Contents:"
tar tzf "$OUT/luci-app-easymesh-${VERSION}-all.tar.gz" | head -25

# =========================================================
# i18n tarball
# =========================================================
if [ -x "$PO2LMO" ] && [ -f "$SRC/po/zh_Hans/easymesh.po" ]; then
    echo ""
    echo "==> Building i18n tarball..."

    STAGE_I18N="$BUILD/stage-i18n"
    mkdir -p "$STAGE_I18N/usr/lib/lua/luci/i18n"
    mkdir -p "$STAGE_I18N/etc/uci-defaults"

    "$PO2LMO" "$SRC/po/zh_Hans/easymesh.po" \
        "$STAGE_I18N/usr/lib/lua/luci/i18n/easymesh.zh-cn.lmo"

    echo "uci set luci.languages.zh_cn='简体中文 (Chinese Simplified)'; uci commit luci" \
        > "$STAGE_I18N/etc/uci-defaults/luci-i18n-easymesh-zh-cn"

    chmod -R 755 "$STAGE_I18N/etc"
    chmod 644 "$STAGE_I18N/usr/lib/lua/luci/i18n/easymesh.zh-cn.lmo"

    tar czf "$OUT/luci-i18n-easymesh-zh-cn-${VERSION}-all.tar.gz" \
        --numeric-owner --owner=0 --group=0 \
        --sort=name \
        --mtime='2026-09-11 00:00:00' \
        -C "$STAGE_I18N" .

    echo "    Created: $OUT/luci-i18n-easymesh-zh-cn-${VERSION}-all.tar.gz"
    ls -lh "$OUT/luci-i18n-easymesh-zh-cn-${VERSION}-all.tar.gz"
else
    echo "!! po2lmo not found, skipping i18n tarball"
fi

# =========================================================
# Combined "install everything" tarball
# =========================================================
echo ""
echo "==> Building combined tarball (main + i18n)..."

STAGE_ALL="$BUILD/stage-all"
mkdir -p "$STAGE_ALL"
cp -a "$BUILD/stage-main/." "$STAGE_ALL/"
[ -d "$BUILD/stage-i18n" ] && cp -a "$BUILD/stage-i18n/." "$STAGE_ALL/"

tar czf "$OUT/luci-app-easymesh-${VERSION}-full.tar.gz" \
    --numeric-owner --owner=0 --group=0 \
    --sort=name \
    --mtime='2026-09-11 00:00:00' \
    -C "$STAGE_ALL" .

echo "    Created: $OUT/luci-app-easymesh-${VERSION}-full.tar.gz"
ls -lh "$OUT/luci-app-easymesh-${VERSION}-full.tar.gz"

echo ""
echo "============================================================"
echo "Tarballs in $OUT:"
ls -lh "$OUT"/*.tar.gz
