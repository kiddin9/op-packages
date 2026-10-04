/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * A single self-contained diagnostic report, built in-process for the
 * `debug_report` rpc method (see luci.homeproxy-pro).  It exists because the
 * failure modes this plugin has are not visible from the log page: a route
 * that stopped splitting, an nft rule that is not in the fw4 table, a
 * rule-set that never downloaded, a mark that no longer matches anything.
 * Each of those needs a different command to confirm, and collecting them
 * by hand over ssh is slow and easy to get wrong - the commands are spread
 * across `ip rule`, `nft`, the procd state and the resource version files.
 *
 * Two properties are deliberate and are the reason this is not a shell
 * script dropped in beside the other runtime helpers:
 *
 * 1. REDACTION IS DEFAULT-DENY.  A node section is a credential store: it
 *    holds passwords, uuids, private keys, SNI and the server address.  A
 *    report that is going to be pasted into an issue tracker has to be safe
 *    by construction, so the rule is "if the key looks like a secret, mask
 *    it" rather than an enumerated list of keys to mask - the enumerated
 *    kind is exactly the one that goes stale when a field is added.  The
 *    pattern is applied to the key name, so a value is masked no matter
 *    which section it came from.
 *
 * 2. EVERY PROBE DEGRADES.  A report that aborts because `nft` is missing,
 *    or that silently omits a section when a command fails, is worse than
 *    no report: the reader cannot tell "not applicable" from "not
 *    collected".  Each probe therefore reports one of three states -
 *    the output, "(unavailable)" for a missing command, or
 *    "(no output, exit N)" for one that ran and failed.  This is the same
 *    distinction health.sh draws between "probe failed" and "cannot probe
 *    here", and it is why a testbed without netfilter still produces a
 *    usable report.
 *
 * The commands below are fixed literals: nothing in this file is built from
 * configuration, so there is no shell interpolation to get wrong and no
 * argument that would need shellQuote().
 */

'use strict';

import { popen } from 'fs';

import { HP_DIR, RUN_DIR, shellQuote } from '../homeproxy-pro.uc';

export const DEBUG_REPORT_PATH = RUN_DIR + '/debug.log';

/* Per-section output cap.  The nft dump is the one section that is expected
 * to be large - a populated fw4 table runs to a few thousand lines, and
 * truncating it is worse than useless because a truncated chain looks like
 * a chain that ends there.  The cap is high enough that a real router never
 * reaches it, and reaching it is stated in the output rather than hidden. */
const SECTION_MAX = 128 * 1024;

/* A key whose name matches any of these is masked.  Deliberately broad: a
 * false positive costs a line of a report, a false negative ships someone's
 * private key.  `method` and `path` are in the list because obfs parameters
 * and websocket paths are credentials in practice; `user` catches both
 * `username` and the access-control user lists; `short` is there for
 * `tls_reality_short_id`, which matched nothing until a canary run put a
 * value in it and found it in the report verbatim.
 *
 * `url` is the one pattern that is NOT a bare substring, and it has to stay
 * that way: a plain `url` alternative matches inside `main_urltest_nodes` and
 * `main_urltest_tolerance` (`main_u-r-l-test`), which silently blanked the
 * urltest pool out of the report.  Those lists are how you tell "this node
 * is still in the test pool" from "this node was dropped", which is a
 * question the report exists to answer.  Anchoring on a word boundary keeps
 * `url` / `urls` / `subscription_urls` covered and leaves the pool visible. */
const SECRET_KEY_RE = /pass|secret|token|key|uuid|(^|_)urls?$|address|server|host|sni|user|psk|path|method|param|seed|salt|auth|hosts|short/i;

/* Exported for the rpc behaviour test: the redaction rule is the one part of
 * this file with no I/O to observe, so it is the one part that can be
 * asserted directly - a key that stops being recognised is a silent leak. */
export function isSecretKey(name) {
	/* ucode has no RegExp.prototype.test - the module-level match() is the
	 * only way to apply a pattern, and every other file in this tree does it
	 * the same way. */
	return type(name) === 'string' && match(name, SECRET_KEY_RE) != null;
};

function maskValue(value) {
	/* A list keeps its length visible: "3 masked entries" tells the reader
	 * the subscription imported something, which is a fact worth having,
	 * without disclosing any of it. */
	if (type(value) === 'array')
		return value === null || length(value) === 0
			? value
			: sprintf('[%d masked]', length(value));

	return '***';
};

