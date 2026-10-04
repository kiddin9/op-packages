/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

import { access, lstat, mkdtemp, open, rmdir, unlink } from 'fs';
import { urldecode_params } from 'luci.http';

/* Global variables start */
export const HP_DIR = '/etc/homeproxy-pro';
export const RUN_DIR = '/var/run/homeproxy-pro';
/* Where the UCI configuration lives. This is /etc/config - NOT HP_DIR/config.
 * The package ships its config as the conffile /etc/config/homeproxy-pro, and
 * ucode's `cursor(dir)` treats `dir` as the *confdir*, so
 * cursor(HP_DIR + '/config') would read /etc/homeproxy-pro/config/homeproxy-pro, a
 * path that exists nowhere.  uci.load() then returns null, every uci.get()
 * returns null, and the Loader silently yields pure defaults: no main-out,
 * no route/direct final, none of the user's ports or nodes.
 * Verified on a device: cursor('/etc/homeproxy-pro/config').get(...) is empty
 * while cursor().get(...) returns the configured value.
 * The test suite stages a rewritten copy of this constant instead of the
 * old `__LOADER_DIR__` source sed. */
export const UCICONFIG_DIR = '/etc/config';
/* Largest subscription body we will fetch, in bytes. See wGETVerbose(). */
export const HP_FETCH_CAP = 5 * 1024 * 1024;
/* Global variables end */

/* Utilities start */
/* Kanged from luci-app-commands */
export function shellQuote(s) {
	return `'${replace(s, "'", "'\\''")}'`;
};

export function isBinary(str) {
	for (let off = 0, byte = ord(str); off < length(str); byte = ord(str, ++off))
		if (byte <= 8 || (byte >= 14 && byte <= 31))
			return true;

	return false;
};

/* Whitelist absolute paths the generators are allowed to put into
 * sing-box config. sing-box runs as root and reads the file itself; an
 * arbitrary UCI value of e.g. /etc/passwd would leak the file to anyone
 * who could write to the UCI tree. The LuCI UI already gates the input
 * via validateCertificatePath() in homeproxy-pro.js, but UCI can be set from
 * any node on the LAN (subscription updates, scripted edits) and the
 * UI check is only UX - we have to enforce on the backend.
 *
 *   /etc/homeproxy-pro/...   - project-managed certs / ruleset paths / etc.
 *   /tmp/homeproxy_*     - upload staging files (cert_upload_* writes)
 *
 * Anything else (relative paths, /etc/passwd, /var/run/...) returns false
 * and the caller is expected to die() / warn() / strip the value. */
export function validateHomeProxyPath(p) {
	if (!p || type(p) !== 'string')
		return false;

	/* Reject traversal *before* the prefix checks below: a plain prefix
	 * comparison accepts '/etc/homeproxy-pro/../../etc/shadow', and sing-box reads
	 * these paths as root. */
	if (match(p, /(^|\/)\.\.(\/|$)/))
		return false;

	/* Reject anything that does not start with '/' - relative paths in
	 * sing-box resolve against the process CWD, which is /tmp at boot
	 * but is not a position we want any UCI value to land in. */
	if (substr(p, 0, 1) !== '/')
		return false;

	if (substr(p, 0, length('/etc/homeproxy-pro/')) === '/etc/homeproxy-pro/')
		return true;

	if (substr(p, 0, length('/tmp/homeproxy_')) === '/tmp/homeproxy_')
		return true;

	return false;
};

/* Certificates the sing-box instances are allowed to read.
 *
 * TLS certificate_path / key_path are not rule-set paths: a server's
 * certificate normally lives under /etc/ssl/ or under the ACME state in
 * /etc/acme/, and the two sing-box jails mount exactly those directories
 * (see runtime/service.sh's procd_add_jail_mount calls). validateHomeProxyPath()
 * only knows /etc/homeproxy-pro/ and /tmp/homeproxy_, so a certificate the user
 * legitimately picked from /etc/ssl/ was accepted by the LuCI validator and
 * then silently dropped here - certificate_path became null and the TLS
 * listener failed with no error pointing at the path.
 *
 * The list is mirrored by HP_CERT_PATH_ROOTS in
 * htdocs/luci-static/resources/homeproxy-pro.js; guard 29 in tests/arch-guard.sh
 * keeps the two in step.
 */
export const CERT_PATH_ROOTS = ['/etc/homeproxy-pro/certs/', '/etc/acme/', '/etc/ssl/'];

/* validateCertificatePath(p) - the TLS certificate/key path gate.
 *
 * Same shape as validateHomeProxyPath(): reject traversal and relative paths,
 * then require one of CERT_PATH_ROOTS. Kept separate rather than folded into
 * validateHomeProxyPath() so a rule-set path cannot be pointed at /etc/ssl/
 * and a certificate cannot be pointed at /tmp/homeproxy_*. */
export function validateCertificatePath(p) {
	if (!p || type(p) !== 'string')
		return false;

	if (match(p, /(^|\/)\.\.(\/|$)/))
		return false;

	if (substr(p, 0, 1) !== '/')
		return false;

	for (let root in CERT_PATH_ROOTS)
		if (length(p) > length(root) && substr(p, 0, length(root)) === root)
			return true;

	return false;
};

