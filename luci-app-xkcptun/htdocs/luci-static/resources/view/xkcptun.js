'use strict';
'require view';
'require dom';
'require ui';
'require form';
'require rpc';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

function getServiceStatus() {
	return L.resolveDefault(callServiceList('xkcptun'), {}).then(function (res) {
		let status = {
			client: null,
			server: null
		};
		try {
			let instances = res['xkcptun']['instances'];
			if (instances['client'] && instances['client']['running']) {
				status.client = instances['client']['pid'];
			}
			if (instances['server'] && instances['server']['running']) {
				status.server = instances['server']['pid'];
			}
		} catch (e) {}
		return status;
	});
}

function renderStatus(status) {
	let clientHTML = '';
	let serverHTML = '';
	let spanGreen = '<em><span style="color:green"><strong>%s (PID %d)</strong></span></em>';
	let spanRed = '<em><span style="color:grey"><strong>%s</strong></span></em>';

	if (status.client) {
		clientHTML = String.format(spanGreen, _('RUNNING'), status.client);
	} else {
		clientHTML = String.format(spanRed, _('NOT RUNNING'));
	}

	if (status.server) {
		serverHTML = String.format(spanGreen, _('RUNNING'), status.server);
	} else {
		serverHTML = String.format(spanRed, _('NOT RUNNING'));
	}

	return E('div', { class: 'cbi-map' },
		E('fieldset', { class: 'cbi-section' }, [
			E('p', {}, [
				E('strong', {}, _('Client Daemon') + ': '),
				E('span', {}, [clientHTML]),
				E('span', { style: 'margin-left: 20px;' }, [
					E('strong', {}, _('Server Daemon') + ': '),
					E('span', {}, [serverHTML])
				])
			])
		])
	);
}

const modeProfiles = [
	['fast3', 'fast3 (nodelay=1, interval=10ms, resend=2, nc=1)'],
	['fast2', 'fast2 (nodelay=1, interval=10ms, resend=2, nc=0)'],
	['fast', 'fast (nodelay=0, interval=20ms, resend=2, nc=0)'],
	['normal', 'normal (nodelay=0, interval=30ms, resend=2, nc=0)'],
	['manual', _('manual (custom parameters)')]
];

function addCommonAdvancedOptions(s, tabName, isServer) {
	let tab = tabName || 'advanced';
	let o;

	o = s.taboption(tab, form.Value, 'mtu', _('MTU'),
		_('Maximum Transmission Unit for UDP packets. Default is 1350.'));
	o.datatype = 'uinteger';
	o.placeholder = '1350';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'sndwnd', _('Send Window (sndwnd)'),
		_('Send window size (number of packets).'));
	o.datatype = 'uinteger';
	o.placeholder = isServer ? '4096' : '1024';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'rcvwnd', _('Receive Window (rcvwnd)'),
		_('Receive window size (number of packets).'));
	o.datatype = 'uinteger';
	o.placeholder = isServer ? '1024' : '4096';
	o.optional = true;

	o = s.taboption(tab, form.Flag, 'fec', _('Enable FEC (fec)'),
		_('Frame all UDP datagrams with Reed-Solomon FEC header. Default is enabled.'));
	o.default = '1';
	o.rmempty = false;

	o = s.taboption(tab, form.Value, 'datashard', _('Data Shards (FEC)'),
		_('Reed-Solomon erasure coding data shards. Default is 10.'));
	o.datatype = 'uinteger';
	o.placeholder = '10';
	o.optional = true;
	o.depends('fec', '1');

	o = s.taboption(tab, form.Value, 'parityshard', _('Parity Shards (FEC)'),
		_('Reed-Solomon erasure coding parity shards. Default is 3.'));
	o.datatype = 'uinteger';
	o.placeholder = '3';
	o.optional = true;
	o.depends('fec', '1');

	o = s.taboption(tab, form.Value, 'dscp', _('DSCP'),
		_('DSCP IP TOS value (0-63). Default is 0.'));
	o.datatype = 'range(0,63)';
	o.placeholder = '0';
	o.optional = true;

	o = s.taboption(tab, form.Flag, 'lossctrl', _('Loss-Driven AIMD (lossctrl)'),
		_('Enable loss-driven AIMD send window adaptation. Default is disabled.'));
	o.default = '0';
	o.rmempty = false;

	o = s.taboption(tab, form.Value, 'pacing', _('Send Pacing (pacing)'),
		_('Max KCP segments per flush tick to smooth send bursts (0 = off). Default is 0.'));
	o.datatype = 'uinteger';
	o.placeholder = '0';
	o.optional = true;

	o = s.taboption(tab, form.ListValue, 'nodelay', _('No Delay (nodelay)'),
		_('Enable KCP nodelay mode.'));
	o.value('0', '0 (' + _('Disable') + ')');
	o.value('1', '1 (' + _('Enable') + ')');
	o.default = '1';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'interval', _('Internal Interval'),
		_('Internal clock interval in milliseconds (10-5000). Default is 10ms.'));
	o.datatype = 'range(10,5000)';
	o.placeholder = '10';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'resend', _('Fast Resend'),
		_('Fast resend count. 0 = off, 2 = fast resend. Default is 2.'));
	o.datatype = 'uinteger';
	o.placeholder = '2';
	o.optional = true;

	o = s.taboption(tab, form.Flag, 'nc', _('No Congestion Control (nc)'),
		_('Disable congestion window flow control. Default is 1 (disabled).'));
	o.default = '1';
	o.rmempty = false;

	o = s.taboption(tab, form.Value, 'sockbuf', _('Socket Buffer Size'),
		_('UDP socket receive/send buffer size in bytes. Default is 16777216 (16MB).'));
	o.datatype = 'uinteger';
	o.placeholder = '16777216';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'keepalive', _('Keepalive Interval'),
		_('KCP keepalive ping interval in seconds. Default is 10s.'));
	o.datatype = 'uinteger';
	o.placeholder = '10';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'conntimeout', _('Connection Timeout'),
		_('Idle connection timeout in seconds (0 = disable timeout sweep). Default is 60s.'));
	o.datatype = 'uinteger';
	o.placeholder = '60';
	o.optional = true;
}

