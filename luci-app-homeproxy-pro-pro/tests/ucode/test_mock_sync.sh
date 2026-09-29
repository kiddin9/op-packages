#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# The test doubles must still behave like the production code they copy.
#
# tests/ucode/mocks/homeproxy.uc says of isEmpty/decodeBase64Str/parseURL:
# "verbatim copy so the parser tests exercise the same string handling as
# production. Keep these in sync when homeproxy.uc changes."  Nothing enforced
# that sentence.  tests/ucode/mocks/homeproxy_fetcher.uc carries the same note
# for redactUrl, and the *security* assertion in
# test_subscription_fetcher.uc - that a subscription token cannot reappear in
# the log - is made against that copy, not against the production function.
#
# Editing the production function alone would therefore leave every test green
# while the behaviour they claim to check had changed.  This compares the two
# implementations on a shared corpus, which is what "in sync" has to mean: the
# mock is allowed to be reformatted (redactUrl's copy already reorders a couple
# of statements), only the results must agree.
#
# validation() is deliberately NOT compared.  It is a pure-ucode stand-in for
# /sbin/validate_data, so it differs from the real thing by design; it is
# pinned by its own unit tests instead.
#
# Usage: sh tests/ucode/test_mock_sync.sh <repo-root> [workdir]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
WORK="${2:-/tmp/hp-mock-sync}"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi


rm -rf "$WORK"
mkdir -p "$WORK"

# production parseURL() validates the hostname by shelling out to the hardcoded
# /sbin/validate_data. On a device that binary exists; off-target it does not,
# and production then returns null for every URL while the mock - which carries
# its own pure-ucode validation() - parses them happily. An environment variable
# would not help: the path is a literal in the source, so the staged copy has to
# be rewritten, exactly as tests/ucode/test_generators.sh does it. Without this
# the test passed on the device and failed in CI, which is how it was found.
VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
if [ ! -x "$VALIDATE_DATA" ] && [ -x "$ROOT/tests/toolchain/validate-data.sh" ]; then
	VALIDATE_DATA="$ROOT/tests/toolchain/validate-data.sh"
fi

mkdir -p "$WORK/scripts"
sed -e "s#/sbin/validate_data#$VALIDATE_DATA#" \
	"$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$WORK/scripts/homeproxy.uc"

cat > "$WORK/sync.uc" <<'DRIVER'
import {
	isEmpty as p_isEmpty,
	decodeBase64Str as p_decodeBase64Str,
	redactUrl as p_redactUrl,
	parseURL as p_parseURL,
	shellQuote as p_shellQuote
} from '@@SCRIPTS@@/homeproxy.uc';
import {
	isEmpty as m_isEmpty,
	decodeBase64Str as m_decodeBase64Str,
	parseURL as m_parseURL,
	shellQuote as m_shellQuote
} from '@@MOCK-HP@@';
import { redactUrl as f_redactUrl } from '@@MOCK-FETCHER@@';

let checks = 0, failures = 0;
function same(name, a, b) {
	checks++;
	const sa = sprintf('%J', a), sb = sprintf('%J', b);
	if (sa === sb) return;
	failures++;
	printf('FAIL %s: production %s vs mock %s\n', name, sa, sb);
}

/* --- isEmpty ------------------------------------------------------------ */
const empty_corpus = ['', null, 'nil', [], {}, [1], { a: 1 }, 0, 'x', '0', false, true, [ [] ]];
for (let v in empty_corpus)
	same(sprintf('isEmpty(%J)', v), p_isEmpty(v), m_isEmpty(v));

/* --- decodeBase64Str ---------------------------------------------------- */
const b64_corpus = [
	'', 'aGVsbG8=', 'aGVsbG8', 'aGVsbG8h', 'a-b_c', 'a+b/c', '!!!!',
	'AA==', 'AAA=', 'AAAA', '  aGVsbG8=  ', 'not base64 at all', '===='
];
for (let v in b64_corpus)
	same(sprintf('decodeBase64Str(%J)', v), p_decodeBase64Str(v), m_decodeBase64Str(v));

/* --- shellQuote --------------------------------------------------------- */
const quote_corpus = [
	'', 'plain', "it's", "a'b'c", 'has space', '"double"', '$var', '`cmd`',
	'; rm -rf /', 'a\\b', "mix'\"$`"
];
for (let v in quote_corpus)
	same(sprintf('shellQuote(%J)', v), p_shellQuote(v), m_shellQuote(v));

/* --- redactUrl: the fetcher mock's copy -------------------------------- */
const url_corpus = [
	'',
	'https://host/path',
	'https://user:pass@host/path?token=secret',
	'https://user@host/path',
	'https://host/path?a=1&b=2',
	'https://host/path?a=1#frag',
	'ss://method:password@host:8388#label',
	'not a url',
	'https://host/path?',
	'://@?'
];
for (let v in url_corpus)
	same(sprintf('redactUrl(%J)', v), p_redactUrl(v), f_redactUrl(v));

/* --- parseURL: only inputs where the real validate_data and the stand-in
 * agree, since validation() is allowed to differ. ------------------------ */
const parse_corpus = [
	'https://example.com/path',
	'https://example.com:8443/path?x=1#h',
	'http://user:pass@example.com/p',
	'https://1.2.3.4/p',
	'https://[2001:db8::1]:443/p',
	'ftp://example.com/p',
	'',
	'not a url',
	'https://',
	'https:///path'
];
for (let v in parse_corpus)
	same(sprintf('parseURL(%J)', v), p_parseURL(v), m_parseURL(v));

printf('mock sync: %d checks, %d failures\n', checks, failures);
exit(failures ? 1 : 0);
DRIVER

sed -e "s#@@SCRIPTS@@#$WORK/scripts#" \
    -e "s#@@MOCK-HP@@#$ROOT/tests/ucode/mocks/homeproxy.uc#" \
    -e "s#@@MOCK-FETCHER@@#$ROOT/tests/ucode/mocks/homeproxy_fetcher.uc#" \
    "$WORK/sync.uc" > "$WORK/sync.uc.new"
mv -f "$WORK/sync.uc.new" "$WORK/sync.uc"

if ucode -L "$ROOT/root/etc/homeproxy/scripts" "$WORK/sync.uc"; then
	echo "PASS: the test doubles agree with production"
	rm -rf "$WORK"
	exit 0
else
	echo "FAIL: a test double has drifted from the production function it copies"
	rm -rf "$WORK"
	exit 1
fi
