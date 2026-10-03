#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * What the UI does when an RPC does not answer.  Two paths, both of which
 * used to state something false rather than admit ignorance.
 *
 * getBuiltinFeatures() goes through rpcCall(), which resolves to `{}` when the
 * call does not come back. The protocol list used to be filtered against that
 * map unconditionally, so an empty map hid every feature-gated protocol
 * (hysteria, hysteria2, naive, tuic, wireguard). A node already saved as one
 * of them then rendered with no matching Select option, and LuCI's
 * AbstractValue.parse() writes whenever formvalue != cfgvalue - so the next
 * Save & Apply silently rewrote the node's `type` to whichever protocol came
 * first. Silent protocol change, from a failed status RPC.
 *
 * No test could see it: luci-form-snapshot.js always passes the fully
 * populated feature map (and its rpc stub always resolves), so the empty-map
 * path was never taken.
 *
 * Usage: node tests/frontend-feature-fallback.js <repo-root>
 */

'use strict';

const path = require('path');

const { loadLuciModule } = require('./lib/luci-module.js');

const root = path.resolve(process.argv[2] || '.');

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

const hp = loadLuciModule(
	path.join(root, 'htdocs/luci-static/resources/homeproxy-pro.js'),
	{ baseclass: { extend: (o) => o }, form: { DynamicList: { extend: (o) => o } },
	  fs: {}, rpc: {}, uci: {}, ui: {} });

function types(side, features) {
	return hp.protocolChoices(side, features).map((p) => p.type);
}

const FULL = { with_quic: true, with_wireguard: true, with_gvisor: true };
const GATED_CLIENT = ['hysteria', 'hysteria2', 'tuic', 'wireguard'];
const GATED_SERVER = ['hysteria', 'hysteria2', 'naive', 'tuic'];

/* --- the failure path: an empty map means "unknown", not "none" ---------- */

for (const [side, gated] of [['client', GATED_CLIENT], ['server', GATED_SERVER]]) {
	const unknown = types(side, {});
	const full = types(side, FULL);

	for (const g of gated) {
		check(`${side}: ${g} is still offered when the feature call failed`,
			unknown.indexOf(g) !== -1,
			`offered: ${unknown.join(',')}`);
	}

	/* The property that actually matters: an unanswered call must not offer
	 * FEWER protocols than a successful one. */
	check(`${side}: an unknown feature map offers at least as many as a full one`,
		unknown.length >= full.length,
		`unknown=${unknown.length} full=${full.length}`);

	check(`${side}: the unknown list contains everything the full list does`,
		full.every((t) => unknown.indexOf(t) !== -1),
		`missing: ${full.filter((t) => unknown.indexOf(t) === -1).join(',')}`);
}

/* --- and the filter still works when the features ARE known -------------- */

const noQuic = types('client', { with_quic: false, with_wireguard: true, with_gvisor: true });
for (const g of ['hysteria', 'hysteria2', 'tuic'])
	check(`client: ${g} is filtered out when with_quic is false`, noQuic.indexOf(g) === -1,
		`offered: ${noQuic.join(',')}`);
check('client: wireguard survives with_quic=false', noQuic.indexOf('wireguard') !== -1);

/* wireguard needs BOTH of its features; one missing must be enough to hide it. */
const partialWg = types('client', { with_quic: true, with_wireguard: true, with_gvisor: false });
check('client: wireguard is hidden when only one of its features is present',
	partialWg.indexOf('wireguard') === -1, `offered: ${partialWg.join(',')}`);

/* --- renderProtocolOptions must use the same rule ------------------------ */

function driveRenderProtocolOptions(features, side) {
	const offered = [];
	const fakeOption = {
		value: (type) => { offered.push(type); },
		rmempty: true
	};
	const fakeSection = { option: () => fakeOption };

	hp.renderProtocolOptions(fakeSection, { features: features, side: side });
	return offered;
}

for (const [side, gated] of [['client', GATED_CLIENT], ['server', GATED_SERVER]]) {
	const offered = driveRenderProtocolOptions({}, side);
	for (const g of gated)
		check(`renderProtocolOptions(${side}, {}) still offers ${g}`,
			offered.indexOf(g) !== -1, `offered: ${offered.join(',')}`);
}

