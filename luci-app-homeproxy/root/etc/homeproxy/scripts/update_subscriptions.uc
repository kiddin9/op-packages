#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

'use strict';

import { md5 } from 'digest';
import { lstat, open } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import { init_action } from 'luci.sys';

import {
	wGETVerbose, decodeBase64Str, getTime, isEmpty, shellQuote, HP_DIR, RUN_DIR
} from 'homeproxy';

import { parse_uri } from 'parse_uri';

/* UCI config start */
const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const ucimain = 'config',
      ucinode = 'node',
      ucisubscription = 'subscription';

const allow_insecure = uci.get(uciconfig, ucisubscription, 'allow_insecure') || '0',
      filter_mode = uci.get(uciconfig, ucisubscription, 'filter_nodes') || 'disabled',
      filter_keywords = uci.get(uciconfig, ucisubscription, 'filter_keywords') || [],
      packet_encoding = uci.get(uciconfig, ucisubscription, 'packet_encoding') || 'xudp',
      subscription_urls = uci.get(uciconfig, ucisubscription, 'subscription_url') || [],
      user_agent = uci.get(uciconfig, ucisubscription, 'user_agent'),
      via_proxy = uci.get(uciconfig, ucisubscription, 'update_via_proxy') || '0';

const routing_mode = uci.get(uciconfig, ucimain, 'routing_mode') || 'bypass_mainland_china';
let main_node, main_udp_node;
if (routing_mode !== 'custom') {
	main_node = uci.get(uciconfig, ucimain, 'main_node') || 'nil';
	main_udp_node = uci.get(uciconfig, ucimain, 'main_udp_node') || 'nil';
}
/* UCI config end */

/* String helper start */
function filter_check(name) {
	if (isEmpty(name) || filter_mode === 'disabled' || isEmpty(filter_keywords))
		return false;

	let ret = false;
	for (let i in filter_keywords) {
		let patten;
		try {
			patten = regexp(i);
		} catch(e) {
			log(sprintf('Skipping invalid filter keyword regex: %s.', i));
			continue;
		}
		if (patten && match(name, patten))
			ret = true;
	}
	if (filter_mode === 'whitelist')
		ret = !ret;

	return ret;
}
/* String helper end */

/* Common var start */
const node_cache = {},
      node_result = [];

const ubus = connect();
const sing_features = ubus.call('luci.homeproxy', 'singbox_get_features', {}) || {};
if (isEmpty(sing_features))
	log('Warning: Failed to query sing-box features via ubus, assuming defaults.');
/* Common var end */

/* Log */
system(`mkdir -p ${RUN_DIR}`);
function log(...args) {
	const logfile = open(`${RUN_DIR}/homeproxy.log`, 'a');
	logfile.write(`${getTime()} [SUBSCRIBE] ${join(' ', args)}\n`);
	logfile.close();
}

/*
 * Subscription URLs usually carry the provider token in the query string;
 * the log is surfaced in LuCI, so keep it out.
 */
