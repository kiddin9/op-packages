'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require tools.widgets as widgets';

return view.extend({
	callHostHints: rpc.declare({
		object: 'luci-rpc',
		method: 'getHostHints',
		expect: { '': {} }
	}),

	callAwake: rpc.declare({
		object: 'luci.wolplus',
		method: 'awake',
		params: ['section'],
		expect: {}
	}),

	load() {
		return Promise.all([
			uci.load('wolplus'),
			L.resolveDefault(this.callHostHints(), {})
		]);
	},

	render(loadResults) {
		const hosts = loadResults[1] || {};
		let m, s, o;

		m = new form.Map('wolplus', _('Wake on LAN +'),
			_('Wake on LAN is a mechanism to remotely boot computers in the local network.') +
			'<br/><br/><a href="https://github.com/sundaqiang/openwrt-packages" target="_blank">Powered by sundaqiang</a>');

		s = m.section(form.GridSection, 'macclient', _('Host Clients'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;

		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(form.Value, 'macaddr', _('MAC Address'));
		o.rmempty = false;
		o.datatype = 'macaddr';
		L.sortedKeys(hosts).forEach(function(mac) {
			const hint = hosts[mac].name ||
				L.toArray(hosts[mac].ipaddrs || hosts[mac].ipv4)[0] ||
				L.toArray(hosts[mac].ip6addrs || hosts[mac].ipv6)[0];
			o.value(mac, hint ? '%s (%s)'.format(mac, hint) : mac);
		});

		o = s.option(widgets.DeviceSelect, 'maceth', _('Network Interface'));
		o.rmempty = false;
		o.noaliases = true;
		o.noinactive = true;

		const gridSection = s;

		s.renderRowActions = L.bind(function(section_id) {
			const defaultButtons = form.GridSection.prototype.renderRowActions.call(gridSection, section_id, _('Edit'));

			const awakeButton = E('button', {
				'class': 'cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function() {
					return this.handleAwake(section_id);
				})
			}, _('Awake'));

			const buttonContainer = defaultButtons.querySelector('div');
			if (buttonContainer)
				buttonContainer.insertBefore(awakeButton, buttonContainer.firstChild);

			return defaultButtons;
		}, this);

		return m.render();
	},

	handleAwake(section_id) {
		const name = uci.get('wolplus', section_id, 'name');
		const mac = uci.get('wolplus', section_id, 'macaddr');

		return this.callAwake(section_id).then(function(res) {
			const raw = (res && res.data) ? res.data : '';
			const ok = !/error|fail|not found|missing/i.test(raw);

			if (ok) {
				ui.addTimeLimitedNotification(null,
					E('p', {}, _('Woke up successfully') + ': ' + (name || mac || section_id)),
					3000, 'info');
			} else {
				ui.showModal(_('Wake up failed'), [
					E('p', {}, (name || mac || section_id)),
					E('pre', {
						'style': 'white-space: pre-wrap; word-break: break-all; max-height: 240px; overflow: auto;'
					}, raw),
					E('div', { 'class': 'right' }, [
						E('button', {
							'class': 'btn cbi-button',
							'click': ui.hideModal
						}, _('Close'))
					])
				]);
			}
		}).catch(function(err) {
			ui.showModal(_('Wake up failed'), [
				E('p', {}, String(err)),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn cbi-button',
						'click': ui.hideModal
					}, _('Close'))
				])
			]);
		});
	}
});