const renderedFull = driveRenderProtocolOptions(FULL, 'client');
check('renderProtocolOptions offers every client protocol with full features',
	renderedFull.length === types('client', FULL).length,
	`${renderedFull.length} vs ${types('client', FULL).length}`);

/* --- the status bar: "the query failed" is not "the service is down" ----- */

/* getServiceStatus() asks rpcCall() for a `null` fallback so it can tell the
 * two apart; the default `{}` made the try/catch report a failed query as
 * NOT RUNNING, which reads as "your proxy is down". */
const running = hp.statusLabel(true);
const stopped = hp.statusLabel(false);
const unknown = hp.statusLabel(null);

check('a running service is green', String(running.color) === 'green', String(running.color));
check('a stopped service is red', String(stopped.color) === 'red', String(stopped.color));
check('an unanswered query is neither green nor red',
	String(unknown.color) !== 'green' && String(unknown.color) !== 'red',
	String(unknown.color));

check('an unanswered query does not say NOT RUNNING',
	String(unknown.text) !== String(stopped.text),
	`unknown=${String(unknown.text)} stopped=${String(stopped.text)}`);
check('an unanswered query does not say RUNNING either',
	String(unknown.text) !== String(running.text),
	`unknown=${String(unknown.text)} running=${String(running.text)}`);
check('a missing status argument is treated as unknown',
	String(hp.statusLabel(undefined).text) === String(unknown.text));
check('the three states are three distinct texts',
	new Set([String(running.text), String(stopped.text), String(unknown.text)]).size === 3);

/* --- the status poll registers exactly once ----------------------------- */

/* The flag that makes this true used to live in client.js and server.js as two
 * separate booleans. Every re-render that got past it added another poll
 * handler, and LuCI keeps them all. The form snapshots never reach this code,
 * so nothing could fail until the state moved somewhere testable. */
function makePoll() {
	const added = [];
	return {
		added: added,
		poll: { add: (fn) => { added.push(fn); return added.length; } }
	};
}

{
	const h = makePoll();
	let reads = 0;
	const register = hp.statusPoller({
		poll: h.poll,
		read: () => { reads++; return Promise.resolve('v'); },
		paint: () => {}
	});

	check('the first registration reports that it registered', register() === true);
	check('a second registration reports that it did not', register() === false);
	check('a third registration reports that it did not', register() === false);
	check('exactly one poll handler was added', h.added.length === 1, `${h.added.length} added`);

	/* The handler has to actually do something - a registrar that registered an
	 * empty function would satisfy the count above. read() is called
	 * synchronously inside the handler, so this needs no awaiting (and a
	 * top-level `return` is not allowed in a CommonJS module anyway - the first
	 * version of this used one and the whole file failed to load, printing
	 * nothing at all). */
	h.added[0]();
	check('the registered handler calls read() when invoked', reads === 1, `${reads} reads`);
}

/* --- the rule-set degradation report ------------------------------------
 *
 * parseRuleSetFetchFailures() is the only thing that tells a user a rule-set
 * is currently EMPTY, because with ruleset_safe_start on there is no other
 * symptom: the instance is healthy, the health gate passes (nothing in
 * health.sh looks at rule-sets), and the LAN is proxied.
 *
 * It parses a file sing-box is concurrently writing and that clean_log.sh
 * truncates at 50 KB, so the cases below are about tolerance and about not
 * lying: a missing timestamp must read as "no timestamp", never as a guess.
 */
const FAILURES = hp.parseRuleSetFetchFailures;

/* The first two lines are VERBATIM from a real sing-box 1.14.2 run on the
 * target (an isolated instance with the rule-set URLs pointed at an
 * unreachable port), including the `+0800` UTC offset that precedes the date.
 *
 * That offset is the reason this case exists.  The first version of the
 * timestamp pattern was anchored at the start of the line and matched a bare
 * date, which parses fine against every hand-written sample and returns null
 * for every line the device actually writes - so the panel would have shown
 * the right tag and the right reason and no time on every real failure.  Only
 * a real line catches that, and it is pinned here so it cannot come back. */