/* Run one collector.  Returns { state, text } where state is 'ok',
 * 'unavailable' or 'failed', so the caller can label it honestly instead of
 * printing an empty block that reads like "nothing to see". */
function probe(command) {
	if (command == null)
		return { state: 'unavailable', text: '' };

	const fd = popen(command);
	if (fd == null)
		return { state: 'unavailable', text: '' };

	let out = fd.read('all');
	fd.close();

	if (out == null)
		return { state: 'failed', text: '' };

	out = trim(out);

	/* popen() gives no exit status, so an empty result is the only signal
	 * that the command produced nothing.  Whether that is a problem
	 * depends on the command, and the section header says which. */
	if (out === '')
		return { state: 'failed', text: '' };

	if (length(out) > SECTION_MAX)
		out = substr(out, 0, SECTION_MAX) +
			sprintf('\n... [truncated at %d bytes; rerun the command by hand for the full output]\n', SECTION_MAX);

	return { state: 'ok', text: out };
};

/* The value form of the same collector: trimmed stdout, or null when the
 * command produced nothing.  Used where the caller wants a value rather
 * than a rendered block.  Deliberately not written with the optional-chaining
 * shorthand, which no other file in this tree uses. */
function runCommand(command) {
	const fd = popen(command);
	if (fd == null)
		return null;

	const out = fd.read('all');
	fd.close();

	if (out == null)
		return null;

	const t = trim(out);
	return t === '' ? null : t;
};

function runDate() {
	return runCommand('date "+%Y-%m-%d %H:%M:%S %Z"') || 'unknown';
};

/* Render one ```bash fenced block for a command, with the state spelled out
 * when there is no output to show. */
function block(command, unavailable_label) {
	const r = probe(command);

	if (r.state === 'ok')
		return sprintf('```shell\n# %s\n%s\n```\n', command, r.text);

	if (r.state === 'unavailable')
		return sprintf('```\n(unavailable: %s)\n```\n', unavailable_label || command);

	return '```\n(no output)\n```\n';
};

/* Render a two-column table, or a single "(unavailable)" row. */
function table(rows, unavailable_label) {
	if (rows == null)
		return sprintf('_%s_\n', unavailable_label || 'unavailable');

	let out = '| 项目 | 值 |\n|------|-----|\n';
	for (let r in rows)
		out += sprintf('| %s | %s |\n', r[0], r[1]);
	return out;
};

/* `apk list -I <pkg>` prints one line:
 *
 *   sing-box-1.14.2-r1 x86_64 {feeds/.../sing-box} (GPL-3.0-or-later) [installed]
 *
 * The package name is the argument, so the version is simply what follows
 * that name's trailing dash up to the first space.  A pattern anchored on
 * a negated class instead - `^[^ -]+-([0-9][^ ]*)` - stops at the FIRST
 * dash, so it works for `firewall4` and silently fails for every package
 * whose own name contains one (`sing-box`, `luci-app-homeproxy-pro`), which is
 * most of them.  Splitting on the known prefix has no such case.
 *
 * This also avoids `\\s` inside a negated class, whose meaning inside `[...]`
 * is not what it is outside: `homeproxy-pro.uc`'s `replace(reason, /\s+/g, ' ')`
 * collapses whitespace correctly, yet the same `\s` inside `[^\\s-]` did not
 * exclude whitespace, and the version came back with the architecture glued
 * to it. */
function packageVersion(name) {
	if (system('command -v apk >/dev/null 2>&1') !== 0)
		return null;

	const fd = popen(sprintf('apk list -I %s 2>/dev/null', shellQuote(name)));
	if (fd == null)
		return null;

	const line = trim(fd.read('line'));
	fd.close();

	if (line == null || line === '')
		return null;

	const prefix = name + '-';
	if (index(line, prefix) !== 0)
		return null;

	const rest = substr(line, length(prefix));
	const sp = index(rest, ' ');
	const v = (sp == -1) ? rest : substr(rest, 0, sp);

	return v === '' ? null : v;
};

/* --- UCI summary --------------------------------------------------------- */

/* A structural, redacted view of the configuration: counts and switch
 * positions, never a credential.  Sections are summarised by type rather
 * than dumped, because a node section has no field that is safe to print
 * and a subscription section has exactly one. */
