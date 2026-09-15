/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require form';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

'require homeproxy as hp';
'require tools.widgets as widgets';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

const CBIGenValue = form.Value.extend({
	__name__: 'CBI.GenValue',

	renderWidget(/* ... */) {
		let node = form.Value.prototype.renderWidget.apply(this, arguments);

		if (!this.password)
			node.classList.add('control-group');

		(node.querySelector('.control-group') || node).appendChild(E('button', {
			class: 'cbi-button cbi-button-add',
			title: _('Generate'),
			click: ui.createHandlerFn(this, handleGenKey, this.hp_options || this.option)
		}, [ _('Generate') ]));

		return node;
	}
});

function getServiceStatus() {
	return L.resolveDefault(callServiceList('homeproxy'), {}).then((res) => {
		let isRunning = false;
		try {
			isRunning = res['homeproxy']['instances']['sing-box-s']['running'];
		} catch (e) { }
		return isRunning;
	});
}

function renderStatus(isRunning, version) {
	let spanTemp = '<em><span style="color:%s"><strong>%s (sing-box v%s) %s</strong></span></em>';
	let renderHTML;
	if (isRunning)
		renderHTML = spanTemp.format('green', _('HomeProxy Server'), version, _('RUNNING'));
	else
		renderHTML = spanTemp.format('red', _('HomeProxy Server'), version, _('NOT RUNNING'));

	return renderHTML;
}

