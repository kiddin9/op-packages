/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 路由节点前端 helper。
 */

'use strict';
'require baseclass';
'require uci';

return baseclass.extend({
	routingNodeName(res) {
		let type = _('Routing node');
		if (res.node === 'urltest')
			type = _('URLTest');
		else if (res.node === 'selector')
			type = _('Selector');

		return String.format('[%s] %s', type, res.label || res['.name']);
	},

	buildRoutingNodeNames(uci_config) {
		let names = {};

		uci.sections(uci_config, 'routing_node', (res) => {
			names[res['.name']] = this.routingNodeName(res);
		});

		return names;
	},

	addSelectableOutbounds(option, uci_config, proxy_nodes, section_id, include_routing_nodes) {
		for (let i in proxy_nodes)
			option.value(i, proxy_nodes[i]);

		if (!include_routing_nodes)
			return;

		uci.sections(uci_config, 'routing_node', (res) => {
			if (res.enabled === '1' && res['.name'] !== section_id)
				option.value(res['.name'], this.routingNodeName(res));
		});
	},

	nodeDisplayName(node_id, proxy_nodes, routing_node_names) {
		return proxy_nodes[node_id] || routing_node_names[node_id] || node_id;
	},

	toArray(value) {
		if (!value)
			return [];
		return Array.isArray(value) ? value : [ value ];
	},

	routingNodeEdges(res) {
		let edges = [];

		if (res.node === 'selector') {
			edges = edges.concat(this.toArray(res.selector_nodes));
			edges = edges.concat(this.toArray(res.selector_default));
		} else if (res.node === 'urltest') {
			edges = edges.concat(this.toArray(res.urltest_nodes));
		} else {
			edges = edges.concat(this.toArray(res.node));
		}

		return edges.concat(this.toArray(res.outbound));
	},

	selectorHasPath(uci_config, start, target, path_cache, seen) {
		if (!start || !target)
			return false;
		if (start === target)
			return true;

		let key = start + '->' + target;
		if (path_cache[key] !== undefined)
			return path_cache[key];

		if (seen[start])
			return false;

		seen[start] = true;

		let found = false;
		uci.sections(uci_config, 'routing_node', (res) => {
			if (found || res['.name'] !== start)
				return;

			if (res.enabled !== '1' || !res.node)
				return;

			for (let node_id of this.routingNodeEdges(res)) {
				if (node_id === target || this.selectorHasPath(uci_config, node_id, target, path_cache, seen)) {
					found = true;
					return;
				}
			}
		});

		path_cache[key] = found;
		return found;
	}
});