const SAMPLE = [
	'+0800 2026-10-03 09:29:34 INFO sing-box started (0.05s)',
	'+0800 2026-10-03 09:29:34 ERROR router: fetch rule-set geoip-cn: Get "http://127.0.0.1:9/geoip-cn.srs": remote error: open connection to 127.0.0.1:9 using outbound/direct[direct]: dial tcp 127.0.0.1:9: connect: connection refused',
	'+0800 2026-10-03 09:29:34 ERROR router: fetch rule-set geosite-cn: Get "http://127.0.0.1:9/geosite-cn.srs": remote error: open connection to 127.0.0.1:9 using outbound/direct[direct]: dial tcp 127.0.0.1:9: connect: connection refused',
	''
].join('\n');

check('an empty log yields no failures', FAILURES('').length === 0);
check('a log of blank lines yields no failures', FAILURES('\n\n').length === 0);
check('a log with no fetch lines yields no failures',
	FAILURES('2026-10-03 01:15:42 INFO router: loaded rule-set geoip-cn').length === 0);

const sample = FAILURES(SAMPLE);
check('both failing tags are reported', sample.length === 2, JSON.stringify(sample));
check('the tag is captured without the surrounding prose',
	sample.map((f) => f.tag).join(',') === 'geoip-cn,geosite-cn',
	JSON.stringify(sample.map((f) => f.tag)));
check('the reason is captured',
	sample[0].reason.startsWith('Get "http://'), JSON.stringify(sample[0].reason));
check('the timestamp is captured despite the +0800 offset before it',
	sample[0].at === '2026-10-03 09:29:34', String(sample[0].at));
check('the reason survives the full real line',
	sample[1].reason.startsWith('Get "http://127.0.0.1:9/'), JSON.stringify(sample[1].reason));
check('the reason keeps the nested colons and quotes',
	sample[1].reason.includes('dial tcp 127.0.0.1:9: connect: connection refused'),
	JSON.stringify(sample[1].reason));

/* A negative UTC offset, and a build that omits the offset entirely, both have
 * to keep working - the offset is optional in the pattern on purpose. */
const westOfUTC = FAILURES('-0500 2026-12-31 20:00:00 ERROR router: fetch rule-set geoip-cn: timeout');
check('a negative UTC offset still yields the time',
	westOfUTC[0].at === '2026-12-31 20:00:00', String(westOfUTC[0].at));
const noOffset = FAILURES('2026-12-31 20:00:00 ERROR router: fetch rule-set geoip-cn: timeout');
check('a line with no offset at all still yields the time',
	noOffset[0].at === '2026-12-31 20:00:00', String(noOffset[0].at));

/* A rule-set that fails on every 24-hour refresh is in the log many times, and
 * the file is truncated - so the most recent line has to win, or the panel
 * shows a reason from yesterday as if it were current. */
const REPEATED = [
	'+0800 2026-10-01 01:00:00 ERROR router: fetch rule-set geoip-cn: old failure',
	'+0800 2026-10-03 01:00:00 ERROR router: fetch rule-set geoip-cn: new failure'
].join('\n');
const repeated = FAILURES(REPEATED);
check('a repeated tag is reported once', repeated.length === 1, JSON.stringify(repeated));
check('the most recent failure wins for a repeated tag',
	repeated[0].reason === 'new failure', JSON.stringify(repeated[0].reason));

/* clean_log.sh can cut mid-line, and a truncated line must not become a
 * failure with a nonsense reason - but it must still name its tag, or the
 * panel would hide a rule-set that really is failing. */
const truncated = FAILURES('+0800 2026-10-03 01:00:00 ERROR router: fetch rule-set geoip-cn: Get "https://exa');
check('a truncated line still names its tag', truncated.length === 1, JSON.stringify(truncated));
check('a truncated line keeps the timestamp it has',
	truncated[0].at === '2026-10-03 01:00:00', String(truncated[0].at));

/* The format is not assumed. A line with no timestamp is still reported, with
 * the time simply absent - the panel omits it rather than inventing one. */
const noTime = FAILURES('ERROR router: fetch rule-set geosite-cn: dial tcp: i/o timeout');
check('a line without a timestamp is still reported', noTime.length === 1, JSON.stringify(noTime));
check('a line without a timestamp reports no time', noTime[0].at === null, String(noTime[0].at));
check('a line without a timestamp still yields the reason',
	noTime[0].reason === 'dial tcp: i/o timeout', JSON.stringify(noTime[0].reason));

check('the parser tolerates null', FAILURES(null).length === 0);
check('the parser tolerates undefined', FAILURES(undefined).length === 0);

console.log(`frontend rpc fallbacks: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
