'use strict';

function isEmpty(value) {
	return !value || value === 'nil' || (type(value) in ['array', 'object'] && length(value) === 0);
}

function toArray(value) {
	if (type(value) === 'array')
		return value;
	else if (isEmpty(value))
		return [];

	return [ value ];
}

function removeListValue(uci, config, section, option, value) {
	let values = toArray(uci.get(config, section, option)),
	    filtered = [];

	for (let item in values)
		if (item !== value)
			push(filtered, item);

	if (length(filtered))
		uci.set(config, section, option, filtered);
	else if (length(values))
		uci.delete(config, section, option);
}

function addReference(refs, entry) {
	push(refs, entry);
}

function addCleanupChange(changes, node_id, scope, section, option, action, value) {
	push(changes, {
		node_id: node_id,
		scope: scope,
		section: section,
		option: option,
		action: action,
		value: value
	});
}

function normalizeUniqueNodeIds(node_ids) {
	let seen = {},
	    unique_ids = [];

	if (type(node_ids) !== 'array')
		return unique_ids;

	for (let node_id in node_ids)
		if (!seen[node_id] && !isEmpty(node_id)) {
			seen[node_id] = true;
			push(unique_ids, node_id);
		}

	return unique_ids;
}

export function collect_node_references(uci, config, node_id) {
	let refs = [];

	if (isEmpty(node_id))
		return refs;

	if (uci.get(config, 'config', 'main_node') === node_id)
		addReference(refs, {
			scope: 'main_node',
			section: 'config',
			option: 'main_node',
			label: 'Main node'
		});

	if (uci.get(config, 'config', 'main_udp_node') === node_id)
		addReference(refs, {
			scope: 'main_udp_node',
			section: 'config',
			option: 'main_udp_node',
			label: 'Main UDP node'
		});

	if (~index(toArray(uci.get(config, 'config', 'main_urltest_nodes')), node_id))
		addReference(refs, {
			scope: 'main_urltest_nodes',
			section: 'config',
			option: 'main_urltest_nodes',
			label: 'Main node / URLTest nodes'
		});

	if (~index(toArray(uci.get(config, 'config', 'main_udp_urltest_nodes')), node_id))
		addReference(refs, {
			scope: 'main_udp_urltest_nodes',
			section: 'config',
			option: 'main_udp_urltest_nodes',
			label: 'Main UDP node / URLTest nodes'
		});

	if (uci.get(config, 'routing', 'default_outbound') === node_id)
		addReference(refs, {
			scope: 'default_outbound',
			section: 'routing',
			option: 'default_outbound',
			label: 'Routing / Default outbound'
		});

	uci.foreach(config, 'routing_node', (cfg) => {
		const section = cfg['.name'],
		      label = cfg.label || section;

		if (uci.get(config, section, 'node') === node_id)
			addReference(refs, {
				scope: 'routing_node_node',
				section: section,
				option: 'node',
				label: sprintf('Routing Nodes / %s / Node', label)
			});

		if (uci.get(config, section, 'outbound') === node_id)
			addReference(refs, {
				scope: 'routing_node_outbound',
				section: section,
				option: 'outbound',
				label: sprintf('Routing Nodes / %s / Outbound', label)
			});

		if (uci.get(config, section, 'selector_default') === node_id)
			addReference(refs, {
				scope: 'routing_node_selector_default',
				section: section,
				option: 'selector_default',
				label: sprintf('Routing Nodes / %s / Default', label)
			});

		if (~index(toArray(uci.get(config, section, 'urltest_nodes')), node_id))
			addReference(refs, {
				scope: 'routing_node_urltest_nodes',
				section: section,
				option: 'urltest_nodes',
				label: sprintf('Routing Nodes / %s / URLTest nodes', label)
			});

		if (~index(toArray(uci.get(config, section, 'selector_nodes')), node_id))
			addReference(refs, {
				scope: 'routing_node_selector_nodes',
				section: section,
				option: 'selector_nodes',
				label: sprintf('Routing Nodes / %s / Selector nodes', label)
			});
	});

	uci.foreach(config, 'routing_rule', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id)
			addReference(refs, {
				scope: 'routing_rule_outbound',
				section: cfg['.name'],
				option: 'outbound',
				label: sprintf('Routing Rules / %s / Outbound', cfg.label || cfg['.name'])
			});
	});

	uci.foreach(config, 'dns_server', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id)
			addReference(refs, {
				scope: 'dns_server_outbound',
				section: cfg['.name'],
				option: 'outbound',
				label: sprintf('DNS Server / %s / Outbound', cfg.label || cfg['.name'])
			});
	});

	uci.foreach(config, 'dns_rule', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id)
			addReference(refs, {
				scope: 'dns_rule_outbound',
				section: cfg['.name'],
				option: 'outbound',
				label: sprintf('DNS Rules / %s / Outbound', cfg.label || cfg['.name'])
			});
	});

	uci.foreach(config, 'ruleset', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id)
			addReference(refs, {
				scope: 'ruleset_outbound',
				section: cfg['.name'],
				option: 'outbound',
				label: sprintf('Rule set / %s / Outbound', cfg.label || cfg['.name'])
			});
	});

	return refs;
};