function configSummary(uci) {
	const all = uci.get_all('homeproxy-pro') || {};
	const byType = {};

	for (let sid in all) {
		const section = all[sid];
		const stype = section['.type'] || 'unknown';

		if (byType[stype] == null)
			byType[stype] = { count: 0, sample: section['.name'] || sid };

		byType[stype].count++;
	}

	if (byType == null || length(keys(byType)) === 0)
		return '_configuration is empty_\n';

	let out = '';

	for (let t in keys(byType)) {
		out += sprintf('- `%s`: %d section(s)\n', t, byType[t].count);
	}

	/* The switches that decide what the report is FOR: which mode, which
	 * ports, and the mark - these are the first things anyone reading a
	 * routing problem looks for, and none of them is sensitive.  Each entry
	 * is [section, option]. */
	const switches = [
		['config', 'proxy_mode'],
		['config', 'routing_mode'],
		['config', 'main_node'],
		['config', 'main_udp_node'],
		['config', 'ipv6_support'],
		['config', 'log_level'],
		['config', 'bypass_cn_traffic'],
		['infra', 'mixed_port'],
		['infra', 'redirect_port'],
		['infra', 'tproxy_port'],
		['infra', 'dns_port'],
		['infra', 'self_mark'],
		['infra', 'tproxy_mark'],
		['infra', 'tun_mark'],
		['infra', 'table_mark'],
		['infra', 'tun_name'],
		['server', 'enabled']
	];

	out += '\n| 开关 | 值 |\n|------|-----|\n';
	for (let sw in switches) {
		const v = uci.get('homeproxy-pro', sw[0], sw[1]);
		out += sprintf('| `%s.%s` | %s |\n', sw[0], sw[1],
			(v == null || v === '') ? '_(unset)_' : (isSecretKey(sw[1]) ? maskValue(v) : v));
	}

	return out;
};

/* Every non-secret option, flattened, with anything that looks like a
 * credential masked.  This is the section that makes the report useful for
 * "which option did I set wrong" - the summary above cannot show them. */
function fullConfig(uci) {
	const all = uci.get_all('homeproxy-pro') || {};
	let out = '';

	for (let sid in keys(all)) {
		const section = all[sid];
		const stype = section['.type'] || 'unknown';
		const sname = section['.name'] || sid;

		out += sprintf('\n### %s `%s`\n\n```\n', stype, sname);

		for (let k in keys(section)) {
			if (substr(k, 0, 1) === '.')
				continue;

			const v = section[k];

			if (isSecretKey(k)) {
				out += sprintf('option %s %s\n', k, maskValue(v));
			} else if (type(v) === 'array') {
				out += sprintf('list %s %s\n', k,
					length(v) === 0 ? '' : join(' ', v));
			} else {
				out += sprintf('option %s %s\n', k, v);
			}
		}

		out += '```\n';
	}

	return out == '' ? '_configuration is empty_\n' : out;
};

/* --- resource versions --------------------------------------------------- */

/* The .ver files next to each shipped list.  A rule-set that has been
 * failing to download shows up here as a version that never moves, which is
 * the cheapest way to tell "the list is stale" from "the list is missing". */
function resourceVersions() {
	const names = ['china_ip4', 'china_ip6', 'china_list', 'gfw_list'];
	let out = '';

	for (let n in names) {
		const path = sprintf('%s/resources/%s.ver', HP_DIR, n);
		const fd = popen(sprintf('cat %s 2>/dev/null', shellQuote(path)));

		if (fd != null) {
			const v = trim(fd.read('all'));
			fd.close();
			out += sprintf('- `%s`: %s\n', n, (v == null || v === '') ? '_(no version file)_' : v);
		} else {
			out += sprintf('- `%s`: _(unavailable)_\n', n);
		}
	}

	/* The dnsmasq nftset capability marker: init.d writes this at start
	 * and firewall_post.ut gates the gfwlist mode on it, so a device whose
	 * dnsmasq was built without HAVE_NFTSET silently routes everything
	 * direct while DNS still goes through the proxy. */
	const marker = sprintf('%s/resources/.dnsmasq-nftset', HP_DIR);
	const fd = popen(sprintf('cat %s 2>/dev/null', shellQuote(marker)));
	let cap = 'unknown';
	if (fd != null) {
		cap = trim(fd.read('all')) || 'unknown';
		fd.close();
	}
	out += sprintf('- `dnsmasq nftset`: %s', cap == '1' ? 'yes' : (cap == '0' ? 'no (gfwlist mode cannot work)' : cap));

	return out + '\n';
};

/* --- the report ---------------------------------------------------------- */