function redact(url) {
	return replace(url, /[?#].*$/, '');
}

/*
 * mkdir is the lock: atomic everywhere this runs and no flock binding needed.
 * A lock older than LOCK_STALE is broken, so a killed run cannot block every
 * later update. Two concurrent runs (cron + the LuCI button) used to
 * interleave commits and service restarts.
 */
const LOCK_DIR = RUN_DIR + '/update_subscriptions.lock';
const LOCK_STALE = 600;

function acquire_lock() {
	if (system(sprintf('mkdir %s 2>/dev/null', shellQuote(LOCK_DIR))) === 0)
		return true;

	const st = lstat(LOCK_DIR);
	const age = st ? max(0, time() - (st.mtime || 0)) : null;

	if (age != null && age > LOCK_STALE) {
		log(sprintf('Breaking a stale update lock (%s seconds old).', age));
		system(sprintf('rmdir %s 2>/dev/null', shellQuote(LOCK_DIR)));

		return system(sprintf('mkdir %s 2>/dev/null', shellQuote(LOCK_DIR))) === 0;
	}

	return false;
}

function release_lock() {
	system(sprintf('rmdir %s 2>/dev/null', shellQuote(LOCK_DIR)));
}

/*
 * sing-box rejects the whole generated config over one malformed node, and the
 * generator keeps the old config when it fails, so a node that cannot possibly
 * work must not reach UCI. Returns the reason, or null when the node is usable.
 */
function node_problem(cfg) {
	if (isEmpty(cfg.address) || isEmpty(cfg.port))
		return 'missing address or port';
	if (!validation_port(cfg.port))
		return 'invalid port';

	switch (cfg.type) {
	case 'shadowsocks':
		if (isEmpty(cfg.shadowsocks_encrypt_method) || isEmpty(cfg.password))
			return 'missing shadowsocks method or password';
		break;
	case 'vless':
	case 'vmess':
		if (isEmpty(cfg.uuid))
			return 'missing uuid';
		break;
	case 'trojan':
	case 'anytls':
	case 'snell':
		if (isEmpty(cfg.password))
			return 'missing password';
		break;
	case 'tuic':
		if (isEmpty(cfg.uuid) || isEmpty(cfg.password))
			return 'missing uuid or password';
		break;
	case 'hysteria':
	case 'hysteria2':
		if (isEmpty(cfg.password) && isEmpty(cfg.hysteria_auth_payload))
			return 'missing auth';
		break;
	case 'socks':
	case 'http':
		break;
	default:
		return 'unsupported type';
	}

	return null;
}

function validation_port(port) {
	return match(port, /^\d{1,5}$/) != null && int(port) > 0 && int(port) <= 65535;
}

function main() {
	if (via_proxy !== '1') {
		log('Stopping service...');
		init_action('homeproxy', 'stop');
	}

	for (let url in subscription_urls) {
		url = replace(url, /#.*$/, '');
		const groupHash = md5(url);
		node_cache[groupHash] = {};
		const shown_url = redact(url);

		const fetched = wGETVerbose(url, user_agent);
		if (isEmpty(fetched.content)) {
			log(sprintf('Failed to fetch resources from %s: %s', shown_url, fetched.error || 'empty response'));
			continue;
		}
		const res = fetched.content;

		let nodes;
		try {
			nodes = json(res).servers || json(res);

			/* Shadowsocks SIP008 format */
			if (nodes[0].server && nodes[0].method)
				map(nodes, (_, i) => nodes[i].nodetype = 'sip008');
		} catch(e) {
			/* Clash/mihomo subscriptions are YAML, not base64; say so instead
			   of reporting a base64/JSON failure followed by "no valid node". */
			if (match(res, /(^|\n)[ \t]*(proxies|proxy-groups)[ \t]*:/)) {
				log(sprintf('Unsupported subscription format (Clash/mihomo YAML) at %s.', shown_url));
				continue;
			}

			log(sprintf('JSON parse failed for %s, trying base64: %s', shown_url, e.message));
			nodes = decodeBase64Str(res);
			nodes = nodes ? split(trim(nodes), '\n') : [];
		}

		let count = 0, skipped = 0;
		for (let node in nodes) {
			if (isEmpty(node))
				continue;

			const config = parse_uri(node, sing_features, log);
			if (isEmpty(config)) {
				/* No credentials in the log: only the scheme says whether a
				   parser is missing or the entry is simply not a node. Only
				   the first few are printed, the rest is summarized below. */
				if (skipped < 5)
					log(sprintf('Skipping unparsable entry (%s) from %s.',
						type(node) === 'string' ? replace(node, /:.*$/, '') : type(node), shown_url));
				skipped++;
				continue;
			}

			const problem = node_problem(config);
			if (problem) {
				if (skipped < 5)
					log(sprintf('Skipping invalid node %s: %s.', config.label || config.address, problem));
				skipped++;
				continue;
			}

			const label = config.label;
			config.label = null;
			const confHash = md5(sprintf('%J', config)),
			      nameHash = md5(groupHash + label);
			config.label = label;

			if (filter_check(config.label))
				log(sprintf('Skipping blacklist node: %s.', config.label));
			else if (node_cache[groupHash][confHash] || node_cache[groupHash][nameHash])
				log(sprintf('Skipping duplicate node: %s.', config.label));
			else {
				if (config.tls === '1' && allow_insecure === '1')
					config.tls_insecure = '1';
				if (config.type in ['vless', 'vmess'])
					config.packet_encoding = packet_encoding;

				config.grouphash = groupHash;
				push(node_result, []);
				push(node_result[length(node_result)-1], config);
				node_cache[groupHash][confHash] = config;
				node_cache[groupHash][nameHash] = config;

				count++;
			}
		}

		if (skipped > 0)
			log(sprintf('%s entries skipped from %s.', skipped, shown_url));

		if (count === 0)
			log(sprintf('No valid node found in %s.', shown_url));
		else
			log(sprintf('Successfully fetched %s nodes of total %s from %s.', count, length(nodes), shown_url));
	}

	if (isEmpty(node_result)) {
		log('Failed to update subscriptions: no valid node found.');

		if (via_proxy !== '1') {
			log('Starting service...');
			init_action('homeproxy', 'start');
		}

		return false;
	}

	let added = 0, removed = 0, changed = false;
	uci.foreach(uciconfig, ucinode, (cfg) => {
		/* Nodes created by the user */
		if (!cfg.grouphash)
			return null;

		/* Empty object - failed to fetch nodes, or subscription URL not yet processed */
		if (!node_cache[cfg.grouphash] || length(node_cache[cfg.grouphash]) === 0)
			return null;

		if (!node_cache[cfg.grouphash][cfg['.name']]) {
			uci.delete(uciconfig, cfg['.name']);
			removed++;
			changed = true;

			log(sprintf('Removing node: %s.', cfg.label || cfg['name']));
		} else {
			map(keys(cfg), (v) => {
				/* skip the cursor's own metadata (.name/.type/...): deleting
				   those is a no-op and would mark every run as changed */
				if (substr(v, 0, 1) === '.')
					return null;

				if (v in node_cache[cfg.grouphash][cfg['.name']]) {
					/* only write what actually differs, so an unchanged
					   subscription does not fake a change below */
					const fresh = node_cache[cfg.grouphash][cfg['.name']][v];
					const current = uci.get(uciconfig, cfg['.name'], v);
					if (type(fresh) === 'array' ? (sprintf('%J', uci.get_all(uciconfig, cfg['.name'], v) || []) !== sprintf('%J', fresh))
					    : (current !== sprintf('%s', fresh))) {
						uci.set(uciconfig, cfg['.name'], v, fresh);
						changed = true;
					}
				} else {
					uci.delete(uciconfig, cfg['.name'], v);
					changed = true;
				}
			});
			node_cache[cfg.grouphash][cfg['.name']].isExisting = true;
		}
	});
	for (let nodes in node_result)
		map(nodes, (node) => {
			if (node.isExisting)
				return null;

			const nameHash = md5(node.grouphash + node.label);
			uci.set(uciconfig, nameHash, 'node');
			map(keys(node), (v) => uci.set(uciconfig, nameHash, v, node[v]));

			added++;
			changed = true;
			log(sprintf('Adding node: %s.', node.label));
		});
	uci.commit(uciconfig);

	/* via_proxy keeps the service up during the fetch, but a configuration
	   change still has to be applied - it used to be committed and then
	   ignored until the next restart. */
	let need_restart = (via_proxy !== '1') || changed;
	if (!isEmpty(main_node)) {
		const first_server = uci.get_first(uciconfig, ucinode);
		if (first_server) {
			let main_urltest_nodes;
			if (main_node === 'urltest') {
				const old_urltest_nodes = uci.get(uciconfig, ucimain, 'main_urltest_nodes') || [];
				main_urltest_nodes = filter(old_urltest_nodes, (v) => {
					if (!uci.get(uciconfig, v)) {
						log(sprintf('Node %s is gone, removing from urltest list.', v));
						return false;
					}
					return true;
				});
				if (length(main_urltest_nodes) !== length(old_urltest_nodes)) {
					uci.set(uciconfig, ucimain, 'main_urltest_nodes', main_urltest_nodes);
					uci.commit(uciconfig);
					need_restart = true;
				}
			}

			if ((main_node === 'urltest') ? !length(main_urltest_nodes) : !uci.get(uciconfig, main_node)) {
				uci.set(uciconfig, ucimain, 'main_node', first_server);
				uci.commit(uciconfig);
				need_restart = true;

				log('Main node is gone, switching to the first node.');
			}

			if (!isEmpty(main_udp_node) && main_udp_node !== 'same') {
				let main_udp_urltest_nodes;
				if (main_udp_node === 'urltest') {
					const old_udp_urltest_nodes = uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes') || [];
					main_udp_urltest_nodes = filter(old_udp_urltest_nodes, (v) => {
						if (!uci.get(uciconfig, v)) {
							log(sprintf('Node %s is gone, removing from urltest list.', v));
							return false;
						}
						return true;
					});
					if (length(main_udp_urltest_nodes) !== length(old_udp_urltest_nodes)) {
						uci.set(uciconfig, ucimain, 'main_udp_urltest_nodes', main_udp_urltest_nodes);
						uci.commit(uciconfig);
						need_restart = true;
					}
				}

				if ((main_udp_node === 'urltest') ? !length(main_udp_urltest_nodes) : !uci.get(uciconfig, main_udp_node)) {
					uci.set(uciconfig, ucimain, 'main_udp_node', first_server);
					uci.commit(uciconfig);
					need_restart = true;

					log('Main UDP node is gone, switching to the first node.');
				}
			}
		} else {
			uci.set(uciconfig, ucimain, 'main_node', 'nil');
			uci.set(uciconfig, ucimain, 'main_udp_node', 'nil');
			uci.commit(uciconfig);
			need_restart = true;

			log('No available node, disable tproxy.');
		}
	}

	/* Scrub stale urltest member references in custom routing nodes */
	uci.foreach(uciconfig, 'routing_node', (cfg) => {
		if (cfg.node !== 'urltest' || isEmpty(cfg.urltest_nodes))
			return null;

		const cleaned_nodes = filter(cfg.urltest_nodes, (v) => uci.get(uciconfig, v));
		if (length(cleaned_nodes) !== length(cfg.urltest_nodes)) {
			uci.set(uciconfig, cfg['.name'], 'urltest_nodes', cleaned_nodes);
			uci.commit(uciconfig);
			need_restart = true;

			log(sprintf('Routing node %s: removed gone nodes from urltest list.', cfg['.name']));
		}
	});

	if (need_restart) {
		log('Restarting service...');
		init_action('homeproxy', 'stop');
		init_action('homeproxy', 'start');
	}

	log(sprintf('%s nodes added, %s removed.', added, removed));
	log('Successfully updated subscriptions.');
}

if (!isEmpty(subscription_urls)) {
	if (!acquire_lock()) {
		log('Another subscription update is running, aborting.');
		exit(0);
	}

	try {
		call(main);
	} catch(e) {
		log('[FATAL ERROR] An error occurred during updating subscriptions:');
		log(sprintf('%s: %s', e.type, e.message));
		log(e.stacktrace[0].context);

		log('Restarting service...');
		init_action('homeproxy', 'stop');
		init_action('homeproxy', 'start');
	}

	release_lock();
}
