#!/bin/sh
# Source builds (feeds / SDK) minify our JS with LuCI's jsmin, which is stricter than a browser:
# for one, it misreads a regex literal that follows `return`. Run every script through the same
# jsmin and make sure the result still parses. Needs cc, curl and node; skipped without them.
set -eu
cd "$(dirname "$0")/.."
T=${TMPDIR:-/tmp}/7dollar-jsmin
mkdir -p "$T"
if [ ! -x "$T/jsmin" ]; then
	curl -sfL -o "$T/jsmin.c" https://raw.githubusercontent.com/openwrt/luci/master/modules/luci-base/src/jsmin.c \
		&& cc -o "$T/jsmin" "$T/jsmin.c" 2>/dev/null || { echo "check-jsmin: skipped (no cc or network)"; exit 0; }
fi
bad=0
for f in $(find htdocs -name '*.js'); do
	"$T/jsmin" < "$f" > "$T/out.js" 2>/dev/null || continue   # jsmin gave up: the buildroot then ships the file as it is
	node -e "new Function(require('fs').readFileSync('$T/out.js','utf8'))" 2>/dev/null || { echo "check-jsmin: $f breaks after jsmin"; bad=1; }
done
exit $bad