/* Rule-set source files: the `path` of a `type: local` rule_set and the
 * `initial_path` of a `type: remote` one.  sing-box opens both as root, so
 * the threat model is the certificate one - an arbitrary UCI value would leak
 * the file to anyone who can write the UCI tree from anywhere on the LAN.
 *
 * Unlike a certificate, a rule-set has exactly one home: the archive this
 * package creates at install time (uci-defaults/luci-homeproxy-pro) and before
 * every generation (runtime/service.sh's hp_prepare_ruleset_dir).  So the
 * policy is a single root rather than the three a certificate needs, and it
 * is deliberately NARROWER than validateHomeProxyPath() - that gate also
 * accepts /tmp/homeproxy_*, which exists for upload staging, and every path
 * under /etc/homeproxy-pro/ including the resource lists the package itself
 * rewrites.  A rule-set belongs in the archive (issue #7, review 4.4/4.7).
 *
 * Kept as a third policy rather than folded into validateHomeProxyPath() for
 * the reason validateCertificatePath() is: the policies have to be
 * independently narrowable, and folding them back together is exactly how the
 * certificate one regressed once already - a path the UI offered was accepted
 * there and silently dropped here, so the TLS listener failed with nothing
 * pointing at the path.
 *
 * The list is mirrored by HP_RULE_PATH_ROOTS in
 * htdocs/luci-static/resources/homeproxy-pro.js; guard 50 in tests/arch-guard.sh
 * keeps the two in step across the JS/ucode boundary, which nothing else can
 * see. */
export const RULE_PATH_ROOTS = ['/etc/homeproxy-pro/ruleset/'];

/* validateRuleSetPath(p) - the rule-set path gate.
 *
 * Same shape as validateCertificatePath(): reject traversal and relative
 * paths, then require one of RULE_PATH_ROOTS.  A bare root ("/etc/homeproxy-pro/
 * ruleset/" with nothing after it) is rejected - it names the directory, not
 * a file. */
export function validateRuleSetPath(p) {
	if (!p || type(p) !== 'string')
		return false;

	/* Reject traversal *before* the prefix checks: a plain prefix comparison
	 * accepts '/etc/homeproxy-pro/ruleset/../../etc/shadow', and sing-box reads
	 * these paths as root. */
	if (match(p, /(^|\/)\.\.(\/|$)/))
		return false;

	/* Reject anything that does not start with '/' - a relative path in
	 * sing-box resolves against the process CWD. */
	if (substr(p, 0, 1) !== '/')
		return false;

	for (let root in RULE_PATH_ROOTS)
		if (length(p) > length(root) && substr(p, 0, length(root)) === root)
			return true;

	return false;
};

/* RULE_PATH_ROOTS rendered for a diagnostic.
 *
 * join(', ', RULE_PATH_ROOTS) would do this in one line - it is the form
 * firewall_utils.uc uses for its own lists, and ucode's join() does flatten an
 * array argument rather than stringifying it.  The loop is kept anyway: it
 * cannot be wrong about the separator, and this string ends up inside a die()
 * a user reads in a log file. */
export function rulePathRootsText() {
	let text = '';

	for (let root in RULE_PATH_ROOTS)
		text = text ? (text + ', ' + root) : root;

	return text;
};

/* --- rule-set format probing ---------------------------------------------
 *
 * A rule-set comes in exactly two formats, and sing-box needs to be told
 * which one it is looking at:
 *
 *   source  a JSON document, {"version":3,"rules":[...]}
 *   binary  a compiled .srs, which starts with the three ASCII bytes "SRS"
 *
 * The field is optional, because sing-box infers it from the file extension
 * (.json -> source, .srs -> binary).  That inference is a guess about the
 * NAME, and it is wrong in three ways that all end the same way - `sing-box
 * check` rejects the whole configuration, so a reload is aborted and the user
 * is left with "my change did not take":
 *
 *   content disagrees with the name   example.srs holding JSON  -> the file
 *                                     is parsed as SRS and fails
 *   the field says the wrong thing    format=binary on a .json    -> same
 *   there is no name to infer from     a file with no extension   -> "missing
 *                                     format", a different error for the
 *                                     same underlying mistake
 *
 * So the correction is to look at the bytes.  The functions below are split
 * in two on purpose: ruleSetFormatFromBytes() is a pure function of what it
 * is handed, so the decision is unit-testable and auditable, and
 * probeRuleSetFile() is the only part that touches the disk.  It is called
 * from the CLI's resolve_env(), never from generator/ (guard 27), and its
 * verdict reaches the generator as an ordinary context field.
 *
 * Nothing here ever *guesses*: an unreadable, empty or unclassifiable file
 * yields no verdict at all, and the declared format is left exactly as the
 * user wrote it.  sing-box stays the authority, and auto-correction can
 * never become a second source of wrongness. */

/* How many leading bytes ruleSetFormatFromBytes() needs.  Three for the magic,
 * plus room to skip leading whitespace before the first JSON brace - a file
 * written by a text editor or a Windows tool routinely starts with "\r\n".
 * 512 is far more than the decision can use and far less than any real
 * rule-set, so reading it is one short read, not a load. */
export const RULESET_PROBE_BYTES = 512;

/* ruleSetFormatFromBytes(head, size) -> 'binary' | 'source' | null.
 *
 * `head` is the leading bytes as a string (ucode fs.read hands them over as
 * one), `size` the whole file's size.  Returns null when the bytes do not
 * identify a format - an empty file, or content that is neither SRS nor JSON
 * (a truncated download, an HTML error page served with a .srs name). */
