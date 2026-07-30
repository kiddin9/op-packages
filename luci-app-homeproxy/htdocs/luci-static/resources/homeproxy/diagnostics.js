/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 配置诊断 helper。
 */

'use strict';
'require baseclass';
'require rpc';

'require homeproxy as hp';

const callConfigDiagnostics = rpc.declare({
	object: 'luci.homeproxy_node_tools',
	method: 'config_diagnostics',
	expect: { '': {} }
});

return baseclass.extend({
	load() {
		return L.resolveDefault(callConfigDiagnostics(), { result: true, items: [] });
	},

	show(diagnostics) {
		return hp.showConfigDiagnostics(diagnostics);
	}
});
