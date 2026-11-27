'use strict';
'require daeuniverse.common as daeu';

return daeu.createConfigFileView(
	function (core) {
		if (core === 'dae') {
			return [
				{
					name: '_subscription',
					path: '/etc/daeuniverse/dae/config.d/subscription.dae',
					title: _('Subscription Configuration (/etc/daeuniverse/dae/config.d/subscription.dae)'),
					rows: 12
				},
				{
					name: '_node',
					path: '/etc/daeuniverse/dae/config.d/node.dae',
					title: _('Node Configuration (/etc/daeuniverse/dae/config.d/node.dae)'),
					rows: 14
				},
				{
					name: '_group',
					path: '/etc/daeuniverse/dae/config.d/group.dae',
					title: _('Group Configuration (/etc/daeuniverse/dae/config.d/group.dae)'),
					rows: 12
				}
			];
		}
		return [
			{
				name: '_node',
				path: '/etc/daeuniverse/honk/config.d/node.dae',
				title: _('Node Configuration (/etc/daeuniverse/honk/config.d/node.dae)'),
				rows: 25
			}
		];
	},
	_('Node Settings'),
	function (core) {
		return (core === 'dae')
			? _('Configure subscriptions, inline nodes, and groups for DAE.')
			: _('Configure nodes, subscriptions, and groups for HONK (/etc/daeuniverse/honk/config.d/node.dae).');
	},
	null,
	_('Node configuration saved and service reloaded.')
);