export function ruleSetFormatFromBytes(head, size) {
	/* Empty is not "source" and not "binary": sing-box rejects a 0-byte
	 * local rule-set with "invalid sing-box rule-set file" whatever format
	 * is declared, so no verdict is the honest answer here and declaring one
	 * would not help. */
	if (!size || !head)
		return null;

	/* The SRS magic, compared byte by byte.
	 *
	 * isBinary() must NOT be reused here, and the reason is worth being exact
	 * about, because the obvious one is wrong: isBinary() does not say "not
	 * SRS", so it cannot be used as a negative test.  It answers a different
	 * question - "does this look like text?" - and for rule-sets that answer
	 * is only *correlated* with the format, never equal to it:
	 *
	 *   a full .srs happens to read as binary, because the version byte and
	 *   the deflate stream carry control bytes.  That is a property of this
	 *   week's encoder, not of the format, and it only holds because the
	 *   probe happens to read enough of the file;
	 *   a negative is ambiguous - binary-but-not-SRS, or text that is not
	 *   JSON - and those need different answers.
	 *
	 * The magic is the format's own identity, costs three bytes, and gives
	 * null for anything it does not recognise.  That last part is the point:
	 * this probe declines to have an opinion rather than guessing. */
	if (length(head) >= 3 &&
	    ord(head, 0) == 0x53 && ord(head, 1) == 0x52 && ord(head, 2) == 0x53)
		return 'binary';

	/* Source is JSON, so the first byte that is not whitespace decides.
	 * Both { (an object) and [ (an array) are accepted: sing-box's own
	 * source form is an object, but an array is still "this is JSON" and
	 * refusing to say so would only hand the decision back to a guess. */
	const lead = trim(head);
	if (length(lead) && (substr(lead, 0, 1) == '{' || substr(lead, 0, 1) == '['))
		return 'source';

	return null;
};

/* ruleSetFormatFromPath(path) -> 'binary' | 'source' | null.
 *
 * What sing-box's extension inference would decide for this name, expressed
 * as the same two values.  null means "no extension sing-box can infer from",
 * which is the case that produces "missing format" rather than a wrong parse -
 * and the reason a content probe is worth doing at all.
 *
 * Deliberately NOT a general extension parser: only the two suffixes sing-box
 * acts on are named, so this cannot drift into claiming it knows sing-box's
 * rules.  A {tag} placeholder does not affect the answer, since the suffix
 * comes after it. */
export function ruleSetFormatFromPath(path) {
	if (!path || type(path) !== 'string')
		return null;

	if (match(path, /\.json$/))
		return 'source';

	if (match(path, /\.srs$/))
		return 'binary';

	return null;
};


/* probeRuleSetFile(path) -> 'binary' | 'source' | null.
 *
 * The disk half.  Returns null - meaning "no opinion" - for a path outside the
 * rule-set policy, a missing/empty/non-regular file, an unreadable one, and
 * for content it cannot classify.  The policy check is not redundant with
 * ruleset.uc's: this runs BEFORE the generator, on paths that have not been
 * vetted yet, and it is a reader.
 *
 * lstat() rather than the two-argument access() - see the note in
 * generate_client.uc's china_ip6_ready about this ucode build answering only
 * in its one-argument form. */
export function probeRuleSetFile(path) {
	if (!validateRuleSetPath(path))
		return null;

	const st = lstat(path);
	if (!st || st.type !== 'file' || st.size <= 0)
		return null;

	const f = open(path);
	if (!f)
		return null;

	/* The `?? ''` is the same defensive read read_capped() uses: a short or
	 * failed read must not become a null the caller has to reason about. */
	const head = f.read(RULESET_PROBE_BYTES) ?? '';
	f.close();

	return ruleSetFormatFromBytes(head, st.size);
};

/* Read at most `limit` bytes from a file, or '' when it does not exist.
 * The cap is deliberate: a command's output is not trustworthy input. */
function read_capped(path, limit) {
	const f = open(path);

	if (!f)
		return '';

	const data = f.read(limit) ?? '';
	f.close();
	return data;
};

/* Remove the scratch files and the directory created for one run. Best
 * effort: a command the shell could not even parse leaves no files behind,
 * and a failed cleanup must never mask the command's own result. */
function cleanup_exec_dir(dir, outpath, errpath) {
	try {
		if (access(outpath))
			unlink(outpath);
		if (access(errpath))
			unlink(errpath);
		rmdir(dir);
	} catch (e) {
		/* nothing useful to do - the results are already captured */
	}
};

