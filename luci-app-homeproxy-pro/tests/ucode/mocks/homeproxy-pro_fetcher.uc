/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * homeproxy-pro module shim for subscription/fetcher unit tests.
 *
 * The real homeproxy-pro.uc wraps wGETVerbose around `executeCommand(
 * uclient-fetch ...)`, which means a unit test that imports it
 * would shell out to the network. Tests stage this file as
 * `homeproxy-pro` in their -L directory so the fetcher picks up the
 * shim's wGETVerbose instead.
 *
 * The shim reads HP_TEST_WGET_CONTENT / HP_TEST_WGET_ERROR globals
 * (set by the test before each fetch call) and returns them. The
 * two other names the fetcher imports (isEmpty, redactUrl) are
 * short enough to copy verbatim from homeproxy-pro.uc so the shim is
 * fully self-contained - the real homeproxy-pro.uc also imports
 * validate_data / popen / a long list of luci.* modules that the
 * testbed does not have on PATH, and pulling the full file would
 * pull those imports along.
 *
 * The `global` prefix is the only cross-module shared state ucode
 * exposes without a dependency-injection hook, and the test is the
 * only writer.
 */

export function wGETVerbose(url, _ua) {
	const content = global.HP_TEST_WGET_CONTENT;
	const error = global.HP_TEST_WGET_ERROR;
	return { content: content, error: error };
};

export function isEmpty(res) {
	return !res || res === 'nil' || (type(res) in ['array', 'object'] && length(res) === 0);
};

/* Verbatim copy of homeproxyuc:redactUrl - keeps the security
 * behaviour covered in test_subscription_fetcher.uc. */
export function redactUrl(url) {
	if (!url || type(url) !== 'string')
		return '';

	let u = url;

	/* userinfo: scheme://user:pass@host -> scheme://***@host */
	const at = index(u, '@');
	const scheme = match(u, /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//);
	if (scheme && at !== -1 && at > length(scheme[0]))
		u = substr(u, 0, length(scheme[0])) + '***' + substr(u, at);

	/* path and query: keep the authority, mark the rest.  Splitting them
	 * rather than masking from the first '/' keeps the structural markers
	 * (`/***?***`) so a reader can still tell a path from a query, and it is
	 * why the authority end is the *earlier* of the two separators. */
	const scheme_end = scheme ? length(scheme[0]) : 0;
	const rest = substr(u, scheme_end);
	const path_at = index(rest, '/');
	const query_at = index(rest, '?');
	const has_path = path_at !== -1 && (query_at === -1 || path_at < query_at);

	let authority_end = length(rest);
	if (has_path)
		authority_end = path_at;
	else if (query_at !== -1)
		authority_end = query_at;

	let tail = '';
	if (has_path)
		tail += '/***';
	if (query_at !== -1)
		tail += '?***';

	u = substr(u, 0, scheme_end + authority_end) + tail;

	return u;
};