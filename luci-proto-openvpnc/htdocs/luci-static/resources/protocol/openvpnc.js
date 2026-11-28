'use strict';
'require form';
'require fs';
'require network';
'require request';
'require rpc';
'require uci';

network.registerPatternVirtual(/^vpn-.+$/);

function getProfilePath(section_id) {
	return '/etc/openvpnc/profile-%s.ovpn'.format(section_id);
}

function hasProfile(path) {
	return fs.stat(path).then(function(stat) {
		return stat.type === 'file' && stat.size > 0;
	}, function() {
		return false;
	});
}

var writeProfile = rpc.declare({
	object: 'file',
	method: 'write',
	params: [ 'path', 'data', 'mode', 'base64' ],
	reject: true
});

async function uploadProfile(path, file) {
	// Keep the Base64-encoded request within the ubus message size limit.
	if (file.size <= 32 * 1024) {
		var encoded = await new Promise(function(resolve, reject) {
			var reader = new FileReader();
			reader.onload = function() { resolve(reader.result.split(',', 2)[1]); };
			reader.onerror = function() { reject(reader.error); };
			reader.readAsDataURL(file);
		});
		await writeProfile(path, encoded, 384, true); // 0600
		return;
	}

	var data = new FormData();
	data.append('sessionid', rpc.getSessionID());
	data.append('filename', path);
	data.append('filemode', '0600');
	data.append('filedata', file);

	var response = await request.post(L.env.cgi_base + '/cgi-upload', data, { timeout: 120000 });
	var result = response.json();
	if (!response.ok || result.failure)
		throw new Error(result.message || _('Upload failed'));
}

return network.registerProtocol('openvpnc', {
	getI18n: function() {
		return _('OpenVPN Client');
	},

	getIfname: function() {
		return this._ubus('l3_device') || 'vpn-%s'.format(this.sid);
	},

	getOpkgPackage: function() {
		return 'openvpn';
	},

	isFloating: function() {
		return true;
	},

	isVirtual: function() {
		return true;
	},

	getDevices: function() {
		return null;
	},

	containsDevice: function(ifname) {
		return (network.getIfnameOf(ifname) == this.getIfname());
	},

	renderFormOptions: function(s) {
		var o;

		o = s.taboption('general', form.Value, 'profile_revision', _('OpenVPN configuration'));
		o.renderWidget = async function(section_id) {
			var path = getProfilePath(section_id);
			var legacy = uci.get('network', section_id, 'ovpn_file');
			var installed = await hasProfile(path);
			var current = installed ? path : legacy && await hasProfile(legacy) ? legacy : null;
			var status = E('div', { 'role': 'status' }, current
				? _('Current profile: %s').format(current)
				: _('No profile uploaded'));
			var error = E('div', { 'class': 'cbi-value-error', 'role': 'alert' });
			var input = E('input', {
				'id': this.cbid(section_id),
				'type': 'file',
				'accept': '.ovpn',
				'disabled': (this.readonly != null ? this.readonly : this.map.readonly) || null,
				'change': function() { error.textContent = ''; }
			});

			input.profileInstalled = !!current;
			return E('div', {}, [
				status, input, error,
				E('div', { 'class': 'cbi-value-description' },
					_('Choose an .ovpn file with embedded certificates and keys. Save to upload it to %s.').format(path))
			]);
		};
		o.parse = async function(section_id) {
			var input = this.map.findElement('id', this.cbid(section_id));
			if (!input || input.disabled || !this.isActive(section_id))
				return;

			var file = input.files[0];
			var error = input.nextElementSibling;
			try {
				if (!file) {
					if (!input.profileInstalled)
						throw new Error(_('Choose an .ovpn file to upload'));
					return;
				}

				if (!file.size || !/\.ovpn$/i.test(file.name))
					throw new Error(_('Choose a non-empty .ovpn file'));

				await uploadProfile(getProfilePath(section_id), file);

				// netifd must reload even when the profile path stays the same.
				this.map.data.set(this.map.config, section_id, this.option, String(Date.now()));
				this.map.data.unset(this.map.config, section_id, 'ovpn_file');
				error.textContent = '';
			}
			catch (e) {
				error.textContent = e.message;
				throw e;
			}
		};

		o = s.taboption('general', form.Value, 'username', _('Username'),
			_('If your VPN requires a username and password, enter both here. OpenVPN saves them in the interface’s .auth file when it starts.'));
		o.rmempty = true;

		o = s.taboption('general', form.Value, 'password', _('Password'));
		o.password = true;
		o.rmempty = true;

		o = s.taboption('advanced', form.Flag, 'custom_dns_enable', _('Allow custom DNS servers'),
			_('When enabled, the DNS servers entered below will be added to this interface even if the OpenVPN server does not push any DNS settings.'));
		o.rmempty = false;
		o.default = o.disabled;

		o = s.taboption('advanced', form.Value, 'custom_dns', _('Custom DNS servers'),
			_('Enter one or more DNS server addresses separated by spaces or commas, for example: 1.1.1.1,8.8.8.8'));
		o.placeholder = '1.1.1.1 8.8.8.8';
		o.depends('custom_dns_enable', '1');
		o.rmempty = true;

		o = s.taboption('advanced', form.Flag, 'extra_routes_enable', _('Allow extra route networks'),
			_('When enabled, the custom route networks entered below will be appended after the route networks pushed by the OpenVPN server.'));
		o.rmempty = false;
		o.default = o.disabled;

		o = s.taboption('advanced', form.Value, 'extra_routes', _('Extra route networks'),
			_('Enter one or more IPv4 CIDR networks separated by spaces or commas, for example: 10.0.0.0/24,172.16.10.0/24'));
		o.placeholder = '10.0.0.0/24 172.16.10.0/24';
		o.depends('extra_routes_enable', '1');
		o.rmempty = true;

		o = s.taboption('advanced', form.Flag, 'domain_dns_enable', _('Resolve specific domains via custom DNS'),
			_('When enabled, dnsmasq will forward the domains entered below to the custom DNS servers through the generated ovpnc.conf file in its active conf-dir directory.'));
		o.rmempty = false;
		o.default = o.disabled;
		o.depends('custom_dns_enable', '1');

		o = s.taboption('advanced', form.Value, 'dns_domains', _('Domains resolved by custom DNS'),
			_('Enter one or more domains separated by spaces or commas, for example: corp.example.com'));
		o.placeholder = 'corp.example.com';
		o.depends('domain_dns_enable', '1');
		o.rmempty = true;

		o = s.taboption('advanced', form.Value, 'mtu', _('Override MTU'));
		o.placeholder = '1500';
		o.datatype = 'max(9200)';
		o.rmempty = true;
	}
});
