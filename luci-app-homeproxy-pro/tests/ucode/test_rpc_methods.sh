#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Behaviour tests for the rpcd module (root/usr/share/rpcd/ucode/luci.homeproxy-pro).
#
# Until now that file was only ever compiled for syntax. tests/ucode/run.sh
# rewrites its absolute imports and runs `ucode -c`, and nothing called a single
# one of its ten methods - which is why the "Upload ECH config" button could
# stay 100% broken: the frontend has called
# certificate_write('client_ech_conf') since the initial commit, the ACL
# granted the write, and the backend simply had no case for that name.
#
# This drives the methods directly with a fake request, the same way
# tests/frontend-validators.js drives the frontend's validate callbacks.
#
# Usage: sh tests/ucode/test_rpc_methods.sh <repo-root> [workdir]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
WORK="${2:-/tmp/hp-rpc-methods}"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi

rm -rf "$WORK"
mkdir -p "$WORK/scripts"
cp -R "$ROOT/root/etc/homeproxy-pro/scripts/." "$WORK/scripts/"

# stage_rewrite <src> <dst>: point a file's absolute /etc/homeproxy-pro paths at the
# sandbox, and nothing else.  Both the imports and the runtime directories have
# to move, or the test would write real certificates into /etc/homeproxy-pro/certs.
# The certificate staging prefix is moved too (it is a literal /tmp path inside
# luci.homeproxy-pro): the driver then writes and checks the staged upload under
# $WORK/tmp, so the test never touches a fixed global path and two concurrent
# runs cannot delete each other's upload between the stage and the call.
stage_rewrite() {
	sed -e "s#/etc/homeproxy-pro/scripts/#$WORK/scripts/#g" \
	    -e "s#^const HP_DIR = '/etc/homeproxy-pro';#const HP_DIR = '$WORK';#" \
	    -e "s#^export const HP_DIR = '/etc/homeproxy-pro';#export const HP_DIR = '$WORK';#" \
	    -e "s#^const RUN_DIR = '/var/run/homeproxy-pro';#const RUN_DIR = '$WORK/run';#" \
	    -e "s#^export const RUN_DIR = '/var/run/homeproxy-pro';#export const RUN_DIR = '$WORK/run';#" \
	    -e "s#^export const UCICONFIG_DIR = '/etc/config';#export const UCICONFIG_DIR = '$WORK/cfg';#" \
	    -e "s#/tmp/homeproxy_cert_#$WORK/tmp/homeproxy_cert_#g" \
	    "$1" > "$2"
}

stage_rewrite "$WORK/scripts/homeproxy-pro.uc" "$WORK/scripts/homeproxy-pro.uc.new"
mv -f "$WORK/scripts/homeproxy-pro.uc.new" "$WORK/scripts/homeproxy-pro.uc"
stage_rewrite "$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy-pro" "$WORK/rpc.uc"

# update_subscriptions.call() execs the staged updater through /bin/sh, so its
# shebang has to name the ucode that is running this test. On a target that is
# /usr/bin/ucode and nothing needs rewriting; on the off-target testbed the
# toolchain is built into a private prefix (tests/toolchain/build-ucode-*.sh)
# by design, and CI has nothing at /usr/bin/ucode at all - the first version of
# this test came back as "not found" (exit 127) there and passed on the device,
# which is the kind of environment dependence the staging is supposed to
# remove. The rewrite is asserted, not assumed.
UCODE_BIN="$(command -v ucode)"
if [ "$UCODE_BIN" != "/usr/bin/ucode" ]; then
	# `|` as the delimiter, not `#`: the pattern and the replacement both
	# contain `#!`, and busybox sed rejects the escaped form ("bad option in
	# substitution expression") while GNU sed accepts it.
	sed -e "1s|^#!/usr/bin/ucode\$|#!$UCODE_BIN|" \
	    "$WORK/scripts/update_subscriptions.uc" > "$WORK/scripts/update_subscriptions.uc.new"
	mv -f "$WORK/scripts/update_subscriptions.uc.new" "$WORK/scripts/update_subscriptions.uc"
	if ! head -n 1 "$WORK/scripts/update_subscriptions.uc" | grep -qxF "#!$UCODE_BIN"; then
		echo "FAIL: could not point the staged updater's shebang at $UCODE_BIN"
		head -n 1 "$WORK/scripts/update_subscriptions.uc"
		exit 1
	fi