return view.extend({
	render: function() {
		let m, s, o;

		m = new form.Map('xkcptun', _('xkcptun'),
			_('xkcptun is a high-performance C implementation of kcptun with dynamic destination multi-tunnel unified daemon architecture.'));

		// Status Section
		s = m.section(form.NamedSection, '_status');
		s.anonymous = true;
		s.render = function (section_id) {
			let container = E('div', { id: 'service_status' }, _('Collecting status ...'));
			L.Poll.add(function () {
				return L.resolveDefault(getServiceStatus(), {}).then(function(status) {
					let view = document.getElementById('service_status');
					if (view) {
						dom.content(view, renderStatus(status));
					}
				});
			});

			return container;
		};

		// ===== Client Global Default Settings =====
		s = m.section(form.NamedSection, 'client', 'global', _('Client Global Settings'),
			_('Common connection parameters and KCP profile inherited by all client tunnels.'));
		s.anonymous = false;
		s.addremove = false;

		s.tab('general', _('General Settings'));
		s.tab('advanced', _('Advanced Settings'));

		o = s.taboption('general', form.Value, 'remote_addr', _('Default Server Address'),
			_('Remote xkcptun server IP address or domain name.'));
		o.datatype = 'host';
		o.placeholder = '1.2.3.4';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'remote_port', _('Default Server Port'),
			_('Remote xkcptun server UDP listen port.'));
		o.datatype = 'port';
		o.placeholder = '9089';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'key', _('Pre-Shared Key'),
			_('Pre-shared key for HMAC-SHA256 dynamic target authentication. Must match the server.'));
		o.password = true;
		o.placeholder = "it's a secret";
		o.optional = true;

		o = s.taboption('general', form.ListValue, 'mode', _('Mode Profile'),
			_('KCP performance tuning profile.'));
		for (let i = 0; i < modeProfiles.length; i++) {
			o.value(modeProfiles[i][0], modeProfiles[i][1]);
		}
		o.default = 'fast3';

		addCommonAdvancedOptions(s, 'advanced', false);

		// ===== Client Tunnels =====
		s = m.section(form.GridSection, 'client', _('Client Tunnels'),
			_('Configure local client listening ports and dynamic backend target ports. All tunnels share the single unified client daemon.'));
		s.anonymous = false;
		s.addremove = true;
		s.sortable = true;
		s.addbtntitle = _('Add Client Tunnel');

		s.tab('general', _('General Settings'));
		s.tab('advanced', _('Advanced Overrides'));

		// Overview Columns in table
		o = s.option(form.Flag, 'disabled', _('Enabled'));
		o.enabled = '0';
		o.disabled = '1';
		o.default = '0';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Value, 'name', _('Tunnel Name'));
		o.modalonly = false;
		o.placeholder = _('(Auto)');

		o = s.option(form.ListValue, 'proto', _('Protocol'));
		o.value('tcp', 'TCP');
		o.value('udp', 'UDP');
		o.default = 'tcp';
		o.modalonly = false;

		o = s.option(form.Value, 'local_port', _('Local Port'));
		o.modalonly = false;
		o.placeholder = '9088';

		o = s.option(form.Value, 'target_port', _('Target Port'));
		o.modalonly = false;
		o.placeholder = '22';

		o = s.option(form.Value, 'target_addr', _('Target Host'));
		o.modalonly = false;
		o.placeholder = '127.0.0.1';

		// Modal / Tab: General Settings
		o = s.taboption('general', form.Flag, 'disabled', _('Enable Tunnel'));
		o.enabled = '0';
		o.disabled = '1';
		o.default = '0';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'name', _('Tunnel Name / Alias'),
			_('Optional descriptive name for this tunnel (e.g. ssh_tunnel, web_proxy).'));
		o.placeholder = 'my_tunnel';
		o.optional = true;
		o.modalonly = true;

		o = s.taboption('general', form.ListValue, 'proto', _('Tunnel Protocol'),
			_('Protocol to tunnel: TCP (standard KCP stream) or UDP (direct low-latency datagram forwarding, e.g. for DNS).'));
		o.value('tcp', 'TCP (TCP-over-KCP)');
		o.value('udp', 'UDP (Direct UDP Datagram)');
		o.default = 'tcp';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'local_interface', _('Local Interface'),
			_('Network interface to bind (default: br-lan).'));
		o.placeholder = 'br-lan';
		o.default = 'br-lan';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'local_port', _('Local Listen Port'),
			_('Local port to listen for incoming application traffic (e.g. 9088).'));
		o.datatype = 'port';
		o.placeholder = '9088';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'target_port', _('Dynamic Target Port'),
			_('Target port on the server to forward traffic to (e.g. 22, 53, 80, 443).'));
		o.datatype = 'port';
		o.placeholder = '22';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'target_addr', _('Dynamic Target Host'),
			_('Target host on the server to connect/forward to (default: 127.0.0.1).'));
		o.datatype = 'host';
		o.placeholder = '127.0.0.1';
		o.default = '127.0.0.1';
		o.optional = true;
		o.modalonly = true;

		// Modal / Tab: Advanced Overrides (Optional)
		o = s.taboption('advanced', form.Value, 'remote_addr', _('Override Server Address'),
			_('Override remote server address for this specific tunnel (defaults to global).'));
		o.datatype = 'host';
		o.placeholder = _('(Inherit from Global)');
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'remote_port', _('Override Server Port'),
			_('Override remote server port for this specific tunnel (defaults to global).'));
		o.datatype = 'port';
		o.placeholder = _('(Inherit from Global)');
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'key', _('Override Pre-Shared Key'),
			_('Override pre-shared authentication key for this specific tunnel (defaults to global).'));
		o.password = true;
		o.placeholder = _('(Inherit from Global)');
		o.optional = true;

		// ===== Server Global Settings (Dynamic Gateway) =====
		s = m.section(form.NamedSection, 'server', 'global', _('Server Global Settings (Dynamic Gateway)'),
			_('Unified xkcptun server dynamic gateway. The server listens on a single UDP port and dynamically routes each client tunnel to its requested backend target.'));
		s.anonymous = false;
		s.addremove = false;

		s.tab('general', _('General Settings'));
		s.tab('advanced', _('Advanced Settings'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enable Server Daemon'),
			_('Enable unified xkcptun server dynamic gateway daemon.'));
		o.enabled = '1';
		o.disabled = '0';
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'local_interface', _('Listen Interface'),
			_('Network interface to bind (e.g. eth0, br-lan, wan).'));
		o.placeholder = 'eth0';
		o.default = 'eth0';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'local_port', _('Listen Port (UDP)'),
			_('UDP port to listen for incoming client KCP connections (default: 9089).'));
		o.datatype = 'port';
		o.placeholder = '9089';
		o.default = '9089';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'key', _('Pre-Shared Key'),
			_('Pre-shared key for dynamic gateway authentication. Clients must present a valid HMAC token generated with this key.'));
		o.password = true;
		o.placeholder = "it's a secret";
		o.optional = true;

		o = s.taboption('general', form.ListValue, 'mode', _('Mode Profile'),
			_('KCP performance tuning profile.'));
		for (let i = 0; i < modeProfiles.length; i++) {
			o.value(modeProfiles[i][0], modeProfiles[i][1]);
		}
		o.default = 'fast3';

		addCommonAdvancedOptions(s, 'advanced', true);

		// ===== Server Fallback Tunnels (Optional) =====
		s = m.section(form.GridSection, 'server', _('Server Fallback Tunnels (Optional)'),
			_('Optional fallback static target rules for legacy clients that do not send dynamic destination headers. Modern dynamic clients do not require any server tunnels configured here.'));
		s.anonymous = false;
		s.addremove = true;
		s.sortable = true;
		s.addbtntitle = _('Add Fallback Tunnel');

		s.tab('general', _('General Settings'));
		s.tab('advanced', _('Advanced Settings'));

		// Overview Columns in table
		o = s.option(form.Flag, 'disabled', _('Enabled'));
		o.enabled = '0';
		o.disabled = '1';
		o.default = '0';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Value, 'name', _('Tunnel Name'));
		o.modalonly = false;
		o.placeholder = _('(Auto)');

		o = s.option(form.Value, 'local_interface', _('Interface'));
		o.modalonly = false;
		o.placeholder = 'eth0';

		o = s.option(form.Value, 'local_port', _('Listen Port'));
		o.modalonly = false;
		o.placeholder = '9089';

		o = s.option(form.Value, 'remote_addr', _('Fallback Target Host'));
		o.modalonly = false;
		o.placeholder = '127.0.0.1';

		o = s.option(form.Value, 'remote_port', _('Fallback Target Port'));
		o.modalonly = false;
		o.placeholder = '443';

		o = s.option(form.ListValue, 'mode', _('Mode'));
		o.modalonly = false;
		for (let i = 0; i < modeProfiles.length; i++) {
			o.value(modeProfiles[i][0], modeProfiles[i][0]);
		}

		o = s.option(form.Flag, 'fec', _('FEC'));
		o.modalonly = false;
		o.default = '0';
		o.editable = true;

		// Modal / Tab: General Settings
		o = s.taboption('general', form.Flag, 'disabled', _('Enable Tunnel'));
		o.enabled = '0';
		o.disabled = '1';
		o.default = '0';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'name', _('Tunnel Name / Alias'),
			_('Optional descriptive name for this tunnel (e.g. main_srv).'));
		o.placeholder = 'srv_tunnel';
		o.optional = true;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'local_interface', _('Local Interface'),
			_('Network interface to bind (e.g. eth0, br-lan, wan).'));
		o.placeholder = 'eth0';
		o.default = 'eth0';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'local_port', _('Local Listen Port (UDP)'),
			_('UDP port to listen for incoming KCP connections from clients.'));
		o.datatype = 'port';
		o.placeholder = '9089';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'remote_addr', _('Fallback Target Host'),
			_('Default target host if client did not specify a dynamic destination (default: 127.0.0.1).'));
		o.datatype = 'host';
		o.default = '127.0.0.1';
		o.placeholder = '127.0.0.1';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'remote_port', _('Fallback Target Port'),
			_('Default target port if client did not specify a dynamic destination (e.g. 443, 22).'));
		o.datatype = 'port';
		o.placeholder = '443';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.ListValue, 'mode', _('Mode Profile'),
			_('KCP performance tuning profile.'));
		for (let i = 0; i < modeProfiles.length; i++) {
			o.value(modeProfiles[i][0], modeProfiles[i][1]);
		}
		o.default = 'fast3';
		o.modalonly = true;

		addCommonAdvancedOptions(s, 'advanced', true);

		return m.render();
	}
});