function handleGenKey(option) {
	let section_id = this.section.section;
	let type = this.section.getOption('type')?.formvalue(section_id);
	let widget = L.bind((option) => {
		return this.map.findElement('id', 'widget.' + this.cbid(section_id).replace(/\.[^\.]+$/, '.') + option);
	}, this);

	const callSingBoxGenerator = rpc.declare({
		object: 'luci.homeproxy',
		method: 'singbox_generator',
		params: ['type', 'params'],
		expect: { '': {} }
	});

	if (typeof option === 'object') {
		return callSingBoxGenerator(option.type, option.params).then((res) => {
			if (res.result)
				option.callback.call(this, res.result).forEach(([k, v]) => {
					widget(k).value = v ?? '';
				});
			else
				ui.addNotification(null, E('p', _('Failed to generate %s, error: %s.').format(type, res.error)));
		});
	} else {
		let password, required_method;

		if (option === 'uuid')
			required_method = 'uuid';
		else if (type === 'shadowsocks')
			required_method = this.section.getOption('shadowsocks_encrypt_method')?.formvalue(section_id);

		switch (required_method) {
			case 'none':
				password = '';
				break;
			case 'uuid':
				password = hp.generateRand('uuid');
				break;
			default:
				password = hp.generateRand('hex', 16);
				break;
		}
		/* AEAD */
		((length) => {
			if (length && length > 0)
				password = hp.generateRand('base64', length);
		})(hp.shadowsocks_encrypt_length[required_method]);

		return widget(option).value = password;
	}
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('homeproxy'),
			hp.getBuiltinFeatures()
		]);
	},

	render(data) {
		let m, s, o;
		let features = data[1];

		m = new form.Map('homeproxy', _('HomeProxy Server'),
			_('The modern ImmortalWrt proxy platform for ARM64/AMD64.'));

		s = m.section(form.TypedSection);
		s.render = function() {
			poll.add(() => {
				return L.resolveDefault(getServiceStatus()).then((res) => {
					let view = document.getElementById('service_status');
					view.innerHTML = renderStatus(res, features.version);
				});
			});

			return E('div', { class: 'cbi-section', id: 'status_bar' }, [
					E('p', { id: 'service_status' }, _('Collecting data...'))
			]);
		}

		s = m.section(form.NamedSection, 'server', 'homeproxy', _('Global settings'));

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		s = m.section(form.GridSection, 'server', _('Server settings'));
		s.addremove = true;
		s.rowcolors = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.modaltitle = L.bind(hp.loadModalTitle, this, _('Server'), _('Add a server'), data[0]);
		s.sectiontitle = L.bind(hp.loadDefaultLabel, this, data[0]);
		s.renderSectionAdd = L.bind(hp.renderSectionAdd, this, s);

		o = s.option(form.Value, 'label', _('Label'));
		o.load = L.bind(hp.loadDefaultLabel, this, data[0]);
		o.validate = L.bind(hp.validateUniqueValue, this, data[0], 'server', 'label');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = o.enabled;
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Flag, 'firewall', _('Firewall'),
			_('Allow access from the Internet.'));
		o.editable = true;

		o = s.option(form.ListValue, 'type', _('Type'));
		o.value('anytls', _('AnyTLS'));
		o.value('http', _('HTTP'));
		if (features.with_quic) {
			o.value('hysteria', _('Hysteria'));
			o.value('hysteria2', _('Hysteria2'));
			o.value('naive', _('NaïveProxy'));
		}
		o.value('mixed', _('Mixed'));
		o.value('shadowsocks', _('Shadowsocks'));
		o.value('snell', _('Snell (1.14)'));
		o.value('socks', _('Socks'));
		o.value('trojan', _('Trojan'));
		if (features.with_quic)
			o.value('tuic', _('Tuic'));
		o.value('vless', _('VLESS'));
		o.value('vmess', _('VMess'));
		o.rmempty = false;

		o = s.option(form.Value, 'address', _('Listen address'));
		o.placeholder = '::';
		o.datatype = 'ipaddr';
		o.modalonly = true;

		o = s.option(form.Value, 'port', _('Listen port'),
			_('The port must be unique.'));
		o.datatype = 'port';
		o.validate = L.bind(hp.validateUniqueValue, this, data[0], 'server', 'port');

		o = s.option(form.Value, 'username', _('Username'));
		o.depends('type', 'http');
		o.depends('type', 'mixed');
		o.depends('type', 'naive');
		o.depends('type', 'socks');
		o.modalonly = true;

		o = s.option(CBIGenValue, 'password', _('Password'));
		o.password = true;
		o.depends('type', 'anytls');
		o.depends({'type': /^(http|mixed|naive|socks)$/, 'username': /[\s\S]/});
		o.depends('type', 'hysteria2');
		o.depends('type', 'shadowsocks');
		o.depends('type', 'snell');
		o.depends('type', 'trojan');
		o.depends('type', 'tuic');
		o.validate = function(section_id, value) {
			if (section_id) {
				let type = this.section.formvalue(section_id, 'type');
				let required_type = [ 'anytls', 'http', 'mixed', 'naive', 'shadowsocks', 'snell', 'socks', 'trojan' ];

				if (required_type.includes(type)) {
					if (type === 'shadowsocks') {
						let encmode = this.section.formvalue(section_id, 'shadowsocks_encrypt_method');
						if (encmode === 'none')
							return true;
						else if (encmode === '2022-blake3-aes-128-gcm')
							return hp.validateBase64Key(24, section_id, value);
						else if (['2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'].includes(encmode))
							return hp.validateBase64Key(44, section_id, value);
					}

					if (!value)
						return _('Expecting: %s').format(_('non-empty value'));
				}
			}

			return true;
		}
		o.modalonly = true;

		/* AnyTLS config */
		o = s.option(form.DynamicList, 'anytls_padding_scheme', _('Padding scheme'),
			_('AnyTLS padding scheme in array.'));
		o.depends('type', 'anytls');
		o.modalonly = true;

		/* Hysteria (2) config start */
		o = s.option(form.ListValue, 'hysteria_protocol', _('Protocol'));
		o.value('udp');
		/* WeChat-Video / FakeTCP are unsupported by sing-box currently
		   o.value('wechat-video');
		   o.value('faketcp');
		*/
		o.default = 'udp';
		o.depends('type', 'hysteria');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_down_mbps', _('Max download speed'),
			_('Max download speed in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria');
		o.depends('type', 'hysteria2');
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_up_mbps', _('Max upload speed'),
			_('Max upload speed in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria');
		o.depends('type', 'hysteria2');
		o.modalonly = true;

		o = s.option(form.ListValue, 'hysteria_auth_type', _('Authentication type'));
		o.value('', _('Disable'));
		o.value('base64', _('Base64'));
		o.value('string', _('String'));
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_auth_payload', _('Authentication payload'));
		o.password = true;
		o.depends({'type': 'hysteria', 'hysteria_auth_type': /[\s\S]/});
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.ListValue, 'hysteria_obfs_type', _('Obfuscate type'));
		o.value('', _('Disable'));
		o.value('salamander', _('Salamander'));
		o.value('gecko', _('Gecko (1.14)'));
		o.depends('type', 'hysteria2');
		o.modalonly = true;

		o = s.option(CBIGenValue, 'hysteria_obfs_password', _('Obfuscate password'));
		o.password = true;
		o.depends('type', 'hysteria');
		o.depends({'type': 'hysteria2', 'hysteria_obfs_type': /[\s\S]/});
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_obfs_min_packet_size', _('Min obfs packet size (1.14)'),
			_('Minimum on-wire packet size in bytes. Gecko only.'));
		o.datatype = 'uinteger';
		o.placeholder = '512';
		o.depends({'type': 'hysteria2', 'hysteria_obfs_type': 'gecko'});
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_obfs_max_packet_size', _('Max obfs packet size (1.14)'),
			_('Maximum on-wire packet size in bytes. Gecko only.'));
		o.datatype = 'uinteger';
		o.placeholder = '1200';
		o.depends({'type': 'hysteria2', 'hysteria_obfs_type': 'gecko'});
		o.modalonly = true;

		o = s.option(form.Flag, 'hysteria_ignore_client_bandwidth', _('Ignore client bandwidth'),
			_('Tell the client to use the BBR flow control algorithm instead of Hysteria CC.'));
		o.depends({'type': 'hysteria2', 'hysteria_down_mbps': '', 'hysteria_up_mbps': ''});
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_masquerade', _('Masquerade'),
			_('HTTP3 server behavior when authentication fails.<br/>A 404 page will be returned if empty.'));
		o.depends('type', 'hysteria2');
		o.modalonly = true;
		/* Hysteria (2) config end */

		/* Snell config start */
		o = s.option(form.ListValue, 'snell_version', _('Snell version'),
			_('The pre-shared key (password) above must be 12-255 bytes for v6.'));
		o.value('5', _('v5'));
		o.value('6', _('v6'));
		o.default = '5';
		o.depends('type', 'snell');
		o.modalonly = true;

		o = s.option(form.ListValue, 'snell_obfs_mode', _('Obfuscation mode'),
			_('HTTP obfuscation. v5 only.'));
		o.value('', _('none'));
		o.value('http', _('http'));
		o.depends({'type': 'snell', 'snell_version': '5'});
		o.modalonly = true;

		o = s.option(form.ListValue, 'snell_mode', _('Traffic shaping mode'),
			_('v6 only.'));
		o.value('', _('default'));
		o.value('unshaped', _('unshaped'));
		o.value('unsafe-raw', _('unsafe-raw'));
		o.depends({'type': 'snell', 'snell_version': '6'});
		o.modalonly = true;
		/* Snell config end */

		/* Shadowsocks config */
		o = s.option(form.ListValue, 'shadowsocks_encrypt_method', _('Encrypt method'));
		for (let i of hp.shadowsocks_encrypt_methods)
			o.value(i);
		o.default = 'aes-128-gcm';
		o.depends('type', 'shadowsocks');
		o.modalonly = true;

		/* Tuic config start */
		o = s.option(CBIGenValue, 'uuid', _('UUID'));
		o.password = true;
		o.depends('type', 'tuic');
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.validate = hp.validateUUID;
		o.modalonly = true;

		o = s.option(form.ListValue, 'tuic_congestion_control', _('Congestion control algorithm'),
			_('QUIC congestion control algorithm.'));
		o.value('cubic');
		o.value('new_reno');
		o.value('bbr');
		o.default = 'cubic';
		o.depends('type', 'tuic');
		o.modalonly = true;

		o = s.option(form.Value, 'tuic_auth_timeout', _('Auth timeout'),
			_('How long the server should wait for the client to send the authentication command (in seconds).'));
		o.datatype = 'uinteger';
		o.default = '3';
		o.depends('type', 'tuic');
		o.modalonly = true;

		o = s.option(form.Flag, 'tuic_enable_zero_rtt', _('Enable 0-RTT handshake'),
			_('Enable 0-RTT QUIC connection handshake on the client side. This is not impacting much on the performance, as the protocol is fully multiplexed.<br/>' +
				'Disabling this is highly recommended, as it is vulnerable to replay attacks.'));
		o.depends('type', 'tuic');
		o.modalonly = true;

		o = s.option(form.Value, 'tuic_heartbeat', _('Heartbeat interval'),
			_('Interval for sending heartbeat packets for keeping the connection alive (in seconds).'));
		o.datatype = 'uinteger';
		o.default = '10';
		o.depends('type', 'tuic');
		o.modalonly = true;
		/* Tuic config end */

		/* VLESS / VMess config start */
		o = s.option(form.ListValue, 'vless_flow', _('Flow'));
		o.value('', _('None'));
		o.value('xtls-rprx-vision');
		o.depends('type', 'vless');
		o.modalonly = true;

		o = s.option(form.Value, 'vmess_alterid', _('Alter ID'),
			_('Legacy protocol support (VMess MD5 Authentication) is provided for compatibility purposes only, use of alterId > 1 is not recommended.'));
		o.datatype = 'uinteger';
		o.depends('type', 'vmess');
		o.modalonly = true;
		/* VMess config end */

		/* Transport config start */
		hp.renderTransportOptions(s, { features: features, side: 'server' });
		/* Transport config end */

		/* Mux config start */
		o = s.option(form.Flag, 'multiplex', _('Multiplex'));
		o.depends('type', 'shadowsocks');
		o.depends('type', 'trojan');
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.modalonly = true;

		o = s.option(form.Flag, 'multiplex_padding', _('Enable padding'));
		o.depends('multiplex', '1');
		o.modalonly = true;

		if (features.hp_has_tcp_brutal) {
			o = s.option(form.Flag, 'multiplex_brutal', _('Enable TCP Brutal'),
				_('Enable TCP Brutal congestion control algorithm'));
			o.depends('multiplex', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'multiplex_brutal_down', _('Download bandwidth'),
				_('Download bandwidth in Mbps.'));
			o.datatype = 'uinteger';
			o.depends('multiplex_brutal', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'multiplex_brutal_up', _('Upload bandwidth'),
				_('Upload bandwidth in Mbps.'));
			o.datatype = 'uinteger';
			o.depends('multiplex_brutal', '1');
			o.modalonly = true;
		}
		/* Mux config end */

		/* TLS config start */
		hp.renderTlsOptions(s, {
			side: 'server',
			type_depends: [ 'anytls', 'http', 'hysteria', 'hysteria2', 'naive', 'trojan', 'tuic', 'vless', 'vmess' ],
			tls_forced_types: [ 'hysteria', 'hysteria2', 'tuic' ]
		});

		if (features.with_acme) {
			o = s.option(form.Flag, 'tls_acme', _('Enable ACME'),
				_('Use ACME TLS certificate issuer.'));
			o.depends('tls', '1');
			o.modalonly = true;

			o = s.option(form.DynamicList, 'tls_acme_domain', _('Domains'));
			o.datatype = 'hostname';
			o.depends('tls_acme', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_dsn', _('Default server name'),
				_('Server name to use when choosing a certificate if the ClientHello\'s ServerName field is empty.'));
			o.depends('tls_acme', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_email', _('Email'),
				_('The email address to use when creating or selecting an existing ACME server account.'));
			o.depends('tls_acme', '1');
			o.validate = function(section_id, value) {
				if (section_id) {
					if (!value)
						return _('Expecting: %s').format('non-empty value');
					else if (!value.match(/^[^\s@]+@[^\s@]+\.[^\s@]+$/))
						return _('Expecting: %s').format('valid email address');
				}

				return true;
			}
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_key_type', _('ACME key type'),
				_('Private key type for new certificates (1.14). Empty uses the default.'));
			o.value('ed25519');
			o.value('p256');
			o.value('p384');
			o.value('rsa2048');
			o.value('rsa4096');
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_profile', _('ACME profile'),
				_('ACME profile for certificate issuance (1.14). Example: shortlived.'));
			o.placeholder = 'shortlived';
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.TextValue, 'tls_acme_account_key', _('ACME account key'),
				_('PEM-encoded private key of an existing ACME account (1.14).'));
			o.monospace = true;
			o.rows = 3;
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_provider', _('CA provider'),
				_('The ACME CA provider to use.'));
			o.value('letsencrypt', _('Let\'s Encrypt'));
			o.value('zerossl', _('ZeroSSL'));
			o.depends('tls_acme', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Flag, 'tls_dns01_challenge', _('DNS01 challenge'))
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.ListValue, 'tls_dns01_provider', _('DNS provider'));
			o.value('alidns', _('Alibaba Cloud DNS'));
			o.value('cloudflare', _('Cloudflare'));
			o.depends('tls_dns01_challenge', '1');
			o.default = 'cloudflare';
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_dns01_ali_akid', _('Access key ID'));
			o.password = true;
			o.depends('tls_dns01_provider', 'alidns');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_dns01_ali_aksec', _('Access key secret'));
			o.password = true;
			o.depends('tls_dns01_provider', 'alidns');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_dns01_ali_rid', _('Region ID'));
			o.depends('tls_dns01_provider', 'alidns');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_dns01_cf_api_token', _('API token'));
			o.password = true;
			o.depends('tls_dns01_provider', 'cloudflare');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Flag, 'tls_acme_dhc', _('Disable HTTP challenge'));
			o.depends('tls_dns01_challenge', '0');
			o.modalonly = true;

			o = s.option(form.Flag, 'tls_acme_dtac', _('Disable TLS ALPN challenge'));
			o.depends('tls_dns01_challenge', '0');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_ahp', _('Alternative HTTP port'),
				_('The alternate port to use for the ACME HTTP challenge; if non-empty, this port will be used instead of 80 to spin up a listener for the HTTP challenge.'));
			o.datatype = 'port';
			o.depends('tls_dns01_challenge', '0');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_atp', _('Alternative TLS port'),
				_('The alternate port to use for the ACME TLS-ALPN challenge; the system must forward 443 to this port for challenge to succeed.'));
			o.datatype = 'port';
			o.depends('tls_dns01_challenge', '0');
			o.modalonly = true;

			o = s.option(form.Flag, 'tls_acme_external_account', _('External Account Binding'),
				_('EAB (External Account Binding) contains information necessary to bind or map an ACME account to some other account known by the CA.' +
				'<br/>External account bindings are "used to associate an ACME account with an existing account in a non-ACME system, such as a CA customer database.'));
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_ea_keyid', _('External account key ID'));
			o.password = true;
			o.depends('tls_acme_external_account', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_ea_mackey', _('External account MAC key'));
			o.password = true;
			o.depends('tls_acme_external_account', '1');
			o.rmempty = false;
			o.modalonly = true;
		}

		o = s.option(form.Flag, 'tls_reality', _('REALITY'));
		o.depends({'tls': '1', 'tls_acme': '0', 'type': /^(anytls|vless)$/});
		o.depends({'tls': '1', 'tls_acme': null, 'type': /^(anytls|vless)$/});
		o.modalonly = true;

		o = s.option(CBIGenValue, 'tls_reality_private_key', _('REALITY private key'));
		o.password = true;
		o.hp_options = {
			type: 'reality-keypair',
			params: '',
			callback: function(result) {
				return [
					[this.option, result.private_key],
					['tls_reality_public_key', result.public_key]
				]
			}
		}
		o.depends('tls_reality', '1');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'tls_reality_public_key', _('REALITY public key'));
		o.depends('tls_reality', '1');
		o.modalonly = true;

		o = s.option(form.DynamicList, 'tls_reality_short_id', _('REALITY short ID'));
		o.depends('tls_reality', '1');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'tls_reality_max_time_difference', _('Max time difference'),
			_('The maximum time difference between the server and the client.'));
		o.depends('tls_reality', '1');
		o.modalonly = true;

		o = s.option(form.Value, 'tls_reality_server_addr', _('Handshake server address'));
		o.datatype = 'hostname';
		o.depends('tls_reality', '1');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'tls_reality_server_port', _('Handshake server port'));
		o.datatype = 'port';
		o.depends('tls_reality', '1');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'tls_cert_path', _('Certificate path'),
			_('The server public key, in PEM format.'));
		o.value('/etc/homeproxy/certs/server_publickey.pem');
		o.depends({'tls': '1', 'tls_acme': '0', 'tls_reality': null});
		o.depends({'tls': '1', 'tls_acme': '0', 'tls_reality': '0'});
		o.depends({'tls': '1', 'tls_acme': null, 'tls_reality': '0'});
		o.depends({'tls': '1', 'tls_acme': null, 'tls_reality': null});
		o.validate = hp.validateCertificatePath;
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Button, '_upload_cert', _('Upload certificate'),
			_('<strong>Save your configuration before uploading files!</strong>'));
		o.inputstyle = 'action';
		o.inputtitle = _('Upload...');
		o.depends({'tls': '1', 'tls_cert_path': '/etc/homeproxy/certs/server_publickey.pem'});
		o.onclick = L.bind(hp.uploadCertificate, this, _('certificate'), 'server_publickey');
		o.modalonly = true;

		o = s.option(form.Value, 'tls_key_path', _('Key path'),
			_('The server private key, in PEM format.'));
		o.value('/etc/homeproxy/certs/server_privatekey.pem');
		o.depends({'tls': '1', 'tls_acme': '0', 'tls_reality': '0'});
		o.depends({'tls': '1', 'tls_acme': '0', 'tls_reality': null});
		o.depends({'tls': '1', 'tls_acme': null, 'tls_reality': '0'});
		o.depends({'tls': '1', 'tls_acme': null, 'tls_reality': null});
		o.validate = hp.validateCertificatePath;
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Button, '_upload_key', _('Upload key'),
			_('<strong>Save your configuration before uploading files!</strong>'));
		o.inputstyle = 'action';
		o.inputtitle = _('Upload...');
		o.depends({'tls': '1', 'tls_key_path': '/etc/homeproxy/certs/server_privatekey.pem'});
		o.onclick = L.bind(hp.uploadCertificate, this, _('private key'), 'server_privatekey');
		o.modalonly = true;

		o = s.option(form.TextValue, 'tls_ech_key', _('ECH key'));
		o.placeholder = '-----BEGIN ECH KEYS-----\nACBE2+piYBLrOywCbRYU+ZpEkk8keeBlUXbKqLRmQ/68FwBL/g0ARwAAIAAgn8HI\n93RfdV/LaDk+LC9H4h+4WhVBFmWKdhiT3vvpGi8ACAABAAEAAQADABRvdXRlci1z\nbmkuYW55LmRvbWFpbgAA\n-----END ECH KEYS-----';
		o.monospace = true;
		o.cols = 30
		o.rows = 3;
		o.hp_options = {
			type: 'ech-keypair',
			params: '',
			callback: function(result) {
				return [
					[this.option, result.ech_key],
					['tls_ech_config', result.ech_cfg]
				]
			}
		}
		o.renderWidget = function(section_id, option_index, cfgvalue) {
			let node = form.TextValue.prototype.renderWidget.apply(this, arguments);
			const cbid = this.cbid(section_id) + '._outer_sni';

			node.appendChild(E('div',  { 'class': 'control-group' }, [
				E('input', {
					id: cbid,
					class: 'cbi-input-text',
					style: 'width: 10em',
					placeholder: 'outer-sni.any.domain'
				}),
				E('button', {
					class: 'cbi-button cbi-button-add',
					click: ui.createHandlerFn(this, () => {
						this.hp_options.params = document.getElementById(cbid).value;

						return handleGenKey.call(this, this.hp_options);
					})
				}, [ _('Generate') ])
			]));

			return node;
		}
		o.depends('tls', '1');
		o.modalonly = true;

		o = s.option(form.TextValue, 'tls_ech_config', _('ECH config'));
		o.placeholder = '-----BEGIN ECH CONFIGS-----\nAEv+DQBHAAAgACCfwcj3dF91X8toOT4sL0fiH7haFUEWZYp2GJPe++kaLwAIAAEA\nAQABAAMAFG91dGVyLXNuaS5hbnkuZG9tYWluAAA=\n-----END ECH CONFIGS-----';
		o.monospace = true;
		o.cols = 30
		o.rows = 3;
		o.depends('tls', '1');
		o.modalonly = true;
		/* TLS config end */

		/* Extra settings start */
		o = s.option(form.Flag, 'tcp_fast_open', _('TCP fast open'),
			_('Enable tcp fast open for listener.'));
		o.depends({'network': 'udp', '!reverse': true});
		o.modalonly = true;

		o = s.option(form.Flag, 'tcp_multi_path', _('MultiPath TCP'));
		o.depends({'network': 'udp', '!reverse': true});
		o.modalonly = true;

		o = s.option(form.Flag, 'udp_fragment', _('UDP Fragment'),
			_('Enable UDP fragmentation.'));
		o.depends({'network': 'tcp', '!reverse': true});
		o.modalonly = true;

		o = s.option(form.Value, 'udp_timeout', _('UDP NAT expiration time'),
			_('In seconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '300';
		o.depends({'network': 'tcp', '!reverse': true});
		o.modalonly = true;

		o = s.option(form.ListValue, 'network', _('Network'));
		o.value('tcp', _('TCP'));
		o.value('udp', _('UDP'));
		o.value('', _('Both'));
		o.depends('type', 'naive');
		o.depends('type', 'shadowsocks');
		o.modalonly = true;

		o = s.option(widgets.DeviceSelect, 'bind_interface', _('Bind interface'),
			_('The network interface to bind to.'));
		o.multiple = false;
		o.noaliases = true;
		o.modalonly = true;

		o = s.option(form.Flag, 'reuse_addr', _('Reuse address'),
			_('Reuse listener address.'));
		o.modalonly = true;
		/* Extra settings end */

		return m.render();
	}
});