fi
# After the rewrite, not before: the sed above creates the new file with the
# default umask, so a chmod applied to the original would be lost with the mv
# and /bin/sh would refuse to exec it (exit 126).
chmod +x "$WORK/scripts/update_subscriptions.uc"

mkdir -p "$WORK/certs" "$WORK/run" "$WORK/cfg" "$WORK/tmp"

cat > "$WORK/driver_body.uc" <<'DRIVER'
/* Appended to a copy of the module, so this runs in the module's own scope and
 * drives its `methods` table exactly as rpcd would hand it to a request. */
/* writefile/readfile/access come from the module's own `fs` import above;
 * only what is not already in scope is imported here. */
const WORK = '@@WORK@@';
const rpc = methods;

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	printf('FAIL %s%s\n', what, detail != null ? ': ' + detail : '');
}

const CERT = '-----BEGIN CERTIFICATE-----\n' +
	'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' +
	'-----END CERTIFICATE-----\n';
const KEY = '-----BEGIN RSA PRIVATE KEY-----\n' +
	'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' +
	'-----END RSA PRIVATE KEY-----\n';
const ECH = '-----BEGIN ECH CONFIGS-----\n' +
	'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' +
	'-----END ECH CONFIGS-----\n';

/* The upload path is what the frontend's ui.uploadFile writes and what the
 * module reads.  The staged module's /tmp/homeproxy_cert_ prefix is rewritten
 * to this run's work dir, so stage() and the module agree without either
 * touching a fixed /tmp path. */
const STAGE_DIR = '@@STAGE@@';
function stage(filename, content) {
	writefile(sprintf('%s/homeproxy_cert_%s.tmp', STAGE_DIR, filename), content);
}

function tmp_exists(filename) {
	return access(sprintf('%s/homeproxy_cert_%s.tmp', STAGE_DIR, filename));
}

function call(filename) {
	return rpc.certificate_write.call({ args: { filename: filename } });
}

/* --- the four names the frontend actually sends ------------------------- */

const names = ['client_ca', 'server_publickey', 'server_privatekey', 'client_ech_conf'];
const bodies = [CERT, CERT, KEY, ECH];

for (let i = 0; i < length(names); i++) {
	const name = names[i];
	stage(name, bodies[i]);
	const ret = call(name);

	check(sprintf('%s: accepted', name), ret && ret.result === true,
		ret && (ret.error || sprintf('result=%J', ret.result)));

	if (ret && ret.result === true) {
		const stored = readfile(sprintf('%s/certs/%s.pem', WORK, name));
		check(sprintf('%s: stored with a trailing newline', name),
			stored != null && match(stored, /\n$/));
		check(sprintf('%s: staging file removed after success', name), !tmp_exists(name));
	}
}

/* --- the type checks still hold ----------------------------------------- */

stage('client_ca', KEY);
check('client_ca rejects a private key', call('client_ca').result === false);

stage('server_privatekey', CERT);
check('server_privatekey rejects a certificate', call('server_privatekey').result === false);

/* An ECH config is not a certificate: it has its own PEM markers, so the
 * certificate validator must not be reused for it. */
stage('client_ech_conf', CERT);
check('client_ech_conf rejects a certificate body', call('client_ech_conf').result === false);

stage('client_ech_conf', 'not a pem at all');
check('client_ech_conf rejects garbage', call('client_ech_conf').result === false);

/* --- unknown names and empty uploads ------------------------------------ */

stage('client_ca', CERT);
const bogus = call('not_a_certificate');
check('an unknown filename is refused', bogus.result === false);
check('an unknown filename says why', bogus.error === 'illegal cerificate filename',
	bogus.error);

writefile(sprintf('%s/homeproxy_cert_client_ca.tmp', STAGE_DIR), '');
check('an empty upload is refused', call('client_ca').error === 'empty certificate file');

system(sprintf('rm -f %s/homeproxy_cert_client_ca.tmp', STAGE_DIR));
check('a missing upload is refused', call('client_ca').result === false);

/* No method may throw on a request with no arguments at all. */
let threw = null;
try { rpc.certificate_write.call({}); } catch (e) { threw = sprintf('%s: %s', e.type, e.message); }
check('certificate_write tolerates an empty request', threw == null, threw);

