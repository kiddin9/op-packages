/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 节点正则资源限制 helper。
 */

'use strict';

const NODE_FILTER_MAX_PATTERN_LENGTH = 512;
const NODE_FILTER_MAX_RESULT_NODES = 500;
const NODE_FILTER_MAX_SCAN_NODES = 2000;

function isEmpty(value) {
	return !value || value === 'nil' || (type(value) in ['array', 'object'] && length(value) === 0);
}

function limits() {
	return {
		max_pattern_length: NODE_FILTER_MAX_PATTERN_LENGTH,
		max_result_nodes: NODE_FILTER_MAX_RESULT_NODES,
		max_scan_nodes: NODE_FILTER_MAX_SCAN_NODES
	};
}

function nodeFilterGuard(pattern) {
	let result = { result: true, limits: limits() };

	if (isEmpty(pattern))
		return result;

	if (length(pattern) > NODE_FILTER_MAX_PATTERN_LENGTH)
		return {
			result: false,
			error: sprintf('正则长度超过 %d 字符', NODE_FILTER_MAX_PATTERN_LENGTH),
			limits: limits()
		};

	return result;
}

function normalizeNodeList(value) {
	let nodes = [];

	if (isEmpty(value))
		return nodes;

	if (type(value) !== 'array')
		value = [ value ];

	for (let node_id in value)
		if (!isEmpty(node_id) && !~index(nodes, node_id))
			push(nodes, node_id);

	return nodes;
}

function compilePattern(pattern) {
	let validated = nodeFilterGuard(pattern);

	if (!validated.result)
		return validated;

	if (isEmpty(pattern))
		return {
			result: true,
			pattern: null,
			limits: validated.limits
		};

	try {
		return {
			result: true,
			pattern: regexp(pattern),
			limits: validated.limits
		};
	} catch(e) {
		return {
			result: false,
			error: e.message || sprintf('%s', e),
			limits: validated.limits
		};
	}
}

function previewResult(nodes, meta) {
	return {
		result: true,
		nodes: nodes,
		truncated: meta.truncated,
		scan_truncated: meta.scan_truncated,
		max_result_nodes: meta.max_result_nodes,
		max_scan_nodes: meta.max_scan_nodes
	};
}

function appendUniqueNode(nodes, node_id) {
	if (!isEmpty(node_id) && !~index(nodes, node_id))
		push(nodes, node_id);
}

function appendLimitedNode(nodes, node_id, meta) {
	if (isEmpty(node_id) || ~index(nodes, node_id))
		return;

	if (length(nodes) < meta.max_result_nodes)
		push(nodes, node_id);
	else
		meta.truncated = true;
}

function previewManualNodeAllowed(uci, config, node_id, node_mode) {
	const section_type = uci.get(config, node_id);

	if (section_type === 'node')
		return true;

	if (node_mode === 'selector') {
		if (node_id in ['direct-out', 'block-out'])
			return true;

		if (section_type === 'routing_node' &&
		    uci.get(config, node_id, 'enabled') === '1' &&
		    !isEmpty(uci.get(config, node_id, 'node')))
			return true;
	}

	return false;
}

function filterManualNodeAllowed(ctx, node_id) {
	if (type(ctx.allow_manual_node) === 'function')
		return !!ctx.allow_manual_node(node_id);

	return true;
}

function manualNodeError(ctx, node_id) {
	if (type(ctx.on_invalid_manual_node) === 'function')
		ctx.on_invalid_manual_node(node_id);
}

function labelOfNode(cfg) {
	return cfg.label || cfg['.name'];
}

function scanMatchedNodeIds(ctx, pattern, meta) {
	let matched = [],
	    scanned = 0;

	if (!pattern)
		return matched;

	ctx.uci.foreach(ctx.config, ctx.node_type || 'node', (cfg) => {
		if (scanned >= meta.max_scan_nodes) {
			meta.scan_truncated = true;
			return;
		}

		scanned++;

		if (match(labelOfNode(cfg), pattern))
			push(matched, cfg['.name']);
	});

	return matched;
}

function applyExcludePattern(ctx, nodes, pattern, meta) {
	let exclude_ids = {};

	if (!pattern)
		return nodes;

	for (let node_id in scanMatchedNodeIds(ctx, pattern, meta))
		exclude_ids[node_id] = true;

	return filter(nodes, (node_id) => !exclude_ids[node_id]);
}

function defaultMeta() {
	let guard = nodeFilterGuard(null),
	    guard_limits = guard.limits;

	return {
		truncated: false,
		scan_truncated: false,
		max_result_nodes: guard_limits.max_result_nodes,
		max_scan_nodes: guard_limits.max_scan_nodes
	};
}

export function node_filter_guard(pattern) {
	return nodeFilterGuard(pattern);
};

export function node_filter_compile(pattern) {
	return compilePattern(pattern);
};

export function expand_node_filter(ctx, manual_nodes, node_filter, node_filter_exclude) {
	ctx = ctx || {};

	let include_compiled = compilePattern(node_filter),
	    exclude_compiled = compilePattern(node_filter_exclude),
	    meta = defaultMeta(),
	    nodes = [];

	if (!include_compiled.result)
		return include_compiled;

	if (!exclude_compiled.result)
		return exclude_compiled;

	for (let node_id in normalizeNodeList(manual_nodes)) {
		if (filterManualNodeAllowed(ctx, node_id))
			appendUniqueNode(nodes, node_id);
		else
			manualNodeError(ctx, node_id);
	}

	for (let node_id in scanMatchedNodeIds(ctx, include_compiled.pattern, meta))
		appendLimitedNode(nodes, node_id, meta);

	nodes = applyExcludePattern(ctx, nodes, exclude_compiled.pattern, meta);

	return previewResult(nodes, meta);
};

export function preview_manual_node_allowed(uci, config, node_id, node_mode) {
	return previewManualNodeAllowed(uci, config, node_id, node_mode);
};

export function normalize_node_list(value) {
	return normalizeNodeList(value);
};
