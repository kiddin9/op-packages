/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy outbound tag mapping helpers.
 */

'use strict';

function reserve_tag(used_tags, tag) {
	if (type(tag) === 'string' && tag !== '')
		used_tags[tag] = true;
}

function sanitize_outbound_tag(label) {
	if (type(label) !== 'string')
		return '';

	let tag = '';
	for (let i = 0; i < length(label); i++) {
		let ch = ord(label, i);
		if (ch >= 32 && ch !== 127)
			tag += substr(label, i, 1);
	}

	return tag;
}

function conflicts_outbound_tag(tag, used_tags) {
	return tag in used_tags ||
	       match(tag, /^cfg-.+-out$/) ||
	       match(tag, /^cfg-.+-out-shadowtls$/) ||
	       match(tag, /^cfg-.+-dns$/) ||
	       match(tag, /^cfg-.+-rule$/) ||
	       match(tag, /-out-shadowtls$/);
}

function make_suffixed_outbound_tag(base, section, used_tags) {
	let prefix_len = (length(section) < 6) ? length(section) : 6;

	for (let i = prefix_len; i <= length(section); i++) {
		let tag = base + ' #' + substr(section, 0, i);
		if (!conflicts_outbound_tag(tag, used_tags))
			return tag;
	}

	for (let n = 2; ; n++) {
		let tag = base + ' #' + section + '-' + n;
		if (!conflicts_outbound_tag(tag, used_tags))
			return tag;
	}
}

function sort_outbound_tag_items(items) {
	for (let i = 0; i < length(items); i++) {
		let min = i;

		for (let j = i + 1; j < length(items); j++)
			if (items[j].section < items[min].section)
				min = j;

		if (min !== i) {
			let item = items[i];
			items[i] = items[min];
			items[min] = item;
		}
	}
}

function sectionFallbackTag(section) {
	return 'cfg-' + section + '-out';
}

function shadowtlsFallbackTag(section) {
	return sectionFallbackTag(section) + '-shadowtls';
}

function shadowtlsTagFromOutbound(tag) {
	if (type(tag) !== 'string' || tag === '')
		return tag;

	if (match(tag, /-out$/))
		return tag + '-shadowtls';

	return tag + '-out-shadowtls';
}

function renameTags(value, rename, rename_string) {
	let t = type(value);

	if (t === 'string')
		return (rename_string && value in rename) ? rename[value] : value;

	if (t === 'object') {
		for (let k in value) {
			if (k in ['tag', 'outbound', 'outbounds', 'detour', 'default', 'final', 'download_detour'])
				value[k] = renameTags(value[k], rename, true);
			else
				value[k] = renameTags(value[k], rename, false);
		}
		return value;
	}

	if (t === 'array') {
		for (let i = 0; i < length(value); i++)
			value[i] = renameTags(value[i], rename, rename_string);
		return value;
	}

	return value;
}

function collectStaleTagReferences(value, rename, rename_string, refs) {
	let t = type(value);

	if (t === 'string') {
		if (rename_string && value in rename && rename[value] !== value)
			refs[value] = true;
		return;
	}

	if (t === 'object') {
		for (let k in value)
			collectStaleTagReferences(value[k], rename,
				k in ['tag', 'outbound', 'outbounds', 'detour', 'default', 'final', 'download_detour'],
				refs);
		return;
	}

	if (t === 'array')
		for (let i in value)
			collectStaleTagReferences(i, rename, rename_string, refs);
}

function buildTagRenameMap(tag_map) {
	let rename = {};

	if (type(tag_map) !== 'object')
		return rename;

	for (let section in tag_map) {
		let old_tag = sectionFallbackTag(section),
		    final_tag = tag_map[section];

		rename[old_tag] = final_tag;
		rename[old_tag + '-shadowtls'] = shadowtlsTagFromOutbound(final_tag);
	}

	return rename;
}

function checkUniqueTags(entries, seen, on_duplicate) {
	for (let entry in (entries || [])) {
		let tag = (type(entry) === 'object') ? entry.tag : null;
		if (tag === null)
			continue;

		if (seen[tag] && type(on_duplicate) === 'function')
			on_duplicate(tag);

		seen[tag] = true;
	}
}