export function executeCommand(...args) {
	const command = join(' ', args);
	const dir = mkdtemp();
	const outpath = dir + '/stdout';
	const errpath = dir + '/stderr';

	let exitcode = null, stdout = '', stderr = '';

	try {
		/* Redirect to real paths, not to the descriptors of two mkstemp()
		 * files. The old form appended `>&N 2>&N`, which only works when
		 * the child shell can see those descriptors; /bin/sh reports
		 * "Bad file descriptor" (bash) / "Bad fd number" (dash) when it
		 * cannot, so the command was never executed and every caller got
		 * an empty result with exit status 2. That is what happened in
		 * CI, where /bin/sh is dash. Redirecting to paths is plain POSIX
		 * and behaves identically under busybox ash, dash and bash. */
		exitcode = system(sprintf('%s >%s 2>%s', command, outpath, errpath));

		/* The reader has to be able to return one byte more than
		 * HP_FETCH_CAP, or wGETVerbose()'s "response exceeds the limit"
		 * branch below is unreachable: the reader used to stop at 512 KiB,
		 * so every subscription between 512 KiB and 5 MiB was handed to the
		 * parser as a truncated body with error: null - the size check
		 * could never fire and the caller had no way to tell.  stderr keeps
		 * the smaller cap: it is a diagnostic message, not a payload. The
		 * stderr_truncated flag on the result tells the caller the cap
		 * actually fired, so a "reload exited with status N" line is not
		 * the only signal that something went wrong upstream. */
		stdout = read_capped(outpath, HP_FETCH_CAP + 1);
		stderr = read_capped(errpath, 1024 * 512);
	} catch (e) {
		/* Never leave the scratch directory behind on a failing run.
		 * ucode has no `finally` clause, so the exception is re-raised
		 * by hand. */
		cleanup_exec_dir(dir, outpath, errpath);

		die(e);
	}

	const binary = isBinary(stdout);

	/* Did stderr actually overflow the 512 KiB cap?  The temp file is
	 * unlinked right after this, so size is read while it still exists.
	 * lstat() returns null on missing files, so the .size fallback is
	 * defensive against an exception-driven early cleanup. */
	const stderr_size = (lstat(errpath) || {}).size || 0;
	const stderr_truncated = stderr_size > 1024 * 512;

	cleanup_exec_dir(dir, outpath, errpath);

	return {
		command,
		stdout: binary ? null : stdout,
		stderr,
		stderr_truncated,
		exitcode,
		binary
	};
};

export function getTime(epoch) {
	const local_time = localtime(epoch);
	return replace(replace(sprintf(
		'%d-%2d-%2d@%2d:%2d:%2d',
		local_time.year,
		local_time.mon,
		local_time.mday,
		local_time.hour,
		local_time.min,
		local_time.sec
	), ' ', '0'), '@', ' ');

};

/* Redact the credential-bearing parts of a URL before logging it. Any
 * subscription URL we ship into /var/run/homeproxy-pro/homeproxy-pro.log is
 * readable by anyone who can read /var/run/homeproxy-pro - including UCI
 * defaults that ship on the device and anyone with shell on the LAN.
 * (Confirmed on the device: the log is 0644.)
 *
 * Only the scheme, host and port are kept - enough to answer "which
 * provider/endpoint failed?". The userinfo, the path and the query string
 * all carry subscription tokens in practice: many providers hand out
 * `https://host:port/<user>/<token>` with no query string at all, which is
 * exactly what the device this was found on was configured with, and the
 * path used to survive the redaction. The original URL is still passed to
 * wGETVerbose.
 *
 *   https://user:token@host.example.com/path/sub?q=abc&token=secret
 *     -> https://***@host.example.com/***?*** */
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

/* Scan a free-form error string and redact every URL in it.  GNU wget's
 * stderr writes the requested URL back into the message:
 *
 *   https://host/path?q=token=secret: Bad port '80080'.
 *
 * The trailing `:` separator is greedy-matched here, which is harmless -
 * redactUrl leaves it as-is.  Doing this here, in wGETVerbose, means the
 * returned `error` is safe no matter where the caller ships it - the
 * fetcher logs it, the orchestrator returns it, anything that prints it
 * afterwards has already lost the token.  Centralising the redaction at
 * the source is the point: every call site used to have to
 * remember to redact, and the one that forgot was the original bug.
 *
 * A non-string input is returned unchanged so this is safe to apply to
 * the trimmed wget stderr even when it is empty.
 *
 * Both definitions sit above wGETVerbose on purpose: ucode does not hoist
 * `export function`, so a call compiled before the declaration is bound
 * fails at runtime with "access to undeclared variable". */
export function redactReason(reason) {
	if (!reason || type(reason) !== 'string')
		return reason;

	return replace(reason, /https?:\/\/\S+/g, (url) => redactUrl(url));
};

/*
 * Fetch a URL and report both the body and, on failure, the reason. The
 * reason is wget's own stderr (whitespace collapsed, length-capped) so the
 * caller can tell a DNS failure from a timeout or a TLS handshake error.
 */
/* fetchBinary() -> the path to invoke the fetch layer with.
 *
 * uclient-fetch is base OpenWrt, and it lives in /bin on every target measured
 * so far - but "base package" is a packaging fact, not a path guarantee, and
 * the whole point of the switch is not to hard-code an assumption that some
 * buildroot can violate.  So: the two known locations first, then PATH as the
 * fallback, which is also what makes the test suite able to shadow it with a
 * stub.
 *
 * Declared before wGETVerbose() on purpose - see the note above
 * redactReason() about ucode not hoisting exported functions. */
export function fetchBinary() {
	for (let p in [ '/bin/uclient-fetch', '/usr/bin/uclient-fetch' ]) {
		/* One-argument access() is the only form this ucode build answers;
		 * see the china_ip6_ready note in generate_client.uc. */
		if (access(p))
			return p;
	}

	return 'uclient-fetch';
};

