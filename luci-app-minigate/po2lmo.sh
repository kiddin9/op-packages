#!/bin/sh
# Convert PO files to LMO for LuCI
# Usage: ./po2lmo.sh
# Run this on a system with luci-base installed, or on the OpenWrt build host

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PO_DIR="${SCRIPT_DIR}/po"
I18N_DIR="${SCRIPT_DIR}/root/usr/lib/lua/luci/i18n"

mkdir -p "$I18N_DIR"

# Method 1: Use po2lmo if available (OpenWrt build system)
if command -v po2lmo >/dev/null 2>&1; then
    for lang_dir in "$PO_DIR"/*/; do
        lang=$(basename "$lang_dir")
        for po_file in "$lang_dir"/*.po; do
            base=$(basename "$po_file" .po)
            echo "Converting: ${lang}/${base}.po -> ${base}.${lang}.lmo"
            po2lmo "$po_file" "${I18N_DIR}/${base}.${lang}.lmo"
        done
    done
    echo "Done! LMO files generated in $I18N_DIR"
    exit 0
fi

# Method 2: Direct install on router (copy PO and let LuCI handle it)
echo "po2lmo not found. Falling back to direct PO installation."
echo ""
echo "To install translations on the router, run:"
echo "  scp po/zh-cn/minigate.po root@<router>:/tmp/"
echo "  ssh root@<router>"
echo "  mkdir -p /usr/lib/lua/luci/i18n"
echo "  po2lmo /tmp/minigate.po /usr/lib/lua/luci/i18n/minigate.zh-cn.lmo"
echo "  rm -rf /tmp/luci-*"
echo ""
echo "Or if building with the OpenWrt SDK, the Makefile handles this automatically."
