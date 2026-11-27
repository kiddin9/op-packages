'use strict';
'require daeuniverse.common as daeu';

return daeu.createConfigFileView(
	function(core) {
		return (core === 'dae')
			? '/etc/daeuniverse/dae/config.d/routing.dae'
			: '/etc/daeuniverse/honk/config.d/route.dae';
	},
	_('Routing Settings'),
	function(core) {
		return (core === 'dae')
			? _('Configure routing rules for DAE (/etc/daeuniverse/dae/config.d/routing.dae).')
			: _('Configure routing rules for HONK (/etc/daeuniverse/honk/config.d/route.dae).');
	},
	_('Route Configuration'),
	_('Routing configuration saved and service reloaded.')
);