export function wGETVerbose(url, ua) {
	if (!url || type(url) !== 'string')
		return { content: null, error: 'invalid URL' };

	if (!ua)
		ua = 'Wget/1.21 (HomeProxy, like v2rayN)';

	/* Why uclient-fetch and not wget: `wget` is whatever the firmware's
	 * buildroot happened to compile, and the two implementations do not share
	 * a single option beyond -O.  A command line that works on one of them
	 * exits 2 on the other with "unrecognized option" *before making a single
	 * request*, which is how every subscription fetch, every resource-list
	 * update and the connectivity check failed on a busybox-wget router while
	 * the suite stayed green - the guard below only ever ran against GNU
	 * wget, on CI and on the maintainer's own device.
	 *
	 * uclient-fetch is the fetcher OpenWrt itself ships and drives (opkg,
	 * sysupgrade, uci), with an option set fixed by the applet rather than by
	 * the buildroot, so one command line is correct on every target.  Its
	 * interface was read off the applet on the device, not from memory:
	 *
	 *   -O <file>            stdout is "-"
	 *   --user-agent <str>   -U
	 *   --timeout=N | -T N  seconds, same unit as the --timeout= it replaces
	 *   --spider | -s       existence check only
	 *   --header='K: V'     note the '=': the space-separated form is not
	 *                       accepted, and the value is ONE argv element
	 *
	 * No --quiet, deliberately: the point of capturing stderr is to report
	 * *why* a fetch failed, and uclient-fetch's default stderr is better than
	 * wget's -nv was - on an HTTP error it prints
	 *
	 *   Downloading 'https://…/x.srs?token=…'
	 *   Connecting to 185.199.111.133:443
	 *   HTTP error 404
	 *
	 * including the resolved address.  The URL is in there, so this depends on
	 * redactReason() below; guard 14 is what keeps that honest.  Quiet mode
	 * would have removed the URL from the message and, with it, the only
	 * thing distinguishing an HTTP 404 from a connect failure.
	 *
	 * The size cap is still enforced by piping through `head -c`, not by a
	 * fetcher option: there is no such option in either implementation, and
	 * `head` closing the pipe stops the download early.  The cap is therefore
	 * CAP+1 bytes rather than exactly CAP, and one byte past the limit means
	 * "too large".
	 *
	 * 5 MiB covers a 10 000-node subscription with ~3 KB per node plus the
	 * base64 inflation. Anything larger is almost certainly an attack or a
	 * misconfiguration.
	 *
	 * The pipeline does cost the exit status: `system()` returns head's, which
	 * is always 0. A fetch failure therefore arrives as an empty body plus the
	 * fetcher's own message on stderr, and that is reported below. */
	/* The braces matter: executeCommand() appends `>out 2>err` to the command,
	 * and in `a | b >out 2>err` those redirections bind to b only - the
	 * fetcher's stderr would go to the caller's terminal and the failure
	 * message would be lost.  Grouping the pipeline makes both stream to the
	 * capture files.
	 *
	 * fetchBinary() is shellQuote()d like everything else here rather than
	 * being waved through on the grounds that it only ever returns a literal:
	 * guard 25 exists to make "is this shell-safe" a mechanical check instead
	 * of a judgement call, and a quoted constant costs nothing. */
	const output = executeCommand(`{ ${shellQuote(fetchBinary())} -O - --user-agent=${shellQuote(ua)} --timeout=10 ${shellQuote(url)} | head -c ${HP_FETCH_CAP + 1}; }`) || {};
	let reason = trim(output.stderr || '');
	reason = reason ? replace(reason, /\s+/g, ' ') : '';
	/* An HTTP-level failure prints the requested URL back into the message
	 * with its query string and subscription token attached, as in
	 * `Downloading 'https://host/path?token=secret'` + `HTTP error 404`.
	 *  (A pure connection failure prints only `Failed to send request: …` and
	 * leaks nothing, but the 404/403 case is enough.)  Redact at the source
	 * so every caller of wGETVerbose gets a safe `error` whether or not it
	 * remembers to call redactUrl itself. */
	if (reason)
		reason = redactReason(reason);

	if (length(output.stdout || '') > HP_FETCH_CAP)
		return { content: null, error: `response exceeds the ${HP_FETCH_CAP} byte limit` };

	if (output.exitcode !== 0) {
		if (length(reason) > 200)
			reason = substr(reason, 0, 200) + '...';

		return { content: null, error: `fetch exited with status ${output.exitcode}: ${reason || 'no error output'}` };
	}

	/* A binary body is not a failed fetch.
	 *
	 * executeCommand() nulls stdout for binary content - a subscription body
	 * that is not text cannot be parsed by anything downstream - and without
	 * this branch the "no content, but stderr said something" test below
	 * reported the result as
	 *
	 *   fetch failed: Downloading '…' … Download completed (34185 bytes)
	 *
	 * which contradicts itself, and which would send a user looking for a
	 * network problem they do not have.  Measured on a device, with a real
	 * .srs fetched from a URL that answered 200. */
	if (output.binary)
		return { content: null, error: 'the fetch succeeded but the response is binary, not a subscription payload' };

	/* head() masks the fetcher's status, so a failed fetch shows up here. */
	if (!length(trim(output.stdout)) && reason) {
		if (length(reason) > 200)
			reason = substr(reason, 0, 200) + '...';

		return { content: null, error: `fetch failed: ${reason}` };
	}

	return { content: trim(output.stdout), error: null };
};