/* update_subscriptions is async: the LuCI button used to block inside one
 * XHR for the whole 5-15 s pipeline (wget + UCI commit + reload + health
 * gate), which exceeded the browser XHR timeout on every browser we tried.
 * The ubus method now spawns the script detached and returns immediately.
 * What the test asserts is exactly the contract the frontend relies on:
 * the call returns synchronously (without the script's exit status), the
 * result flag says the script was started, and async:true tells the
 * caller "don't wait, poll status instead".
 *
 * Asserting the lock file is present at the same instant is racy in this
 * sandbox: the early-exit path (no subscription_url) runs the whole
 * take-lock / load-state / release-lock sequence in microseconds, so the
 * lock may already be gone by the time this script runs an `access()` on
 * it. Polling the status RPC instead would be timing-dependent in the
 * same way. The contract is the return shape; that is what we pin. */
{
	const ret = rpc.update_subscriptions.call({ args: {} });
	check('update_subscriptions returns an object', type(ret) === 'object');
	check('update_subscriptions marks the call as async',
		ret.async === true,
		sprintf('got %J', ret));
	check('update_subscriptions does not surface exit status or captured stdio',
		ret.exitcode === null && !(('stdout' in ret) || ('stderr' in ret)),
		sprintf('got %J', ret));

	/* The companion update_subscriptions_status RPC reads the lock + the
	 * last log lines. What we pin here is the *shape* of the response:
	 * `running` is a boolean, `log_tail` is a string. A real
	 * running/false toggle only matters when there is a live lock file,
	 * which the sandbox cannot keep around long enough to observe
	 * deterministically. */
	const sret = rpc.update_subscriptions_status.call({ args: {} });
	check('update_subscriptions_status returns an object', type(sret) === 'object');
	check('update_subscriptions_status.running is a bool',
		type(sret.running) === 'bool',
		sprintf('got %J', sret));
	check('update_subscriptions_status.log_tail is a string',
		type(sret.log_tail) === 'string',
		sprintf('got %J', sret));
}

/* Every method rpcd exposes, so none can be shipped without ever having been
 * executed.  Four of these were referenced by no test at all. */
const all_methods = [
	'acllist_read', 'acllist_write', 'certificate_write', 'connection_check',
	'debug_report', 'log_clean', 'node_parse', 'resources_get_version',
	'resources_update', 'singbox_generator', 'singbox_get_features',
	'update_subscriptions', 'update_subscriptions_status'
];

for (let m in all_methods) {
	check(sprintf('%s is exposed with a call()', m),
		type(rpc[m]) === 'object' && type(rpc[m].call) === 'function');

	let t = null, ret = null;
	try { ret = rpc[m].call({ args: {} }); } catch (e) { t = sprintf('%s: %s', e.type, e.message); }
	check(sprintf('%s tolerates an empty request', m), t == null, t);
	check(sprintf('%s answers with an object', m), ret == null || type(ret) === 'object',
		sprintf('got %J', ret));
}

/* The argument validators must reject, not act on, an unknown value. */
check('acllist_read rejects an unknown list type',
	rpc.acllist_read.call({ args: { type: 'not_a_list' } }).result === false ||
	rpc.acllist_read.call({ args: { type: 'not_a_list' } }).error != null);
check('connection_check rejects an unknown site',
	rpc.connection_check.call({ args: { site: 'not_a_site' } }).result === false);
check('log_clean rejects an unknown log type',
	rpc.log_clean.call({ args: { type: '../etc/passwd' } }).status !== 0);

/* --- debug_report -------------------------------------------------------
 *
 * This one is worth more than a shape check, because the property that
 * makes it usable is the opposite of "works on my router": it has to
 * produce a complete, readable report on a machine that has none of the
 * runtime - no nft, no sing-box, no apk, no /etc/config/homeproxy-pro.  That is
 * exactly this test host, so a regression that turns a failed probe into an
 * exception, or drops a section when its command is missing, fails here
 * rather than on a user's router where the report is the thing they are
 * relying on. */
import { isSecretKey } from '@@SCRIPTS@@/runtime/debug_report.uc';

const dr = rpc.debug_report.call({ args: {} });
check('debug_report succeeds where no runtime is installed', dr.result === true,
	dr.error);
