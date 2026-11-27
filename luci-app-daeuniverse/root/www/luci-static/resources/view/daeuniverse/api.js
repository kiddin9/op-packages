'use strict';
'require daeuniverse.common as daeu';

return daeu.createConfigFileView(
	function (core) {
		return (core === 'dae')
			? '/etc/daeuniverse/dae/api.dae'
			: '/etc/daeuniverse/honk/config.d/api.dae';
	},
	_('API Settings'),
	function (core) {
		return (core === 'dae')
			? _('Configure API settings for DAE (/etc/daeuniverse/dae/api.dae). Changes require a service restart.')
			: _('Configure Native API settings for HONK (/etc/daeuniverse/honk/config.d/api.dae). Changes require a service restart.');
	},
	_('API Configuration'),
	_('API configuration saved and service restarted.'),
	true,
	{
		renderBanner: function (core) {
			var isDae = (core === 'dae');
			var msg = isDae
				? _('Active core is DAE: uses root api { ... } in /etc/daeuniverse/dae/api.dae, and requires a non-empty secret when config_write is enabled.')
				: _('Active core is HONK: uses experimental { native_api { ... } } in /etc/daeuniverse/honk/config.d/api.dae.');
			return E('div', { 'class': 'alert-message info', 'style': 'margin-bottom: 12px;' }, msg);
		}
	}
);
