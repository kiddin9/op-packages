#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Run the ucode-level tests: the parse_uri unit tests, the fw4 inventory check
# and the generator regression fixtures. Requires ucode; sing-box is needed for
# the generator cases (they validate the emitted config with `sing-box check`).
#
# Usage: sh tests/ucode/run.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-ucode-tests}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

echo "== ucode syntax check =="
for file in "$ROOT"/root/etc/homeproxy/scripts/*.uc "$ROOT"/root/usr/share/rpcd/ucode/*; do
	[ -f "$file" ] || continue
	# Modules (with export statements) cannot be compiled as a program; they
	# are loaded through `import` below instead.
	case "$file" in
	*homeproxy.uc|*parse_uri.uc) continue ;;
	esac
	if ! ucode -c -o "/dev/null" "$file" 2> "/tmp/hp-ucode-syntax.err"; then
		echo "FAIL: $file"
		head -8 "/tmp/hp-ucode-syntax.err"
		FAILED=1
	fi
done
for module in homeproxy parse_uri; do
	if ! ucode -L "$ROOT/root/etc/homeproxy/scripts" -e "import * as m from \"$module\";" 2> "/tmp/hp-ucode-syntax.err"; then
		echo "FAIL: module $module"
		head -8 "/tmp/hp-ucode-syntax.err"
		FAILED=1
	fi
done
[ "$FAILED" -eq 0 ] && echo "PASS: all ucode sources compile"

echo "== fw4 chain/set inventory =="
sh "$ROOT/tests/ucode/test_fw4_names.sh" "$ROOT" || FAILED=1

echo "== firewall template rendering =="
sh "$ROOT/tests/ucode/test_firewall_template.sh" "$ROOT" || FAILED=1

echo "== parse_uri unit tests =="
rm -rf "$WORK/parse_uri"
mkdir -p "$WORK/parse_uri"
cp "$ROOT/root/etc/homeproxy/scripts/parse_uri.uc" "$WORK/parse_uri/"
cp "$ROOT/tests/ucode/mocks/homeproxy.uc" "$WORK/parse_uri/"
cp "$ROOT/tests/ucode/test_parse_uri.uc" "$WORK/parse_uri/"

if ( cd "$WORK/parse_uri" && ucode test_parse_uri.uc ); then
	echo "PASS: parse_uri unit tests"
else
	echo "FAIL: parse_uri unit tests"
	FAILED=1
fi

echo "== homeproxy helper tests =="
rm -rf "$WORK/homeproxy"
mkdir -p "$WORK/homeproxy"
cp "$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" "$WORK/homeproxy/"
cp "$ROOT/tests/ucode/test_homeproxy_utils.uc" "$WORK/homeproxy/"
if ( cd "$WORK/homeproxy" && ucode test_homeproxy_utils.uc ); then
	echo "PASS: executeCommand() regression tests"
else
	echo "FAIL: executeCommand() regression tests"
	FAILED=1
fi

echo "== executeCommand() failure-path test =="
rm -rf "$WORK/homeproxy_inject"
mkdir -p "$WORK/homeproxy_inject"
sed 's|const exitcode = system(.*);|die("injected failure");|' \
	"$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$WORK/homeproxy_inject/homeproxy.uc"
cp "$ROOT/tests/ucode/test_homeproxy_utils_inject.uc" "$WORK/homeproxy_inject/"
if ( cd "$WORK/homeproxy_inject" && ucode test_homeproxy_utils_inject.uc 2>"/dev/null" ); then
	echo "PASS: executeCommand() failure path"
else
	echo "FAIL: executeCommand() failure path"
	FAILED=1
fi

echo "== wget flavour selection =="
# A stub /usr/bin/wget whose --version answer comes from the environment, so
# both flavours can be exercised on a single host. The empty-answer/non-zero
# case is uclient-fetch, whose getopt rejects --version just like it rejects
# -nv before sending anything.
rm -rf "$WORK/wget_flavor"
mkdir -p "$WORK/wget_flavor"
cat > "$WORK/wget_flavor/wget-stub" <<'STUB'
#!/bin/sh
if [ "$1" = "--version" ]; then
	printf '%s\n' "$HP_WGET_STUB_VERSION"
	exit "${HP_WGET_STUB_VERSION_RC:-0}"
fi
for arg in "$@"; do printf '%s\n' "$arg"; done >> "$HP_WGET_STUB_LOG"
printf 'stub body\n'
STUB
chmod +x "$WORK/wget_flavor/wget-stub"
sed "s|/usr/bin/wget|$WORK/wget_flavor/wget-stub|" \
	"$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$WORK/wget_flavor/homeproxy.uc"
cp "$ROOT/tests/ucode/test_wget_flavor.uc" "$WORK/wget_flavor/"

for flavor in gnu compat; do
	if [ "$flavor" = "gnu" ]; then
		version="GNU Wget 1.25.0 built on linux-gnu."
		rc=0
	else
		version=""
		rc=1
	fi
	rm -f "$WORK/wget_flavor/args.log"
	if ( cd "$WORK/wget_flavor" &&
		HP_WGET_EXPECT_FLAVOR="$flavor" \
		HP_WGET_STUB_VERSION="$version" \
		HP_WGET_STUB_VERSION_RC="$rc" \
		HP_WGET_STUB_LOG="$WORK/wget_flavor/args.log" \
		ucode test_wget_flavor.uc ); then
		echo "PASS: wget flavour selection ($flavor)"
	else
		echo "FAIL: wget flavour selection ($flavor)"
		FAILED=1
	fi
done

echo "== real uclient-fetch compatibility =="
# uclient-fetch is the default /usr/bin/wget on OpenWrt/ImmortalWrt, so a
# GNU-only option anywhere in the generated command line has to fail here.
if [ -x /bin/uclient-fetch ]; then
	rm -rf "$WORK/uclient"
	mkdir -p "$WORK/uclient"
	sed "s|/usr/bin/wget|/bin/uclient-fetch|" \
		"$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$WORK/uclient/homeproxy.uc"
	cp "$ROOT/tests/ucode/test_wget_verbose_uclient.uc" "$WORK/uclient/"
	if ( cd "$WORK/uclient" && ucode test_wget_verbose_uclient.uc ); then
		echo "PASS: uclient-fetch accepts the generated command line"
	else
		echo "FAIL: uclient-fetch rejects the generated command line"
		FAILED=1
	fi
else
	echo "SKIP: /bin/uclient-fetch not installed on this host"
fi

echo "== generator regression tests =="
sh "$ROOT/tests/ucode/test_generators.sh" "$ROOT" "$WORK/generators" || FAILED=1

exit $FAILED