export function cleanup_node_references_for_delete(uci, config, node_id, opts) {
	opts = opts || {};

	if (isEmpty(node_id))
		return { changed: false, changes: [] };

	let changed = false,
	    changes = [],
	    main_node_fallback = isEmpty(opts.main_node_fallback) ? 'nil' : opts.main_node_fallback,
	    main_udp_fallback = isEmpty(opts.main_udp_fallback) ? 'same' : opts.main_udp_fallback;

	if (uci.get(config, 'config', 'main_node') === node_id) {
		uci.set(config, 'config', 'main_node', main_node_fallback);
		addCleanupChange(changes, node_id, 'main_node', 'config', 'main_node', 'set', main_node_fallback);
		changed = true;
	}

	if (uci.get(config, 'config', 'main_udp_node') === node_id) {
		uci.set(config, 'config', 'main_udp_node', main_udp_fallback);
		addCleanupChange(changes, node_id, 'main_udp_node', 'config', 'main_udp_node', 'set', main_udp_fallback);
		changed = true;
	}

	let before_main_urltest = length(toArray(uci.get(config, 'config', 'main_urltest_nodes')));
	removeListValue(uci, config, 'config', 'main_urltest_nodes', node_id);
	if (length(toArray(uci.get(config, 'config', 'main_urltest_nodes'))) !== before_main_urltest) {
		addCleanupChange(changes, node_id, 'main_urltest_nodes', 'config', 'main_urltest_nodes', 'remove', null);
		changed = true;
	}
	if (uci.get(config, 'config', 'main_node') === 'urltest' &&
	    !length(toArray(uci.get(config, 'config', 'main_urltest_nodes')))) {
		uci.set(config, 'config', 'main_node', main_node_fallback);
		addCleanupChange(changes, node_id, 'main_node', 'config', 'main_node', 'set', main_node_fallback);
		changed = true;
	}

	let before_main_udp_urltest = length(toArray(uci.get(config, 'config', 'main_udp_urltest_nodes')));
	removeListValue(uci, config, 'config', 'main_udp_urltest_nodes', node_id);
	if (length(toArray(uci.get(config, 'config', 'main_udp_urltest_nodes'))) !== before_main_udp_urltest) {
		addCleanupChange(changes, node_id, 'main_udp_urltest_nodes', 'config', 'main_udp_urltest_nodes', 'remove', null);
		changed = true;
	}
	if (uci.get(config, 'config', 'main_udp_node') === 'urltest' &&
	    !length(toArray(uci.get(config, 'config', 'main_udp_urltest_nodes')))) {
		uci.set(config, 'config', 'main_udp_node', main_udp_fallback);
		addCleanupChange(changes, node_id, 'main_udp_node', 'config', 'main_udp_node', 'set', main_udp_fallback);
		changed = true;
	}

	if (uci.get(config, 'routing', 'default_outbound') === node_id) {
		uci.set(config, 'routing', 'default_outbound', 'nil');
		addCleanupChange(changes, node_id, 'default_outbound', 'routing', 'default_outbound', 'set', 'nil');
		changed = true;
	}

	uci.foreach(config, 'routing_node', (cfg) => {
		const section = cfg['.name'];

		if (uci.get(config, section, 'node') === node_id) {
			uci.delete(config, section, 'node');
			addCleanupChange(changes, node_id, 'routing_node_node', section, 'node', 'delete', null);
			changed = true;
		}

		if (uci.get(config, section, 'outbound') === node_id) {
			uci.delete(config, section, 'outbound');
			addCleanupChange(changes, node_id, 'routing_node_outbound', section, 'outbound', 'delete', null);
			changed = true;
		}

		if (uci.get(config, section, 'selector_default') === node_id) {
			uci.delete(config, section, 'selector_default');
			addCleanupChange(changes, node_id, 'routing_node_selector_default', section, 'selector_default', 'delete', null);
			changed = true;
		}

		let before_urltest = length(toArray(uci.get(config, section, 'urltest_nodes')));
		removeListValue(uci, config, section, 'urltest_nodes', node_id);
		if (length(toArray(uci.get(config, section, 'urltest_nodes'))) !== before_urltest) {
			addCleanupChange(changes, node_id, 'routing_node_urltest_nodes', section, 'urltest_nodes', 'remove', null);
			changed = true;
		}

		let before_selector = length(toArray(uci.get(config, section, 'selector_nodes')));
		removeListValue(uci, config, section, 'selector_nodes', node_id);
		if (length(toArray(uci.get(config, section, 'selector_nodes'))) !== before_selector) {
			addCleanupChange(changes, node_id, 'routing_node_selector_nodes', section, 'selector_nodes', 'remove', null);
			changed = true;
		}
	});

	uci.foreach(config, 'routing_rule', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id) {
			uci.set(config, cfg['.name'], 'outbound', 'block-out');
			addCleanupChange(changes, node_id, 'routing_rule_outbound', cfg['.name'], 'outbound', 'set', 'block-out');
			changed = true;
		}
	});

	uci.foreach(config, 'dns_server', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id) {
			uci.set(config, cfg['.name'], 'outbound', 'block-out');
			addCleanupChange(changes, node_id, 'dns_server_outbound', cfg['.name'], 'outbound', 'set', 'block-out');
			changed = true;
		}
	});

	uci.foreach(config, 'dns_rule', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id) {
			uci.set(config, cfg['.name'], 'outbound', 'block-out');
			addCleanupChange(changes, node_id, 'dns_rule_outbound', cfg['.name'], 'outbound', 'set', 'block-out');
			changed = true;
		}
	});

	uci.foreach(config, 'ruleset', (cfg) => {
		if (uci.get(config, cfg['.name'], 'outbound') === node_id) {
			uci.set(config, cfg['.name'], 'outbound', 'block-out');
			addCleanupChange(changes, node_id, 'ruleset_outbound', cfg['.name'], 'outbound', 'set', 'block-out');
			changed = true;
		}
	});

	return {
		changed: changed,
		changes: changes,
		main_node_fallback: main_node_fallback,
		main_udp_fallback: main_udp_fallback
	};
};

export function remove_subscription_nodes(uci, config, node_ids, opts) {
	opts = opts || {};

	let unique_ids = normalizeUniqueNodeIds(node_ids),
	    removed = 0,
	    changed = false,
	    changes = [],
	    main_node_fallback = isEmpty(opts.main_node_fallback) ? 'nil' : opts.main_node_fallback,
	    main_udp_fallback = isEmpty(opts.main_udp_fallback) ? 'same' : opts.main_udp_fallback;

	for (let node_id in unique_ids) {
		let cfg = uci.get_all(config, node_id);
		if (!cfg || cfg['.type'] !== 'node' || isEmpty(cfg.grouphash))
			continue;

		const cleanup = cleanup_node_references_for_delete(uci, config, node_id, {
			main_node_fallback: main_node_fallback,
			main_udp_fallback: main_udp_fallback
		});
		if (cleanup.changed) {
			changed = true;
			for (let item in cleanup.changes)
				push(changes, item);
		}

		uci.delete(config, node_id);
		removed++;
	}

	return {
		changed: changed,
		removed: removed,
		changes: changes,
		main_node_fallback: main_node_fallback,
		main_udp_fallback: main_udp_fallback
	};
};