export function build_outbound_tag_map(uci) {
	const uciconfig = 'homeproxy';
	let items = [],
	    used_tags = {},
	    tag_map = {};

	const reserved_tags = [
		'GLOBAL', 'any',
		'direct-out', 'block-out', 'main-out', 'main-udp-out',
		'default-dns', 'system-dns', 'main-dns', 'china-dns',
		'dns-in', 'mixed-in', 'redirect-in', 'tproxy-in', 'tun-in',
		'direct-domain', 'proxy-domain', 'geoip-cn', 'geosite-cn', 'geosite-noncn',
		// 旧隐藏测速组的保留占位，避免用户标签或旧配置与保留名冲突；不是运行时测速组。
		'__homeproxy_delay_test__'
	];

	for (let tag in reserved_tags)
		reserve_tag(used_tags, tag);

	uci.foreach(uciconfig, 'dns_server', (cfg) => {
		reserve_tag(used_tags, 'cfg-' + cfg['.name'] + '-dns');
	});

	uci.foreach(uciconfig, 'ruleset', (cfg) => {
		reserve_tag(used_tags, 'cfg-' + cfg['.name'] + '-rule');
	});

	uci.foreach(uciconfig, 'node', (cfg) => {
		push(items, {
			section: cfg['.name'],
			label: cfg.label
		});
	});

	uci.foreach(uciconfig, 'routing_node', (cfg) => {
		if (cfg.enabled === '1' && cfg.node in ['selector', 'urltest'])
			push(items, {
				section: cfg['.name'],
				label: cfg.label
			});
	});

	sort_outbound_tag_items(items);

	for (let item in items) {
		let section = item.section,
		    base = sanitize_outbound_tag(item.label),
		    final_tag;

		if (base === '') {
			final_tag = 'cfg-' + section + '-out';
			reserve_tag(used_tags, final_tag);
			tag_map[section] = final_tag;
			continue;
		}

		final_tag = conflicts_outbound_tag(base, used_tags)
			? make_suffixed_outbound_tag(base, section, used_tags)
			: base;

		reserve_tag(used_tags, final_tag);
		tag_map[section] = final_tag;
	}

	return tag_map;
};

export function get_outbound_tag(tag_map, section) {
	if (type(tag_map) === 'object' && section in tag_map)
		return tag_map[section];

	return sectionFallbackTag(section);
};

export function get_shadowtls_outbound_tag(tag_map, section) {
	return shadowtlsTagFromOutbound(get_outbound_tag(tag_map, section));
};

export function get_fallback_outbound_tag(section) {
	return sectionFallbackTag(section);
};

export function get_fallback_shadowtls_outbound_tag(section) {
	return shadowtlsFallbackTag(section);
};

export function apply_outbound_tag_rename(client_config, tag_map) {
	renameTags(client_config, buildTagRenameMap(tag_map), false);
	return client_config;
};

export function assert_unique_outbound_tags(client_config, on_duplicate) {
	let seen = {};

	checkUniqueTags(client_config?.outbounds, seen, on_duplicate);
	checkUniqueTags(client_config?.endpoints, seen, on_duplicate);

	return true;
};

export function assert_no_stale_outbound_tags(client_config, tag_map, on_stale) {
	let refs = {},
	    rename = buildTagRenameMap(tag_map);

	collectStaleTagReferences(client_config, rename, false, refs);

	for (let tag in keys(refs))
		if (type(on_stale) === 'function')
			on_stale(tag, rename[tag]);

	return true;
};

export function normalize_outbound_target(target, tag_map) {
	if (type(target) !== 'string' || target === '')
		return target;

	if (type(tag_map) === 'object')
		for (let section in tag_map) {
			let final_tag = tag_map[section];
			if (target === final_tag || target === get_fallback_outbound_tag(section))
				return section;
		}

	let matched = match(target, /^cfg-(.+)-out$/);
	return matched ? matched[1] : target;
};