/* Utilities end */

/* String helper start */
export function isEmpty(res) {
	return !res || res === 'nil' || (type(res) in ['array', 'object'] && length(res) === 0);
};

export function strToBool(str) {
	return str === '1' ? true : (str === '0' ? false : null);
};

export function strToInt(str) {
	/* Zero reads back as "not set" on purpose: several sing-box fields mean
	 * "omit me" at zero - a vmess user's alterId, for instance - and the
	 * generators depend on removeBlankAttrs() dropping the null this produces.
	 * A review flagged it as "a legitimate 0 becomes null"; the golden outbound
	 * snapshot and the vmess alterId assertion both say otherwise. */
	return !isEmpty(str) ? (int(str) || null) : null;
};

export function strToTime(str) {
	if (isEmpty(str))
		return null;

	/* Preserve values that already carry a time unit (e.g. "30s", "1m") */
	return match(str, /[a-zA-Z]$/) ? str : (str + 's');
};

/* Turn a UCI list of port strings into the int array sing-box wants
 * (e.g. the WireGuard `reserved` list, a routing rule's `port` /
 * `source_port`). Returns null for anything that is not a non-empty
 * array, so a caller can let removeBlankAttrs() drop the field.
 *
 * Lives here rather than in generator/common.uc because the Adapter
 * layer needs it too (EndpointFactory builds the WireGuard endpoint)
 * and an adapter must not import from generator/. */
export function parse_port(strport) {
	if (type(strport) !== 'array' || isEmpty(strport))
		return null;

	let ports = [];
	for (let i in strport) {
		/* Only a bare decimal is a port: int() truncates, so '80-90' used to
		 * become 80 and '443/tcp' become 443, silently widening the rule
		 * instead of dropping the malformed entry. */
		if (match(i, /^[0-9]+$/) && int(i) >= 1 && int(i) <= 65535)
			push(ports, int(i));
	}

	return ports;
};

export function removeBlankAttrs(res) {
	let content;

	if (type(res) === 'object') {
		content = {};
		map(keys(res), (k) => {
			if (type(res[k]) in ['array', 'object'])
				content[k] = removeBlankAttrs(res[k]);
			else if (res[k] !== null && res[k] !== '')
				content[k] = res[k];
		});
	} else if (type(res) === 'array') {
		content = [];
		map(res, (k, i) => {
			if (type(k) in ['array', 'object'])
				push(content, removeBlankAttrs(k));
			else if (k !== null && k !== '')
				push(content, k);
		});
	} else
		return res;

	return content;
};

export function validation(datatype, data) {
	if (!datatype || !data)
		return null;

	const ret = system(`/sbin/validate_data ${shellQuote(datatype)} ${shellQuote(data)} 2>/dev/null`);
	return (ret === 0);
};

/* Validate IP/CIDR format to prevent nftables template injection from resource files */
export function isValidCIDR(addr, family) {
	if (isEmpty(addr))
		return false;

	/* Strip leading/trailing whitespace */
	addr = trim(addr);
	if (!addr)
		return false;

	/* Split address and optional prefix. Reject a second '/' outright:
	 * the only legal form is "ip" or "ip/prefix", and a resource-list
	 * entry like "1.2.3.4/24/32" or "1.2.3.4/;}" would otherwise split
	 * into a benign-looking ip and a prefix the next checks would then
	 * have to defend.  Drop it here so all the following regexes only have
	 * to police a one-or-zero-slash input. */
	const parts = split(addr, '/');
	if (length(parts) > 2)
		return false;
	const ip = parts[0];
	const prefix = parts[1];

	/* Validate IP part */
	if (family === 4) {
		if (!match(ip, /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/))
			return false;
		/* Validate octet ranges */
		const octets = split(ip, '.');
		for (let o in octets)
			if (int(o) > 255)
				return false;
		/* Validate prefix if present.  Anchor with a digit-only regex:
		 * without it, `int(prefix)` happily parses `24;}` as 24 (strtoll
		 * stops at the first non-digit), so a poisoned china_ip4.txt line
		 * `1.2.3.4/24;}` sailed past this check and ended up verbatim
		 * in the fw4 ruleset fw4 then loaded as root.
		 *
		 * ucode has no `undefined` (an absent index reads as null), and
		 * `if (prefix)` is also false for the empty string, so a
		 * trailing-slash entry like `1.2.3.4/` would slip past a plain
		 * `if (prefix)` gate and pass overall.  Gate on null, which
		 * keeps `''` from sneaking in; the regex naturally rejects the
		 * empty string and any non-digit. */
		if (prefix !== null) {
			if (!match(prefix, /^\d{1,3}$/) || int(prefix) > 32)
				return false;
		}
	} else if (family === 6) {
		/* Only hex digits and colons */
		if (!match(ip, /^[0-9a-fA-F:]+$/))
			return false;

		/* At most one "::" */
		if (match(ip, /::.*::/))
			return false;

		/* Validate group structure */
		const dcolon = index(ip, '::');
		if (dcolon === -1) {
			/* Uncompressed form: exactly 8 groups of 1-4 hex digits */
			const groups = split(ip, ':');
			if (length(groups) !== 8)
				return false;
			for (let g in groups)
				if (!match(g, /^[0-9a-fA-F]{1,4}$/))
					return false;
		} else {
			/* Compressed form: "::" expands to at least one zero group */
			let count = 0;
			for (let part in [substr(ip, 0, dcolon), substr(ip, dcolon + 2)]) {
				if (part === '')
					continue;
				for (let g in split(part, ':')) {
					if (!match(g, /^[0-9a-fA-F]{1,4}$/))
						return false;
					count++;
				}
			}
			if (count > 7)
				return false;
		}

		/* Same anchor as the IPv4 branch: `1.2.3.4/24;}` would let
		 * `int('24;}')` slip through unanchored and end up in fw4.  Same
		 * null-presence guard for `::1/` (empty prefix). */
		if (prefix !== null) {
			if (!match(prefix, /^\d{1,3}$/) || int(prefix) > 128)
				return false;
		}
	} else {
		return false;
	}

	return true;
};
/* String helper end */