check('debug_report names the file it wrote', type(dr.path) === 'string' && length(dr.path) > 0);
check('debug_report reports a non-zero size', dr.size > 0);

const dr_text = readfile(sprintf('%s/run/debug.log', WORK));
check('the report was written where the ACL grants read', dr_text != null && length(dr_text) > 0);

if (dr_text != null && length(dr_text) > 0) {
	check('the report carries a title', index(dr_text, '# HomeProxy ') != -1);
	check('the report carries a privacy notice', index(dr_text, '脱敏') != -1);

	/* Every section header, checked as a literal substring rather than a
	 * regex: the headers carry CJK and full-width brackets, and a probe that
	 * throws would take the whole report down rather than leave one section
	 * missing - so "the section is still there" is the property worth pinning. */
	for (let h in ['## 1. ', '## 2. ', '## 3. ', '## 4. ', '## 5. ',
	               '## 6. ', '## 7. ', '## 8. ', '## 9. ', '## 10. '])
		check(sprintf('the report still has section %s', h), index(dr_text, h) != -1);

	/* A missing command must be said out loud.  A report that silently omits
	 * the firewall dump reads exactly like "the firewall is empty", which is
	 * the opposite of what happened. */
	check('an unavailable probe is labelled, not omitted',
		index(dr_text, 'unavailable') != -1 || index(dr_text, '(no output)') != -1);
}

/* The redaction rule has no I/O to observe, so it is asserted directly: a
 * key that quietly stops being recognised is a credential in an issue
 * thread, and nothing else in this suite would notice. */
for (let k in ['password', 'uuid', 'secret', 'token', 'private_key', 'url',
               'urls', 'subscription_urls', 'address', 'tls_sni', 'username',
               'hysteria_obfs_password', 'tls_reality_public_key',
               'tls_reality_short_id', 'ws_path', 'hysteria_obfs_method',
'auth'])
	check(sprintf('the key %s is redacted', k), isSecretKey(k));

/* ...and the other direction matters just as much: over-broad matching
 * would blank out the very switches the report exists to show. */
for (let k in ['proxy_mode', 'routing_mode', 'mixed_port', 'redirect_port',
               'self_mark', 'tproxy_mark', 'log_level', 'ipv6_support',
               'enabled', 'grouphash'])
	check(sprintf('the key %s is left readable', k), !isSecretKey(k));

/* The urltest lists are the reason `url` is anchored rather than a bare
 * substring: `main_urltest_nodes` contains the letters u-r-l, so an
 * unanchored pattern blanked the pool out of the report - and "is this node
 * still in the test pool" is exactly what the report is read for.  These
 * three were found by a canary run, not by inspection. */
for (let k in ['main_urltest_nodes', 'main_urltest_tolerance',
               'main_udp_urltest_nodes'])
	check(sprintf('the key %s is left readable (urltest, not url)', k), !isSecretKey(k));

/* grpc_servicename names the gRPC service, it is not a credential: masking
	* it would hide which transport a node uses, which is worth reporting.
	* Asserted on the readable side because the obvious guess is that anything
	* shaped like a service identifier should be hidden. */
	check('the key grpc_servicename is left readable', !isSecretKey('grpc_servicename'));

printf('rpc methods: %d checks, %d failures\n', checks, failures);
exit(failures ? 1 : 0);
DRIVER

# The module ends with `return { 'luci.homeproxy-pro': methods };`, which makes it a
# program rather than an importable module - that is how rpcd runs it.  Drop
# that one line and append the driver, so the module's top-level code builds
# `methods` and the driver drives it in the same scope.  Nothing else about the
# file changes.
sed '$d' "$WORK/rpc.uc" > "$WORK/run.uc"
sed -e "s#@@WORK@@#$WORK#" -e "s#@@STAGE@@#$WORK/tmp#" -e "s#@@SCRIPTS@@#$WORK/scripts#g" \
	"$WORK/driver_body.uc" >> "$WORK/run.uc"

if ucode -L "$WORK/scripts" -L "$WORK" "$WORK/run.uc"; then
	echo "PASS: rpc method behaviour"
	rm -rf "$WORK"
	exit 0
else
	echo "FAIL: rpc method behaviour"
	rm -rf "$WORK"
	exit 1
fi