export function buildDebugReport(uci) {
	const stamp = trim(runDate());

	let out = '';
	out += '# HomeProxy 诊断报告\n\n';
	out += sprintf('> 生成时间: %s\n', stamp == '' ? '(unknown)' : stamp);
	out += sprintf('> 插件版本: %s\n', packageVersion('luci-app-homeproxy-pro') || 'unknown');
	out += '> 隐私: 凭据字段已按名称脱敏，但本报告仍含公网 IP、内网拓扑和 LAN 主机地址。\n';
	out += '>      外发前请自行确认。\n';

	/* 1. System */
	out += '\n## 1. 系统\n\n';
	out += block('cat /etc/openwrt_release 2>/dev/null', 'uname -a');
	out += block('uname -a');
	out += block('uptime');
	out += block('df -h / /tmp /etc/homeproxy-pro 2>/dev/null', 'df unavailable');
	out += block('free -m 2>/dev/null', 'free unavailable');

	/* 2. Dependencies - the table, not a "is it there" yes/no, because the
	 * version is what a reader needs when reporting "it does not work on
	 * this build". */
	out += '\n## 2. 依赖检查\n\n';
	const deps = ['sing-box', 'firewall4', 'kmod-nft-tproxy', 'kmod-tun',
	              'ip-full', 'uclient-fetch', 'ucode', 'ucode-mod-digest'];
	const dep_rows = [];

	for (let d in deps) {
		const v = packageVersion(d);
		push(dep_rows, [d, v == null ? '_(not reported by apk; may be built in)_' : v]);
	}

	out += table(dep_rows, 'apk not available on this system');

	/* 3. Core capabilities */
	out += '\n## 3. 内核与能力\n\n';
	out += block('/usr/bin/sing-box version 2>/dev/null', 'sing-box not installed');
	out += block('lsmod 2>/dev/null | grep -E "tun|nft_tproxy|inet_diag"', 'lsmod unavailable');
	out += block('command -v nft fw4 utpl ucode uci 2>/dev/null', 'PATH lookup unavailable');

	/* 4. Configuration */
	out += '\n## 4. 配置摘要（脱敏）\n\n';
	out += configSummary(uci);

	/* 5. Resources */
	out += '\n## 5. 资源版本\n\n';
	out += resourceVersions();

	/* 6. Service */
	out += '\n## 6. 服务状态\n\n';
	out += block('/etc/init.d/homeproxy-pro info 2>&1', 'init script unavailable');
	out += block('ubus call service list \'"name":"homeproxy-pro"\' 2>/dev/null',
		'ubus unavailable');

	/* 7. Routing - `ip rule` first, because the mark that routes a
	 * connection into the proxy is set there, and a rule that is missing
	 * explains a proxy that binds its ports and then times out. */
	out += '\n## 7. 路由策略\n\n';
	out += '### ip rule\n\n';
	out += block('ip rule list');
	out += '### ip route\n\n';
	out += block('ip -4 route list');
	out += block('ip -6 route list');
	out += sprintf('\n**策略路由表**（table_mark / tproxy_mark / tun_mark）:\n\n```shell\n# ip route list table 100\n%s\n```\n',
		trim(runCommand('ip route list table 100 2>/dev/null') || '(empty or unavailable)'));

	/* 8. Firewall - the full fw4 table, not just homeproxy-pro's own chains.
	 * The failure this covers is "homeproxy-pro's rules are present and
	 * correct but something in fw4 jumps to another chain first", and
	 * that is only visible with the surrounding rules in view. */
	out += '\n## 8. 防火墙\n\n';
	out += '_The full `inet fw4` table. homeproxy-pro\'s chains are the ones named '
		+ '`homeproxy_*`; everything else is fw4\'s own._\n\n';
	out += block('nft -a list table inet fw4 2>/dev/null', 'nft unavailable (is firewall4 installed?)');

	/* 9. Log excerpts - the tail of each log, not the whole file: the
	 * interesting part of a failure is the last thing that happened. */
	out += '\n## 9. 日志尾部\n\n';
	for (let l in ['homeproxy-pro', 'sing-box-c', 'sing-box-s']) {
		out += sprintf('### %s.log\n\n', l);
		out += block(sprintf('tail -n 60 %s/%s.log 2>/dev/null', RUN_DIR, l),
			sprintf('%s.log not present', l));
	}

	/* 10. Full redacted configuration */
	out += '\n## 10. 完整配置（脱敏）\n\n';
	out += fullConfig(uci);

	return out;
};