/* String parser start */
export function decodeBase64Str(str) {
	if (isEmpty(str))
		return null;

	str = trim(str);
	str = replace(str, /_/g, '/');
	str = replace(str, /-/g, '+');

	const padding = length(str) % 4;
	if (padding)
		str = str + substr('====', padding);

	return b64dec(str);
};

export function parseURL(url) {
	if (type(url) !== 'string')
		return null;

	const services = {
		http: '80',
		https: '443'
	};

	const objurl = {};

	objurl.href = url;

	url = replace(url, /#(.+)$/, (_, val) => {
		objurl.hash = val;
		return '';
	});

	url = replace(url, /^(\w[A-Za-z0-9\+\-\.]+):/, (_, val) => {
		objurl.protocol = val;
		return '';
	});

	url = replace(url, /\?(.+)/, (_, val) => {
		objurl.search = val;
		objurl.searchParams = urldecode_params(val);
		return '';
	});

	url = replace(url, /^\/\/([^\/]+)/, (_, val) => {
		val = replace(val, /^([^@]+)@/, (_, val) => {
			objurl.userinfo = val;
			return '';
		});

		val = replace(val, /:(\d+)$/, (_, val) => {
			objurl.port = val;
			return '';
		});

		if (validation('ip4addr', val) ||
		    validation('ip6addr', replace(val, /\[|\]/g, '')) ||
		    validation('hostname', val))
			objurl.hostname = val;

		return '';
	});

	objurl.pathname = url || '/';

	if (!objurl.protocol || !objurl.hostname)
		return null;

	if (objurl.userinfo) {
		objurl.userinfo = replace(objurl.userinfo, /:(.+)$/, (_, val) => {
			objurl.password = val;
			return '';
		});

		if (match(objurl.userinfo, /^[A-Za-z0-9\+\-\_\.]+$/)) {
			objurl.username = objurl.userinfo;
			delete objurl.userinfo;
		} else {
			delete objurl.userinfo;
			delete objurl.password;
		}
	};

	if (!objurl.port)
		objurl.port = services[objurl.protocol];

	objurl.host = objurl.hostname + (objurl.port ? `:${objurl.port}` : '');
	objurl.origin = `${objurl.protocol}://${objurl.host}`;

	return objurl;
};
/* String parser end */

/* Config generator helper start */
/*
 * Shared sing-box TLS object builder for the client outbound and the server
 * inbound. The property order below is significant: the generated JSON keeps
 * the insertion order of this object after removeBlankAttrs() drops the blank
 * attributes, and both generators used to emit the fields in exactly this
 * order. Keep client-only fields (insecure/handshake_timeout/utls) and
 * server-only fields (key_path/certificate_provider) at their current
 * positions when editing.
 *
 * P1-B: the first arg is now a Node.tls-shape structured sub-object
 * (the same shape the Loader produces) rather than a flat UCI section.
 * The Adapter passes node.tls; the server generator builds a
 * structured view of its UCI inbound before calling. Server-only
 * fields (key material, ACME, server-side reality handshake) still
 * live on the flat UCI section - they are not part of the Node model
 * because no client outbound needs them - so the server passes them
 * through `server_extras` instead of expecting the structured tls
 * to carry them.
 */
