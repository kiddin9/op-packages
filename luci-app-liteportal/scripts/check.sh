#!/bin/sh
# Local and CI gate for luci-app-liteportal.
#
# This project is a pure script package with no compiled unit tests, so the gate
# is syntax-level plus cross-reference consistency. It runs the very same script
# locally and in CI (.github/workflows/build.yml) so the two cannot drift.
#
# Add a check here and in nothing else - CI invokes this file directly.
#
# Usage: sh scripts/check.sh      (no arguments, no configuration)

set -eu

cd "$(dirname "$0")/.."
ROOT=$(pwd)

failed=0
note() { printf '\n--- %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }
ok() { printf '  ok  %s\n' "$1"; }

# ---------------------------------------------------------------- JS syntax
# The four LuCI views/resources and the standalone portal frontend. `node
# --check` parses without executing, so no LuCI runtime is needed.
note "JavaScript syntax"
if ! command -v node >/dev/null 2>&1; then
	# Skipping loudly beats five bogus FAILs: `node: command not found` would
	# otherwise be reported as a syntax error in every file.
	printf '  skip  node not installed (CI has it; see build.yml)\n'
else
	for f in \
		htdocs/luci-static/resources/liteportal/common.js \
		htdocs/luci-static/resources/view/liteportal/general.js \
		htdocs/luci-static/resources/view/liteportal/bookmarks.js \
		htdocs/luci-static/resources/view/liteportal/assets.js \
		root/usr/share/liteportal/www/liteportal.js
	do
		if node --check "$f" 2>/tmp/liteportal-check-js.$$; then
			ok "$f"
		else
			fail "$f"
			cat /tmp/liteportal-check-js.$$ >&2
		fi
	done
	rm -f /tmp/liteportal-check-js.$$
fi

# ---------------------------------------------------------------- form logic
# The LuCI form layer cannot run in a browser here, but the rule that shipped
# broken once is checkable from the source: LuCI ORs multiple depends() calls,
# so an option gated on two conditions must use the object form. The custom
# search URL used two calls, which kept it - and its validator - active for
# every engine once the search box was on, and an empty value then failed the
# whole save. scripts/test-search-form.js extracts the real declarations and
# checks the dependency shape, its effect under those semantics, the validator
# matrix and the shared regex of the two gates.
note "search form dependency and validator"
if command -v node >/dev/null 2>&1; then
	if node scripts/test-search-form.js; then
		ok "search_url depends() is an AND; validator matrix holds"
	else
		fail "scripts/test-search-form.js"
	fi
else
	printf '  skip  node not installed (CI has it; see build.yml)\n'
fi

# ---------------------------------------------------------------- JSON
# The menu registration and the rpcd ACL. Both are consumed by LuCI/rpcd at
# runtime: a syntax error there is invisible until the page fails to load, and
# an ACL error shows up only as "Access denied" in the browser.
note "JSON"
for f in \
	root/usr/share/luci/menu.d/luci-app-liteportal.json \
	root/usr/share/rpcd/acl.d/luci-app-liteportal.json
do
	if python3 -m json.tool "$f" >/dev/null 2>&1; then
		ok "$f"
	else
		fail "$f is not valid JSON"
	fi
done

# ---------------------------------------------------------------- menu -> views
# A menu entry of type "view" is loaded as the module `view.<path with / -> .>`
# - luci-base's ui.js builds it as `'view.%s'.format(path.replace(/\//g, '.'))`
# - so `"path": "liteportal/general"` means
# htdocs/luci-static/resources/view/liteportal/general.js. Nothing ties the two
# strings together, and a mismatch is not an error: the content area comes up
# empty and the page just looks broken. The 4.0.0 rename did hit this - the
# views moved to view/liteportal/ while the menu went on naming view/portal/.
note "menu entries point at views that exist"
menu_json=root/usr/share/luci/menu.d/luci-app-liteportal.json
view_paths=$(grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$menu_json" |
	sed 's/.*:[[:space:]]*"\([^"]*\)"$/\1/')
if [ -z "$view_paths" ]; then
	fail "no \"path\" entry found in $menu_json"
else
	for p in $view_paths; do
		if [ -f "htdocs/luci-static/resources/view/$p.js" ]; then
			ok "view/$p.js"
		else
			fail "$menu_json names view/$p.js, which does not exist"
		fi
	done
fi

note "shell"
if command -v shellcheck >/dev/null 2>&1; then
	if shellcheck -s sh root/etc/init.d/liteportal; then
		ok "root/etc/init.d/liteportal"
	else
		fail "root/etc/init.d/liteportal"
	fi
else
	printf '  skip  shellcheck not installed (CI installs it; see build.yml)\n'
	# A missing shellcheck must not read as a pass, but it also must not fail
	# a contributor who only has a bare shell. The syntax check below still
	# runs, so the gate degrades rather than disappears.
	sh -n root/etc/init.d/liteportal || fail "root/etc/init.d/liteportal does not parse"
fi

# ---------------------------------------------------------------- translations
# msgfmt --check reports malformed format strings and fuzzy/untranslated
# entries, which LuCI would render as broken buttons at runtime.
note "translations"
if command -v msgfmt >/dev/null 2>&1; then
	if msgfmt --check -o /dev/null po/zh_Hans/liteportal.po; then
		ok "po/zh_Hans/liteportal.po"
	else
		fail "po/zh_Hans/liteportal.po"
	fi
else
	printf '  skip  msgfmt not installed (gettext)\n'
fi

# ---------------------------------------------------------------- ubus <-> ACL
# The security-relevant cross-reference: every method liteportal.uc exposes must be
# listed in the ACL, otherwise the view silently gets "Access denied". Checking
# it here turns a runtime-only failure into a build failure.
note "ubus methods are covered by the ACL"
# liteportal.uc exposes its methods through the `const methods = { name: { call: …
# } }` table at the end of the file, so read the names from there rather than
# from call sites or comments.
methods=$(sed -n '/^const methods = {/,/^};/p' root/usr/share/rpcd/ucode/liteportal.uc |
	sed -n 's/^[[:space:]]*\([a-z_][a-z_0-9]*\):[[:space:]]*{.*/\1/p' | sort -u)
if [ -z "$methods" ]; then
	fail "could not read the method table from liteportal.uc (expected \`const methods = { … }\`)"
else
	acl=$(cat root/usr/share/rpcd/acl.d/luci-app-liteportal.json)
	for m in $methods; do
		if printf '%s' "$acl" | grep -q "\"$m\""; then
			ok "luci.liteportal.$m"
		else
			fail "luci.liteportal.$m is exposed by liteportal.uc but absent from the ACL"
		fi
	done
fi

# ---------------------------------------------------------------- identifiers
# One runtime identifier lives in seven files at once (AGENTS.md §8: "change it
# in one place and you change it in five"). Nothing keeps them in sync at
# runtime, and a stale value in any one of them fails quietly on the device: the
# settings page fetches a URL that does not resolve, or the backend writes into
# a directory uhttpd does not serve, and what the user sees is a blank page
# rather than a message. The 4.0.0 rename did hit exactly this - URL_BASE and
# PORTAL_PATH kept '/portal' while every path around them had moved.
#
# The expected values are derived from the package name in the Makefile, not
# compared against one another, so the whole table is pinned to the package name
# instead of agreeing on a stale value. PKG_NAME is the upstream field; LUCI_NAME
# is luci.mk's own fallback for trees that leave it to the directory name.
note "runtime identifiers agree"
slug=$(sed -n 's/^PKG_NAME:=luci-app-\(.*\)$/\1/p' Makefile | head -n 1)
[ -n "$slug" ] || slug=$(sed -n 's/^LUCI_NAME:=luci-app-\(.*\)$/\1/p' Makefile | head -n 1)
if [ -z "$slug" ]; then
	fail "could not read PKG_NAME (or LUCI_NAME) from the Makefile"
else
	eq() {  # label expected actual
		if [ "$2" = "$3" ]; then
			ok "$1 = $3"
		else
			fail "$1 is '$3', expected '$2'"
		fi
	}
	val() { sed -n "$2" "$1" 2>/dev/null | head -n 1; }

	uc=root/usr/share/rpcd/ucode/$slug.uc
	init=root/etc/init.d/$slug
	acl_json=root/usr/share/rpcd/acl.d/luci-app-$slug.json
	assets=htdocs/luci-static/resources/view/$slug/assets.js
	bookmarks=htdocs/luci-static/resources/view/$slug/bookmarks.js
	common=htdocs/luci-static/resources/$slug/common.js

	sub=/$slug
	www=/www/$slug
	tmp=/tmp/${slug}_upload.tmp
	conf=/etc/config/$slug

	# The sub-path the page is served under, in the backend and in both places
	# the frontend has to build an asset URL of its own.
	eq "ucode URL_BASE"            "$sub"  "$(val "$uc" "s/^const URL_BASE = '\([^']*\)';.*/\1/p")"
	eq "assets.js PORTAL_PATH"     "$sub"  "$(val "$assets" "s/^const PORTAL_PATH = '\([^']*\)';.*/\1/p")"
	eq "common.js status fallback" "$sub/" "$(val "$common" "s/.*st\.path || '\([^']*\)'.*/\1/p")"

	# The document root directory it is published into.
	eq "ucode WWW"                "$www"       "$(val "$uc" "s/^const WWW = '\([^']*\)';.*/\1/p")"
	eq "init.d LITEPORTAL_WWW"    "$www"       "$(val "$init" "s|^LITEPORTAL_WWW=\(.*\)$|\1|p")"
	eq "bookmarks.js WWW"         "$www"       "$(val "$bookmarks" "s/^const WWW = '\([^']*\)';.*/\1/p")"
	eq "Makefile postinst mkdir"  "$www"       "$(val Makefile "s|^mkdir -p \(/www/[^ ]*\)$|\1|p")"
	# prerm removes the files the package published, one by one: the directory
	# itself also holds the icons and backgrounds the user uploaded, so a
	# `rm -rf` there would delete them and leave uci pointing at nothing. Same
	# rule as init.d's unpublish(). Each name is checked against the document
	# root derived from the package name, so a rename cannot leave a stale path.
	prerm_block=$(sed -n "/^define Package\/luci-app-$slug\/prerm\$/,/^endef\$/p" Makefile)
	if printf '%s\n' "$prerm_block" | grep -q '^rm -rf'; then
		fail "Makefile prerm deletes a directory instead of the published files"
	else
		ok "Makefile prerm deletes no directory (uploads survive an uninstall)"
	fi
	for f in index.html liteportal.js liteportal.css links.json; do
		if printf '%s' "$prerm_block" | tr -d '\\\n' | grep -q "$www/$f"; then
			ok "Makefile prerm removes $www/$f"
		else
			fail "Makefile prerm does not remove $www/$f"
		fi
	done
	eq "assets.js ICON_DIR"       "$www/icons" "$(val "$assets" "s/^const ICON_DIR = '\([^']*\)';.*/\1/p")"
	eq "assets.js BG_DIR"         "$www/bg"    "$(val "$assets" "s/^const BG_DIR = '\([^']*\)';.*/\1/p")"
	eq "init.d LITEPORTAL_SRC"    "/usr/share/$slug/www" "$(val "$init" "s|^LITEPORTAL_SRC=\(.*\)$|\1|p")"

	# The one path a browser request is allowed to write to.
	eq "ucode TMP_UPLOAD"    "$tmp" "$(val "$uc" "s/^const TMP_UPLOAD = '\([^']*\)';.*/\1/p")"
	eq "assets.js TMP_UPLOAD" "$tmp" "$(val "$assets" "s/^const TMP_UPLOAD = '\([^']*\)';.*/\1/p")"
	eq "acl staging file"    "$tmp" "$(grep -o '"/tmp/[^"]*"' "$acl_json" | tr -d '"' | head -n 1)"

	# The uci package, its configuration file and the conffile declaration.
	eq "ucode CONFIG"      "$slug" "$(val "$uc" "s/^const CONFIG = '\([^']*\)';.*/\1/p")"
	eq "config section"    "$slug" "$(val "root/etc/config/$slug" "s/^config \(.*\)$/\1/p")"
	eq "Makefile conffiles" "$conf" "$(val Makefile "s|^\(/etc/config/[^ ]*\)$|\1|p")"
	eq "init.d uci lookup" "$slug.@$slug[0].enabled" \
		"$(grep -o 'uci -q get [^)]*' "$init" | sed 's/^uci -q get //' | head -n 1)"

	# The ubus object name.
	eq "ucode ubus object"    "luci.$slug" "$(val "$uc" "s/.*return { '\(luci\.[^']*\)'.*/\1/p")"
	eq "acl ubus object"      "luci.$slug" "$(grep -o '"luci\.[^"]*"' "$acl_json" | tr -d '"' | head -n 1)"
	eq "common.js ubus object" "luci.$slug" "$(val "$common" "s/.*object: '\([^']*\)'.*/\1/p")"

	# The menu path, and the fact that every ACL path stays inside the tree the
	# package owns (a widened path would grant access to /www itself).
	eq "menu path" "admin/services/$slug" \
		"$(grep -o '"admin/services/[^"]*"' "$menu_json" | tr -d '"' | head -n 1)"
	unscoped=
	for p in $(grep -oE '"/(www|tmp)/[^"]*"' "$acl_json" | tr -d '"'); do
		case "$p" in
			"$www"|"$www"/*|"$tmp") ;;
			*) unscoped="$unscoped $p" ;;
		esac
	done
	if [ -z "$unscoped" ]; then
		ok "acl file paths stay under $www and $tmp"
	else
		fail "acl grants paths outside the package's own tree:$unscoped"
	fi

	# The sweep that would have caught the 4.0.0 misses directly. Shipped code is
	# held to zero occurrences; the Makefile is included but only outside
	# comments, because the postinst explains in prose why it carries no
	# migration code and has to name the old paths to do it. docs/ and dist/ are
	# not scanned - they keep the historical names deliberately.
	stale_re="luci\.portal|/etc/config/portal|/etc/init\.d/portal|/www/portal|/usr/share/portal|/tmp/portal_upload|admin/services/portal|['\"]/portal|/etc/portal"
	stale=$(
		{
			grep -rnE "$stale_re" htdocs root 2>/dev/null
			grep -nE "$stale_re" Makefile 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#'
		} || true
	)
	if [ -n "$stale" ]; then
		printf '%s\n' "$stale" >&2
		fail "an old runtime identifier is still in the shipped tree"
	else
		ok "no old identifier left in htdocs/, root/ or the Makefile"
	fi
fi

# ---------------------------------------------------------------- rpc call sites
# Every rpc.declare() in this app uses the array form of `params`, which maps
# the arguments positionally - `params: [ 'dir', 'name' ]` means the call has to
# be fn(dir, name). An object argument is silently taken as the first parameter
# itself, so the request ends up as { dir: { ... } } with no name, and ubus
# rejects it with UBUS_STATUS_INVALID_ARGUMENT. The view used to report that
# rejection as a success, so this is worth a build failure rather than a device
# test. Declared methods are the `call*` bindings by convention.
note "rpc call sites pass positional arguments"
objcalls=$(grep -rnE 'call[A-Z][A-Za-z0-9_]*\(\{' \
	htdocs/luci-static/resources 2>/dev/null || true)
if [ -n "$objcalls" ]; then
	printf '%s\n' "$objcalls" >&2
	fail "an rpc call passes an object to an array-style params declaration"
else
	ok "no object arguments to declared rpc methods"
fi

# ---------------------------------------------------------------- line endings
# .gitattributes forces LF in the index. A CRLF shell script breaks on the
# device with "bad interpreter", so a CRLF working tree is worth failing on.
note "line endings"
crlf=$(git ls-files --eol 2>/dev/null | grep -c 'w/crlf' || true)
if [ "${crlf:-0}" -eq 0 ]; then
	ok "all tracked files are LF in the working tree"
else
	fail "$crlf tracked file(s) are CRLF in the working tree; run: git add --renormalize ."
fi

# ---------------------------------------------------------------- cache
# links.json is a static file: uhttpd answers it with Last-Modified and ETag
# only, never Cache-Control. Without an explicit freshness lifetime a browser
# caches it heuristically (about 10% of the file's age), so a portal that has
# not changed for a day keeps reading a stale copy for hours - and every
# appearance slider looks broken until a hard reload. The fetch must keep
# bypassing that cache; losing the option is invisible in a fresh browser and
# only shows up on a device that has been running for a while.
note "links.json is fetched around the browser cache"
if grep -qF "fetch('links.json', { cache: 'no-store' })" root/usr/share/liteportal/www/liteportal.js; then
	ok "no-store"
else
	fail "liteportal.js must fetch links.json with { cache: 'no-store' }"
fi

# ---------------------------------------------------------------- placeholders
# This repository was generated from ai-template-repository. A leftover
# {{PLACEHOLDER}} means a file escaped the fill-in step.
#
# docs/configuration.md is excluded on purpose: it documents the placeholder
# syntax, so it necessarily contains the literal and would match itself.
# .build is excluded because it holds scratch checkouts and their node_modules,
# which are gitignored and never shipped. .workbuddy holds agent working notes,
# which quote source snippets verbatim rather than being deliverables.
note "template placeholders"
ph_files=$(grep -rln '{{' \
	--include='*.md' --include='*.js' --include='*.uc' --include='*.json' \
	--exclude-dir=.git --exclude-dir=dist --exclude-dir=.build --exclude-dir=.workbuddy . 2>/dev/null | grep -v 'docs/configuration.md' || true)
if [ -n "$ph_files" ]; then
	printf '%s\n' "$ph_files" >&2
	grep -n '{{' $(printf '%s' "$ph_files" | tr '\n' ' ') >&2 || true
	fail "unresolved template placeholders in the files above"
else
	ok "none"
fi

# ---------------------------------------------------------------- verdict
printf '\n'
if [ "$failed" -ne 0 ]; then
	printf 'CHECKS FAILED\n' >&2
	exit 1
fi
printf 'ALL CHECKS PASSED\n'
