/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 节点正则预览 helper。
 */

'use strict';
'require baseclass';
'require dom';
'require homeproxy as hp';
'require rpc';

const callValidateRegex = rpc.declare({
	object: 'luci.homeproxy_node_tools',
	method: 'validate_regex',
	params: ['pattern'],
	expect: { '': {} }
});

const callPreviewNodeFilter = rpc.declare({
	object: 'luci.homeproxy_node_tools',
	method: 'preview_node_filter',
	params: ['manual_nodes', 'node_filter', 'node_filter_exclude', 'node'],
	expect: { '': {} }
});

return baseclass.extend({
	normalizeNodeList(value) {
		let nodes = [];

		for (let node_id of hp.toArray(value))
			if (node_id && !nodes.includes(node_id))
				nodes.push(node_id);

		return nodes;
	},

	validate(pattern) {
		return L.resolveDefault(callValidateRegex(pattern), { result: false, error: _('Unknown error.') });
	},

	preview(manual_nodes, node_filter, node_filter_exclude, node) {
		return L.resolveDefault(callPreviewNodeFilter(
			manual_nodes,
			node_filter,
			node_filter_exclude,
			node
		), { result: false, error: _('Unknown error.') });
	},

	setPreviewVisible(container, visible) {
		let row = container.closest('.cbi-value');
		if (row)
			row.style.display = visible ? '' : 'none';
	},

	renderPreview(container, res, nodeName) {
		if (!res.result) {
			let message = _('Expecting: %s').format(_('valid regular expression'));
			if (res.error)
				message += ': ' + res.error;

			dom.content(container, E('em', { 'style': 'color: #a33' }, message));
			return;
		}

			let nodes = this.normalizeNodeList(res.nodes);

		if (!nodes.length) {
			dom.content(container, E('em', {}, _('No effective nodes.')));
			return;
		}

		let content = [];
		if (res.truncated)
			content.push(E('div', { 'style': 'color: #a66; margin-bottom: .35em;' },
				_('Only the first %d effective nodes are shown. Narrow the regex to avoid generating an oversized node group.').format(res.max_result_nodes || nodes.length)));
		if (res.scan_truncated)
			content.push(E('div', { 'style': 'color: #a66; margin-bottom: .35em;' },
				_('Regex matching stopped after scanning %d nodes. Narrow the regex or reduce subscription size.').format(res.max_scan_nodes || 0)));

		content.push(E('ul', {
			'style': 'margin: 0; padding-left: 1.4em; max-height: 28em; overflow: auto;'
		}, nodes.map((node_id) => E('li', {
			'title': node_id
		}, nodeName(node_id)))));

		dom.content(container, content);
	}
});
