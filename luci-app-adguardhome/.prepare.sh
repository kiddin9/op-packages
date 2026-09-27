PKG_NAME="$1"
CURDIR="$2"
PKG_BUILD_DIR="$3"

if [ -d "$CURDIR/.git" ]; then
	config="$CURDIR/.git/config"
else
	config="$(sed "s|^gitdir:\s*|$CURDIR/|;s|$|/config|" "$CURDIR/.git")"
fi
if grep -q -E "url.*gitcode\.(com|net)" "$config"; then
	for d in htdocs patches po root; do
		rm -rf "$PKG_BUILD_DIR"/$d
	done
	mkdir -p "$PKG_BUILD_DIR"/htdocs/luci-static/resources/view
	touch "$PKG_BUILD_DIR"/htdocs/luci-static/resources/view/$PKG_NAME.js
	mkdir -p "$PKG_BUILD_DIR"/root/usr/share/luci/menu.d
	touch "$PKG_BUILD_DIR"/root/usr/share/luci/menu.d/$PKG_NAME.json
fi
exit 0
