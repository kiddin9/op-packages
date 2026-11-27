'use strict';
'require daeuniverse.common as daeu';

return daeu.createConfigFileView(
	function(core) {
		return (core === 'dae')
			? '/etc/daeuniverse/dae/config.d/dns.dae'
			: '/etc/daeuniverse/honk/config.d/dns.dae';
	},
	_('DNS Settings'),
	function(core) {
		return (core === 'dae')
			? _('Configure DNS settings for DAE (/etc/daeuniverse/dae/config.d/dns.dae).')
			: _('Configure DNS settings for HONK (/etc/daeuniverse/honk/config.d/dns.dae).');
	},
	_('DNS Configuration'),
	_('DNS configuration saved and service reloaded.')
);