export function buildTLSObject(tls, is_server, server_extras) {
	if ((tls && tls.enabled) !== '1')
		return null;

	/* When is_server the caller hands a flat UCI section's server-only
	 * tail. We accept either an object or null; null means "no server
	 * extras" which only matters when the caller still wants a TLS
	 * object built for an inbound that does not actually serve TLS
	 * itself (the enabled check above returns null first in that case). */
	const extras = is_server ? (server_extras || {}) : {};

	return {
		enabled: true,
		server_name: tls.server_name,
		insecure: is_server ? null : strToBool(tls.insecure),
		alpn: tls.alpn,
		min_version: tls.min_version,
		max_version: tls.max_version,
		handshake_timeout: is_server ? null : strToTime(tls.handshake_timeout),
		cipher_suites: tls.cipher_suites,
		certificate_path: tls.cert_path && validateCertificatePath(tls.cert_path) ? tls.cert_path : null,
		key_path: (is_server && extras.tls_key_path && validateCertificatePath(extras.tls_key_path)) ? extras.tls_key_path : null,
		certificate_provider: (is_server && extras.tls_acme === '1') ? {
			type: 'acme',
			domain: (type(extras.tls_acme_domain) === 'array') ? extras.tls_acme_domain
				: (isEmpty(extras.tls_acme_domain) ? [] : [extras.tls_acme_domain]),
			data_directory: HP_DIR + '/certs',
			default_server_name: extras.tls_acme_dsn,
			email: extras.tls_acme_email,
			provider: extras.tls_acme_provider,
			account_key: extras.tls_acme_account_key,
			key_type: extras.tls_acme_key_type,
			profile: extras.tls_acme_profile,
			disable_http_challenge: strToBool(extras.tls_acme_dhc),
			disable_tls_alpn_challenge: strToBool(extras.tls_acme_dtac),
			alternative_http_port: strToInt(extras.tls_acme_ahp),
			alternative_tls_port: strToInt(extras.tls_acme_atp),
			external_account: (extras.tls_acme_external_account === '1') ? {
				key_id: extras.tls_acme_ea_keyid,
				mac_key: extras.tls_acme_ea_mackey
			} : null,
			dns01_challenge: (extras.tls_dns01_challenge === '1') ? {
				provider: extras.tls_dns01_provider,
				access_key_id: extras.tls_dns01_ali_akid,
				access_key_secret: extras.tls_dns01_ali_aksec,
				region_id: extras.tls_dns01_ali_rid,
				api_token: extras.tls_dns01_cf_api_token
			} : null
		} : null,
		ech: is_server ? (extras.tls_ech_key ? {
			enabled: true,
			key: split(extras.tls_ech_key, '\n')
			/* config: split(extras.tls_ech_config, '\n') */
		} : null) : ((tls.ech && tls.ech.enabled === '1') ? {
			enabled: true,
			config: tls.ech.config,
			/* Same gate as certificate_path: this is a file sing-box opens as
			 * root, and it used to reach the config unvalidated. */
			config_path: tls.ech.config_path && validateCertificatePath(tls.ech.config_path) ? tls.ech.config_path : null
		} : null),
		utls: (is_server || isEmpty(tls.utls && tls.utls.fingerprint)) ? null : {
			enabled: true,
			fingerprint: tls.utls.fingerprint
		},
		reality: ((tls.reality && tls.reality.enabled) !== '1') ? null : (is_server ? {
			enabled: true,
			private_key: extras.tls_reality_private_key,
			short_id: tls.reality.short_id,
			max_time_difference: strToTime(extras.tls_reality_max_time_difference),
			handshake: {
				server: extras.tls_reality_server_addr,
				server_port: strToInt(extras.tls_reality_server_port)
			}
		} : {
			enabled: true,
			public_key: tls.reality.public_key,
			short_id: tls.reality.short_id
		})
	};
};

/* Shared sing-box transport object builder; the client transport additionally
   supports the gRPC keepalive hint, the server one does not.
   P1-B: the first arg is now a Node.transport-shape structured sub-object. */
export function buildTransportObject(transport, is_server) {
	if (isEmpty(transport && transport.type))
		return null;

	return {
		type: transport.type,
		host: transport.host,
		path: transport.path,
		headers: transport.headers,
		method: transport.method,
		max_early_data: strToInt(transport.max_early_data),
		early_data_header_name: transport.early_data_header_name,
		service_name: transport.service_name,
		idle_timeout: strToTime(transport.idle_timeout),
		ping_timeout: strToTime(transport.ping_timeout),
		permit_without_stream: is_server ? null : strToBool(transport.permit_without_stream)
	};
};
/* Config generator helper end */

/* PEM validation start */
/*
 * Check that `content` is a PEM certificate (is_private_key = false) or an
 * RSA/EC private key (is_private_key = true): matching BEGIN/END boundaries
 * with a base64 body in between. Kanged from luci-proto-openconnect; used by
 * the rpcd certificate upload and available for future certificate features.
 */
/* Shared by the certificate, private-key and ECH-config validators: only the
 * markers differ, the body rule does not (base64 lines - or a single 64
 * character line - between a BEGIN and an END marker). */
function validatePEM(content, beg, end) {
	if (isEmpty(content))
		return false;

	const lines = split(trim(content), /[\r\n]/);
	let start = false, i;

	for (i = 0; i < length(lines); i++) {
		if (match(lines[i], beg))
			start = true;
		else if (start && !b64dec(lines[i]) && length(lines[i]) !== 64)
			break;
	}

	if (!start || i < length(lines) - 1 || !match(lines[i], end))
		return false;

	return true;
};

export function isValidPEM(content, is_private_key) {
	const beg = is_private_key ? /^-----BEGIN (RSA|EC) PRIVATE KEY-----$/ : /^-----BEGIN CERTIFICATE-----$/,
	      end = is_private_key ? /^-----END (RSA|EC) PRIVATE KEY-----$/ : /^-----END CERTIFICATE-----$/;

	return validatePEM(content, beg, end);
};

/* A client ECH config list is neither a certificate nor a private key - it is
 * wrapped in its own markers ("-----BEGIN ECH CONFIGS-----"), so isValidPEM()
 * rejects it.  The node form's "Upload ECH config" button has always sent
 * certificate_write('client_ech_conf'); the backend had no case for that name,
 * and would have rejected the body here even with one. */
export function isValidECHConfig(content) {
	return validatePEM(content,
		/^-----BEGIN ECH CONFIGS-----$/,
		/^-----END ECH CONFIGS-----$/);
};
/* PEM validation end */
