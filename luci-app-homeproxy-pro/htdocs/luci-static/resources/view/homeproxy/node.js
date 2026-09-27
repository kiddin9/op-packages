/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require form';
'require uci';
'require ui';
'require view';

'require homeproxy as hp';

function allowInsecureConfirm(ev, _section_id, value) {
	if (value === '1' && !confirm(_('Are you sure to allow insecure?')))
		ev.target.firstElementChild.checked = null;
}

function renderNodeSettings(section, data, features, main_node, routing_mode) {
	let s = section, o;
	s.rowcolors = true;
	s.sortable = true;
	s.nodescriptions = true;
	s.modaltitle = L.bind(hp.loadModalTitle, hp, _('Node'), _('Add a node'), 'homeproxy');
	s.sectiontitle = L.bind(hp.loadDefaultLabel, this, 'homeproxy');

	if (routing_mode !== 'custom') {
		o = s.option(form.Button, '_apply', _('Apply'));
		o.editable = true;
		o.modalonly = false;
		o.inputstyle = 'apply';
		o.inputtitle = function(section_id) {
			if (main_node == section_id) {
				this.readonly = true;
				return _('Applied');
			} else {
				this.readonly = false;
				return _('Apply');
			}
		}
		o.onclick = function(ev, section_id) {
			uci.set('homeproxy', 'config', 'main_node', section_id);

			return this.map.save(null, true).then(() => {
				ui.changes.apply(true);
			});
		}
	}

	o = s.option(form.Value, 'label', _('Label'));
	o.load = L.bind(hp.loadDefaultLabel, this, 'homeproxy');
	o.validate = L.bind(hp.validateUniqueValue, this, 'homeproxy', 'node', 'label');
	o.modalonly = true;

	o = hp.renderProtocolOptions(s, { features: features, side: 'client' });

	o = s.option(form.Value, 'address', _('Address'));
	o.datatype = 'host';
	o.depends({'type': 'direct', '!reverse': true});
	o.rmempty = false;

	o = s.option(form.Value, 'port', _('Port'));
	o.datatype = 'port';
	o.depends({'type': 'direct', '!reverse': true});
	o.rmempty = false;

	o = s.option(form.Value, 'username', _('Username'));
	o.depends('type', 'http');
	o.depends('type', 'socks');
	o.depends('type', 'ssh');
	o.modalonly = true;

	o = s.option(form.Value, 'password', _('Password'));
	o.password = true;
	o.depends('type', 'anytls');
	o.depends('type', 'http');
	o.depends('type', 'hysteria2');
	o.depends('type', 'shadowsocks');
	o.depends('type', 'snell');
	o.depends('type', 'ssh');
	o.depends('type', 'trojan');
	o.depends('type', 'tuic');
	o.depends({'type': 'shadowtls', 'shadowtls_version': '2'});
	o.depends({'type': 'shadowtls', 'shadowtls_version': '3'});
	o.depends({'type': 'socks', 'socks_version': '5'});
	o.validate = hp.validatePassword([ 'anytls', 'shadowsocks', 'shadowtls', 'snell', 'trojan' ]);
	o.modalonly = true;

	/* Direct config */
	o = s.option(form.ListValue, 'proxy_protocol', _('Proxy protocol'),
		_('Write proxy protocol in the connection header.'));
	o.value('', _('Disable'));
	o.value('1', _('v1'));
	o.value('2', _('v2'));
	o.depends('type', 'direct');
	o.modalonly = true;

	/* AnyTLS config start */
	o = s.option(form.Value, 'anytls_idle_session_check_interval', _('Idle session check interval'),
		_('Interval checking for idle sessions, in seconds.'));
	o.datatype = 'uinteger';
	o.placeholder = '30';
	o.depends('type', 'anytls');
	o.modalonly = true;

	o = s.option(form.Value, 'anytls_idle_session_timeout', _('Idle session check timeout'),
		_('In the check, close sessions that have been idle for longer than this, in seconds.'));
	o.datatype = 'uinteger';
	o.placeholder = '30';
	o.depends('type', 'anytls');
	o.modalonly = true;

	o = s.option(form.Value, 'anytls_min_idle_session', _('Minimum idle sessions'),
		_('In the check, at least the first <code>n</code> idle sessions are kept open.'));
	o.datatype = 'uinteger';
	o.placeholder = '0';
	o.depends('type', 'anytls');
	o.modalonly = true;
	/* AnyTLS config end */

	/* Hysteria (2) config start */
	o = s.option(form.DynamicList, 'hysteria_hopping_port', _('Hopping port'));
	o.depends('type', 'hysteria');
	o.depends('type', 'hysteria2');
	o.validate = hp.validatePortRange;
	o.modalonly = true;

	o = s.option(form.Value, 'hysteria_hop_interval', _('Hop interval'),
		_('Port hopping interval in seconds.'));
	o.datatype = 'uinteger';
	o.placeholder = '30';
	o.depends({'type': 'hysteria', 'hysteria_hopping_port': /[\s\S]/});
	o.depends({'type': 'hysteria2', 'hysteria_hopping_port': /[\s\S]/});
	o.modalonly = true;

	o = s.option(form.Value, 'hysteria_hop_interval_max', _('Max hop interval (1.14)'),
		_('Maximum port hopping interval in seconds; the actual interval is randomized between the two values. Hysteria2 only.'));
	o.datatype = 'uinteger';
	o.placeholder = '300';
	o.depends({'type': 'hysteria2', 'hysteria_hopping_port': /[\s\S]/});
	o.modalonly = true;

	o = s.option(form.ListValue, 'hysteria_protocol', _('Protocol'));
	o.value('udp');
	/* WeChat-Video / FakeTCP are unsupported by sing-box currently
	 * o.value('wechat-video');
	 * o.value('faketcp');
	 */
	o.default = 'udp';
	o.depends('type', 'hysteria');
	o.rmempty = false;
	o.modalonly = true;

	/* Shared with the server form: the auth/obfs cluster and the bandwidth
	   caps.  They are separate calls because the two forms place them at
	   different points, which is why the order is preserved rather than
	   normalised. */
	hp.renderHysteriaAuthObfs(s, {});
	hp.renderHysteriaBandwidth(s);

	o = s.option(form.ListValue, 'hysteria_bbr_profile', _('BBR profile (1.14)'),
		_('BBR congestion control algorithm profile. Hysteria2 only.'));
	o.value('', _('Standard (default)'));
	o.value('conservative', _('Conservative'));
	o.value('aggressive', _('Aggressive'));
	o.depends('type', 'hysteria2');
	o.modalonly = true;

	o = s.option(form.Flag, 'hysteria_disable_chrome_parrot', _('Disable Chrome QUIC fingerprint (1.14)'),
		_('Disable Chrome QUIC handshake parroting, which is enabled by default since sing-box 1.14. Turn this on only when the server uses an Ed25519 certificate or the handshake otherwise fails.'));
	o.depends('type', 'hysteria2');
	o.modalonly = true;
	/* Hysteria (2) config end */

	/* Shadowsocks config start */
	o = s.option(form.ListValue, 'shadowsocks_encrypt_method', _('Encrypt method'));
	for (let i of hp.shadowsocks_encrypt_methods)
		o.value(i);
	for (let i of hp.shadowsocks_stream_methods)
		o.value(i);
	o.default = 'aes-128-gcm';
	o.depends('type', 'shadowsocks');
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.ListValue, 'shadowsocks_plugin', _('Plugin'));
	o.value('', _('none'));
	o.value('obfs-local');
	o.value('v2ray-plugin');
	o.depends('type', 'shadowsocks');
	o.modalonly = true;

	o = s.option(form.Value, 'shadowsocks_plugin_opts', _('Plugin opts'));
	o.depends('shadowsocks_plugin', 'obfs-local');
	o.depends('shadowsocks_plugin', 'v2ray-plugin');
	o.modalonly = true;
	/* Shadowsocks config end */

	/* ShadowTLS config */
	o = s.option(form.ListValue, 'shadowtls_version', _('ShadowTLS version'));
	o.value('1', _('v1'));
	o.value('2', _('v2'));
	o.value('3', _('v3'));
	o.default = '1';
	o.depends('type', 'shadowtls');
	o.rmempty = false;
	o.modalonly = true;

	/* Socks config */
	o = s.option(form.ListValue, 'socks_version', _('Socks version'));
	o.value('4', _('Socks4'));
	o.value('4a', _('Socks4A'));
	o.value('5', _('Socks5'));
	o.default = '5';
	o.depends('type', 'socks');
	o.rmempty = false;
	o.modalonly = true;

	/* SSH config start */
	o = s.option(form.Value, 'ssh_client_version', _('Client version'),
		_('Random version will be used if empty.'));
	o.depends('type', 'ssh');
	o.modalonly = true;

	o = s.option(form.DynamicList, 'ssh_host_key', _('Host key'),
		_('Accept any if empty.'));
	o.depends('type', 'ssh');
	o.modalonly = true;

	o = s.option(form.DynamicList, 'ssh_host_key_algo', _('Host key algorithms'))
	o.depends('type', 'ssh');
	o.modalonly = true;

	o = s.option(form.DynamicList, 'ssh_priv_key', _('Private key'));
	o.password = true;
	o.depends('type', 'ssh');
	o.modalonly = true;

	o = s.option(form.Value, 'ssh_priv_key_pp', _('Private key passphrase'));
	o.password = true;
	o.depends('type', 'ssh');
	o.modalonly = true;
	/* SSH config end */

	/* TUIC config start */
	hp.renderTuicOptions(s, { side: 'client' });
	/* Tuic config end */

	/* VMess / VLESS config start */
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

	o = s.option(form.ListValue, 'vmess_encrypt', _('Encrypt method'));
	o.value('auto');
	o.value('none');
	o.value('zero');
	o.value('aes-128-gcm');
	o.value('chacha20-poly1305');
	o.default = 'auto';
	o.depends('type', 'vmess');
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Flag, 'vmess_global_padding', _('Global padding'),
		_('Protocol parameter. Will waste traffic randomly if enabled (enabled by default in v2ray and cannot be disabled).'));
	o.default = o.enabled;
	o.depends('type', 'vmess');
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Flag, 'vmess_authenticated_length', _('Authenticated length'),
		_('Protocol parameter. Enable length block encryption.'));
	o.depends('type', 'vmess');
	o.modalonly = true;
	/* VMess config end */

	/* Transport config start */
	hp.renderTransportOptions(s, { features: features, side: 'client' });
	/* Transport config end */

	/* Wireguard config start */
	o = s.option(form.DynamicList, 'wireguard_local_address', _('Local address'),
		_('List of IP (v4 or v6) addresses prefixes to be assigned to the interface.'));
	o.datatype = 'cidr';
	o.depends('type', 'wireguard');
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'wireguard_private_key', _('Private key'),
		_('WireGuard requires base64-encoded private keys.'));
	o.password = true;
	o.depends('type', 'wireguard');
	o.validate = L.bind(hp.validateBase64Key, this, 44);
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'wireguard_peer_public_key', _('Peer pubkic key'),
		_('WireGuard peer public key.'));
	o.depends('type', 'wireguard');
	o.validate = L.bind(hp.validateBase64Key, this, 44);
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'wireguard_pre_shared_key', _('Pre-shared key'),
		_('WireGuard pre-shared key.'));
	o.password = true;
	o.depends('type', 'wireguard');
	o.validate = L.bind(hp.validateBase64Key, this, 44);
	o.modalonly = true;

	o = s.option(form.DynamicList, 'wireguard_reserved', _('Reserved field bytes'));
	o.datatype = 'integer';
	o.depends('type', 'wireguard');
	o.modalonly = true;

	o = s.option(form.Value, 'wireguard_mtu', _('MTU'));
	o.datatype = 'range(0,9000)';
	o.placeholder = '1408';
	o.depends('type', 'wireguard');
	o.modalonly = true;

	o = s.option(form.Value, 'wireguard_persistent_keepalive_interval', _('Persistent keepalive interval'),
		_('In seconds. Disabled by default.'));
	o.datatype = 'uinteger';
	o.depends('type', 'wireguard');
	o.modalonly = true;
	/* Wireguard config end */

	/* Mux config start */
	/* The flag, padding and the TCP Brutal group are shared with the server
	   form; only the dialling knobs below are client-specific. */
	hp.renderMuxOptions(s, { features: features });

	o = s.option(form.ListValue, 'multiplex_protocol', _('Protocol'),
		_('Multiplex protocol.'));
	o.value('h2mux');
	o.value('smux');
	o.value('yamux');
	o.default = 'h2mux';
	o.depends('multiplex', '1');
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'multiplex_max_connections', _('Maximum connections'));
	o.datatype = 'uinteger';
	o.depends('multiplex', '1');
	o.modalonly = true;

	o = s.option(form.Value, 'multiplex_min_streams', _('Minimum streams'),
		_('Minimum multiplexed streams in a connection before opening a new connection.'));
	o.datatype = 'uinteger';
	o.depends('multiplex', '1');
	o.modalonly = true;

	o = s.option(form.Value, 'multiplex_max_streams', _('Maximum streams'),
		_('Maximum multiplexed streams in a connection before opening a new connection.<br/>' +
			'Conflict with <code>%s</code> and <code>%s</code>.').format(
				_('Maximum connections'), _('Minimum streams')));
	o.datatype = 'uinteger';
	o.depends({'multiplex': '1', 'multiplex_max_connections': '', 'multiplex_min_streams': ''});
	o.modalonly = true;

	/* Mux config end */

	/* Snell config start */
	o = s.option(form.ListValue, 'snell_version', _('Snell version'),
		_('sing-box implements Snell v4/v5 wire as v4 and v6. The pre-shared key (Password above) must be 12-255 bytes for v6.'));
	/* {4, 6} is the OUTBOUND's valid set, not a subset someone forgot to
	   finish: sing-box 1.14 rejects version 5 on a snell outbound
	   ("unsupported version: 5") and accepts 4 and 6.  The server form offers
	   {5, 6} because its INBOUND is the mirror image (version 4 is rejected
	   there).  Measured against the target sing-box; see the plan's 2.11. */
	o.value('4', _('v4'));
	o.value('6', _('v6'));
	o.default = '4';
	o.depends('type', 'snell');
	o.modalonly = true;

	o = s.option(form.Value, 'snell_userkey', _('User key'),
		_('Optional; only required when connecting to a multi-user Snell server.'));
	o.depends('type', 'snell');
	o.modalonly = true;

	o = s.option(form.Flag, 'snell_reuse', _('Connection reuse'),
		_('Enable connection reuse (the Snell v2 CONNECT command).'));
	o.depends('type', 'snell');
	o.modalonly = true;

	o = s.option(form.ListValue, 'snell_obfs_mode', _('Obfuscation mode'),
		_('HTTP obfuscation. v4 only.'));
	o.value('', _('none'));
	o.value('http', _('http'));
	o.depends({'type': 'snell', 'snell_version': '4'});
	o.modalonly = true;

	o = s.option(form.Value, 'snell_obfs_host', _('Obfuscation host'),
		_('HTTP Host header sent when obfuscation mode is http. bing.com is used by default.'));
	o.depends({'type': 'snell', 'snell_version': '4', 'snell_obfs_mode': 'http'});
	o.modalonly = true;
	/* Snell config end */

	/* TLS config start */
	hp.renderTlsOptions(s, {
		side: 'client',
		type_depends: [ 'anytls', 'http', 'hysteria', 'hysteria2', 'shadowtls', 'trojan', 'tuic', 'vless', 'vmess' ],
		tls_forced_types: [ 'anytls', 'hysteria', 'hysteria2', 'shadowtls', 'tuic' ],
		oninsecurechange: allowInsecureConfirm
	});

	o = s.option(form.Flag, 'tls_self_sign', _('Append self-signed certificate'),
		_('If you have the root certificate, use this option instead of allowing insecure.'));
	o.depends('tls_insecure', '0');
	o.modalonly = true;

	o = s.option(form.Value, 'tls_cert_path', _('Certificate path'),
		_('The path to the server certificate, in PEM format.'));
	o.value('/etc/homeproxy/certs/client_ca.pem');
	o.depends('tls_self_sign', '1');
	o.validate = hp.validateCertificatePath;
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Button, '_upload_cert', _('Upload certificate'),
		_('<strong>Save your configuration before uploading files!</strong>'));
	o.inputstyle = 'action';
	o.inputtitle = _('Upload...');
	o.depends({'tls_self_sign': '1', 'tls_cert_path': '/etc/homeproxy/certs/client_ca.pem'});
	o.onclick = L.bind(hp.uploadCertificate, hp, _('certificate'), 'client_ca');
	o.modalonly = true;

	o = s.option(form.Flag, 'tls_ech', _('Enable ECH'),
		_('ECH (Encrypted Client Hello) is a TLS extension that allows a client to encrypt the first part of its ClientHello message.'));
	o.depends('tls', '1');
	o.modalonly = true;

	o = s.option(form.Value, 'tls_ech_config_path', _('ECH config path'),
		_('The path to the ECH config, in PEM format. If empty, load from DNS will be attempted.'));
	o.value('/etc/homeproxy/certs/client_ech_conf.pem');
	/* Same policy as cert_path / key_path: sing-box reads this file as root and
	   the backend drops any path outside CERT_PATH_ROOTS (validateCertificatePath
	   in homeproxy.uc). Without it the UI accepted a path the generator then
	   silently discarded. */
	o.validate = hp.validateCertificatePath;
	o.depends('tls_ech', '1');
	o.modalonly = true;

	o = s.option(form.Button, '_upload_ech_config', _('Upload ECH config'),
		_('<strong>Save your configuration before uploading files!</strong>'));
	o.inputstyle = 'action';
	o.inputtitle = _('Upload...');
	o.depends({'tls_ech': '1', 'tls_ech_config_path': '/etc/homeproxy/certs/client_ech_conf.pem'});
	o.onclick = L.bind(hp.uploadCertificate, hp, _('ECH config'), 'client_ech_conf');
	o.modalonly = true;

	if (features.with_utls) {
		o = s.option(form.ListValue, 'tls_utls', _('uTLS fingerprint'),
			_('uTLS is a fork of "crypto/tls", which provides ClientHello fingerprinting resistance.'));
		o.value('', _('Disable'));
		o.value('360');
		o.value('android');
		o.value('chrome');
		o.value('edge');
		o.value('firefox');
		o.value('ios');
		o.value('qq');
		o.value('random');
		o.value('randomized');
		o.value('safari');
		o.depends({'tls': '1', 'type': /^((?!hysteria2?|tuic$).)+$/});
		o.validate = function(section_id, value) {
			if (section_id) {
				let tls_reality = this.map.findElement('id', 'cbid.homeproxy.%s.tls_reality'.format(section_id)).firstElementChild;
				if (tls_reality.checked && !value)
					return _('Expecting: %s').format(_('non-empty value'));

				let vless_flow = this.map.lookupOption('vless_flow', section_id)[0].formvalue(section_id);
				if ((tls_reality.checked || vless_flow) && ['360', 'android'].includes(value))
					return _('Unsupported fingerprint!');
			}

			return true;
		}
		o.modalonly = true;

		o = s.option(form.Flag, 'tls_reality', _('REALITY'));
		o.depends({'tls': '1', 'type': 'anytls'});
		o.depends({'tls': '1', 'type': 'vless'});
		o.modalonly = true;

		o = s.option(form.Value, 'tls_reality_public_key', _('REALITY public key'));
		o.password = true;
		o.depends('tls_reality', '1');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'tls_reality_short_id', _('REALITY short ID'));
		o.password = true;
		o.depends('tls_reality', '1');
		o.modalonly = true;
	}
	/* TLS config end */

	/* Extra settings start */
	o = s.option(form.Flag, 'tcp_fast_open', _('TCP fast open'));
	o.modalonly = true;

	o = s.option(form.Flag, 'tcp_multi_path', _('MultiPath TCP'));
	o.modalonly = true;

	o = s.option(form.Flag, 'udp_fragment', _('UDP Fragment'),
		_('Enable UDP fragmentation.'));
	o.modalonly = true;

	o = s.option(form.Flag, 'udp_over_tcp', _('UDP over TCP'),
		_('Enable the SUoT protocol, requires server support. Conflict with multiplex.'));
	o.depends('type', 'socks');
	o.depends({'type': 'shadowsocks', 'multiplex': '0'});
	o.modalonly = true;

	o = s.option(form.ListValue, 'udp_over_tcp_version', _('SUoT version'));
	o.value('1', _('v1'));
	o.value('2', _('v2'));
	o.default = '2';
	o.depends('udp_over_tcp', '1');
	o.modalonly = true;
	/* Extra settings end */

	return s;
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('homeproxy'),
			hp.getBuiltinFeatures()
		]);
	},

	render(data) {
		let m, s, o, ss, so;
		let main_node = uci.get('homeproxy', 'config', 'main_node');
		let routing_mode = uci.get('homeproxy', 'config', 'routing_mode');
		let features = data[1];

		/* Cache subscription information, it will be called multiple times.
		 * hp.subscriptionInfo() owns the URL parsing, the malformed-escape
		 * fallback and the escaping of the fragment, all three of which used
		 * to be inline here: decodeURIComponent threw on a fragment like
		 * '#100%' and took the whole page render down with it, and the decoded
		 * fragment went unescaped into a tab title. */
		let subinfo = [];
		for (let suburl of (uci.get('homeproxy', 'subscription', 'subscription_url') || [])) {
			const info = hp.subscriptionInfo(suburl);
			if (info)
				subinfo.push(info);
		}

		m = new form.Map('homeproxy', _('Edit nodes'));

		s = m.section(form.NamedSection, 'subscription', 'homeproxy');

		/* Node settings start */
		/* User nodes start */
		s.tab('node', _('Nodes'));
		o = s.taboption('node', form.SectionValue, '_node', form.GridSection, 'node');
		ss = renderNodeSettings(o.subsection, data, features, main_node, routing_mode);
		ss.addremove = true;
		ss.filter = function(section_id) {
			for (let info of subinfo)
				if (info.hash === uci.get('homeproxy', section_id, 'grouphash'))
					return false;

			return true;
		}
		/* Import subscription links start */
		/* Thanks to luci-app-shadowsocks-libev */
		ss.handleLinkImport = function() {
			let textarea = new ui.Textarea();
			ui.showModal(_('Import share links'), [
				E('p', _('Support Hysteria, Shadowsocks, Trojan, v2rayN (VMess), and XTLS (VLESS) online configuration delivery standard.')),
				textarea.render(),
				E('div', { class: 'right' }, [
					E('button', {
						class: 'btn',
						click: ui.hideModal
					}, [ _('Cancel') ]),
					'',
					E('button', {
						class: 'btn cbi-button-action',
						click: ui.createHandlerFn(this, () => {
							let input_links = textarea.getValue().trim().split('\n');
							if (!input_links || !input_links[0])
								return ui.hideModal();

							/* Remove duplicate lines */
							input_links = input_links.reduce((pre, cur) =>
								(!pre.includes(cur) && pre.push(cur), pre), []);

							let allow_insecure = uci.get('homeproxy', 'subscription', 'allow_insecure');
							let packet_encoding = uci.get('homeproxy', 'subscription', 'packet_encoding');

							/* Every link is parsed - and rejected - by the
							 * backend parser (parser/uri.uc), so importing a
							 * link and receiving it through a subscription
							 * can no longer disagree about what it means. */
							return Promise.all(input_links.map((l) => hp.parseShareLink(l)))
								.then((configs) => {
									let imported_node = 0;
									configs.forEach((config) => {
										if (!config)
											return;

										if (config.tls === '1' && allow_insecure === '1')
											config.tls_insecure = '1';
										if (['vless', 'vmess'].includes(config.type))
											config.packet_encoding = packet_encoding;

										let nameHash = hp.calcStringMD5(config.label);
										let sid = uci.add('homeproxy', 'node', nameHash);
										Object.keys(config).forEach((k) => {
											uci.set('homeproxy', sid, k, config[k]);
										});
										imported_node++;
									});

									if (imported_node === 0)
										ui.addNotification(null, E('p', _('No valid share link found.')));
									else
										ui.addNotification(null, E('p', _('Successfully imported %s nodes of total %s.').format(
											imported_node, input_links.length)));

									return uci.save()
										.then(L.bind(this.map.load, this.map))
										.then(L.bind(this.map.reset, this.map))
										.then(ui.hideModal)
										.catch((e) => {
											/* The .catch above used to swallow
											 * every error silently, so a failed
											 * hideModal (L.ui is undefined; this
											 * module imported ui, not L.ui) made
											 * the modal look stuck after a
											 * successful import. Surface it now:
											 * the import itself ran, the modal
											 * just did not close, and the user
											 * deserves to know which. */
											ui.addNotification(null, E('p', e && e.message
												? _('Failed to close the import dialog: %s').format(e.message)
												: _('Imported the nodes, but the dialog did not close automatically. Close it manually.')));
										});
								});
						})
					}, [ _('Import') ])
				])
			])
		}
		/* The shared renderer (homeproxy.js) appends the extra button this
		 * page needs; it used to carry a verbatim copy of the whole method.
		 * The factory gets the section back so the handler binds to it, the
		 * same receiver the copy's `this` had.
		 *
		 * Why a plain wrapper, not L.bind(hp.renderSectionAdd, this, ss, factory):
		 * L.bind forwards its preset args in front of the caller's args, so
		 * the bound function calls hp.renderSectionAdd.call(this, ss, factory,
		 * extra_class) - the factory ends up in the extra_class slot and the
		 * parent's classList.add() then coerces the function source to a
		 * string and throws InvalidCharacterError the moment CBI invokes
		 * renderSectionAdd('cbi-tblsection-create'). Passing them through
		 * in their natural positions (section, extra_class, extra_button)
		 * is the only order that lines up. */
		const importShareLinksFactory = (section) => E('button', {
			'class': 'cbi-button cbi-button-add',
			'title': _('Import share links'),
			'click': ui.createHandlerFn(section, 'handleLinkImport')
		}, [ _('Import share links') ]);
		ss.renderSectionAdd = function(extra_class) {
			return hp.renderSectionAdd(ss, extra_class, importShareLinksFactory);
		};
		/* Import subscription links end */
		/* User nodes end */

		/* Subscription nodes start */
		for (const info of subinfo) {
			s.tab('sub_' + info.hash, _('Sub (%s)').format(info.title));
			o = s.taboption('sub_' + info.hash, form.SectionValue, '_sub_' + info.hash, form.GridSection, 'node');
			ss = renderNodeSettings(o.subsection, data, features, main_node, routing_mode);
			ss.filter = function(section_id) {
				return (uci.get('homeproxy', section_id, 'grouphash') === info.hash);
			}
		}
		/* Subscription nodes end */
		/* Node settings end */

		/* Subscriptions settings start */
		s.tab('subscription', _('Subscriptions'));

		o = s.taboption('subscription', form.Flag, 'auto_update', _('Auto update'),
			_('Auto update subscriptions and geodata.'));
		o.rmempty = false;

		o = s.taboption('subscription', form.ListValue, 'auto_update_time', _('Update time'));
		for (let i = 0; i < 24; i++)
			o.value(i, i + ':00');
		o.default = '2';
		o.depends('auto_update', '1');

		o = s.taboption('subscription', form.Flag, 'update_via_proxy', _('Update via proxy'),
			_('Update subscriptions via proxy.'));
		o.rmempty = false;

		o = s.taboption('subscription', form.DynamicList, 'subscription_url', _('Subscription URL-s'),
			_('Support Hysteria, Shadowsocks, Trojan, v2rayN (VMess), and XTLS (VLESS) online configuration delivery standard.'));
		o.validate = function(section_id, value) {
			if (section_id && value) {
				try {
					let url = new URL(value);
					if (!url.hostname)
						return _('Expecting: %s').format(_('valid URL'));
				}
				catch(e) {
					return _('Expecting: %s').format(_('valid URL'));
				}
			}

			return true;
		}

		o = s.taboption('subscription', form.ListValue, 'filter_nodes', _('Filter nodes'),
			_('Drop/keep specific nodes from subscriptions.'));
		o.value('disabled', _('Disable'));
		o.value('blacklist', _('Blacklist mode'));
		o.value('whitelist', _('Whitelist mode'));
		o.default = 'disabled';
		o.rmempty = false;

		o = s.taboption('subscription', form.DynamicList, 'filter_keywords', _('Filter keywords'),
			_('Drop/keep nodes that contain the specific keywords. <a target="_blank" href="https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_Expressions">Regex</a> is supported.'));
		o.depends({'filter_nodes': 'disabled', '!reverse': true});
		o.rmempty = false;

		o = s.taboption('subscription', form.Value, 'user_agent', _('User-Agent'));
		o.placeholder = 'Wget/1.21 (HomeProxy, like v2rayN)';

		o = s.taboption('subscription', form.Flag, 'allow_insecure', _('Allow insecure'),
			_('Allow insecure connection by default when add nodes from subscriptions.') +
			'<br/>' +
			_('This is <strong>DANGEROUS</strong>, your traffic is almost like <strong>PLAIN TEXT</strong>! Use at your own risk!'));
		o.rmempty = false;
		o.onchange = allowInsecureConfirm;

		o = s.taboption('subscription', form.ListValue, 'packet_encoding', _('Default packet encoding'));
		o.value('', _('none'));
		o.value('packetaddr', _('packet addr (v2ray-core v5+)'));
		o.value('xudp', _('Xudp (Xray-core)'));

		o = s.taboption('subscription', form.Button, '_save_subscriptions', _('Save subscriptions settings'),
			_('NOTE: Save current settings before updating subscriptions.'));
		o.inputstyle = 'apply';
		o.inputtitle = _('Save current settings');
		o.onclick = function() {
			return this.map.save(null, true).then(() => {
				ui.changes.apply(true);
			});
		}

		o = s.taboption('subscription', form.Button, '_update_subscriptions', _('Update nodes from subscriptions'));
		o.inputstyle = 'apply';
		o.inputtitle = function(section_id) {
			let sublist = uci.get('homeproxy', section_id, 'subscription_url') || [];
			if (sublist.length > 0) {
				return _('Update %s subscriptions').format(sublist.length);
			} else {
				this.readonly = true;
				return _('No subscription available')
			}
		}
		o.onclick = function() {
			/* The updater pipeline (wget through a CN -> overseas link,
			   UCI commit, /etc/init.d/homeproxy reload, the 30 s sing-box
			   health gate) takes 5-15 s on a real device, which exceeds
			   the browser XHR timeout. The old synchronous RPC waited
			   for the whole thing inside one XHR; the browser saw
			   "XHR request timed out" while the backend completed
			   cleanly, and the user got a stale page with no signal.

			   The ubus method now spawns the script detached and
			   returns immediately with {result:true, async:true}; we
			   poll update_subscriptions_status (which reads the
			   orchestrator's lock + the last log lines) until the run
			   finishes, then reload. A failure is a status poll that
			   stays in 'running' past the deadline, or a log tail that
			   never recorded the success marker. */
			return hp.rpcCall('update_subscriptions').then((res) => {
				if (res && res.running)
					return ui.addNotification(null, E('p',
						_('Subscription update is already running. This page will reload when the previous run finishes.')));

				if (res && res.result === false)
					return ui.addNotification(null, E('p', [
						_('Could not start subscription update: %s').format(res.error || _('unknown error'))
					]));

				const notification = ui.addNotification(null,
					E('p', _('Updating subscriptions\u2026')));

				/* The status page already drives LuCI's poll-status
				 * indicator via hp.statusPoller(); client/server do
				 * too. The node view polls on demand for a single
				 * click, so it doesn't go through that path - mirror
				 * the same "Refreshing\u2026" pill on the top right
				 * via ui.showIndicator so the user sees the same
				 * affordance on every tab. The hide is in every exit
				 * branch below; without it the indicator would survive
				 * until the next page load. */
				ui.showIndicator('hp-subscriptions',
					_('Updating subscriptions\u2026'));

				const finish = (fn) => {
					ui.hideIndicator('hp-subscriptions');
					return fn();
				};

				/* 90 s is a generous ceiling: even a slow fetch plus a
				   worst-case 60 s rollback restart fits, and a stuck
				   poll past that is worth telling the user about
				   rather than reloading silently. */
				const deadline = Date.now() + 90000;

				const poll = () => hp.rpcCall('update_subscriptions_status').then((s) => {
					if (!s || !s.running) {
						/* Detect a clean run by looking for the
						 * success marker the orchestrator writes at
						 * the very end ("Successfully updated
						 * subscriptions"). A run that ends without
						 * it - the orchestrator's try/catch still
						 * removes the lock - is treated as a
						 * failure so the user sees what went
						 * wrong instead of reloading onto a
						 * silently broken state. */
						const ok = s && s.log_tail &&
							/Successfully updated subscriptions/m.test(s.log_tail);
						return Promise.resolve(notification).then((n) => {
							if (n && typeof n.close === 'function')
								n.close();
							if (ok)
								return finish(() => location.reload());
							return finish(() => ui.addNotification(null, E('p', [
								_('Subscription update did not complete cleanly. Last log:'),
								E('pre', {}, s && s.log_tail ? s.log_tail : _('(empty)'))
							])));
						});
					}
					if (Date.now() > deadline) {
						return Promise.resolve(notification).then((n) => {
							if (n && typeof n.close === 'function')
								n.close();
							return finish(() => ui.addNotification(null, E('p',
								_('Subscription update is taking longer than 90 seconds. Check the log and reload manually.'))));
						});
					}
					return new Promise((resolve) => setTimeout(resolve, 1000)).then(poll);
				}).catch(() => {
					/* A transient RPC failure (ubusd hiccup, etc.)
					 * is not the run failing - keep polling. */
					return new Promise((resolve) => setTimeout(resolve, 1000)).then(poll);
				});

				return poll();
			});
		}

		o = s.taboption('subscription', form.Button, '_remove_subscriptions', _('Remove all nodes from subscriptions'));
		o.inputstyle = 'reset';
		o.inputtitle = function() {
			let subnodes = [];
			uci.sections('homeproxy', 'node', (res) => {
				if (res.grouphash)
					subnodes = subnodes.concat(res['.name'])
			});

			if (subnodes.length > 0) {
				return _('Remove %s nodes').format(subnodes.length);
			} else {
				this.readonly = true;
				return _('No subscription node');
			}
		}
		o.onclick = function() {
			let subnodes = [];
			uci.sections('homeproxy', 'node', (res) => {
				if (res.grouphash)
					subnodes = subnodes.concat(res['.name'])
			});

			for (let i in subnodes)
				uci.remove('homeproxy', subnodes[i]);

			if (subnodes.includes(uci.get('homeproxy', 'config', 'main_node')))
				uci.set('homeproxy', 'config', 'main_node', 'nil');

			if (subnodes.includes(uci.get('homeproxy', 'config', 'main_udp_node')))
				uci.set('homeproxy', 'config', 'main_udp_node', 'nil');

			this.inputtitle = _('%s nodes removed').format(subnodes.length);
			this.readonly = true;

			return this.map.save(null, true);
		}
		/* Subscriptions settings end */

		return m.render();
	}
});
