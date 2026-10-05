/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';
'require rpc';
'require uci';
'require ui';

/* Shared wording for the TLS / transport form blocks. Keeping the strings here
   makes node.js and server.js consume a single definition instead of two
   copies that have to be edited in lockstep. */
const TRANSPORT_NONE_HINT = _('No TCP transport, plain HTTP is merged into the HTTP transport.');
const TRANSPORT_HTTP_HINT = _('TLS is not enforced. If TLS is not configured, plain HTTP 1.1 is used.');
const TRANSPORT_QUIC_HINT = _('No additional encryption support: It\'s basically duplicate encryption.');

const HTTP_IDLE_HEALTH_CHECK_HINT = _('Specifies the period of time (in seconds) after which a health check will be performed using a ping frame if no frames have been received on the connection.<br/>' +
	'Please note that a ping response is considered a received frame, so if there is no other traffic on the connection, the health check will be executed every interval.');
const HTTP_IDLE_GOAWAY_HINT = _('Specifies the time (in seconds) until idle clients should be closed with a GOAWAY frame. PING frames are not considered as activity.');
const HTTP_IDLE_KEEPALIVE_HINT = _('If the transport doesn\'t see any activity after a duration of this time (in seconds), it pings the client to check if the connection is still active.');

const HTTP_PING_HEALTH_CHECK_HINT = _('Specifies the timeout duration (in seconds) after sending a PING frame, within which a response must be received.<br/>' +
	'If a response to the PING frame is not received within the specified timeout duration, the connection will be closed.');
const HTTP_PING_KEEPALIVE_HINT = _('The timeout (in seconds) that after performing a keepalive check, the client will wait for activity. If no activity is detected, the connection will be closed.');

/* Certificates the backend lets sing-box read. This list mirrors
   CERT_PATH_ROOTS in /etc/homeproxy-pro/scripts/homeproxy-pro.uc, and
   tests/arch-guard.sh guard 29 fails when the two drift apart: a path the UI
   accepted but the backend dropped made certificate_path null silently, so the
   TLS listener failed with nothing pointing at the path. */
const HP_CERT_PATH_ROOTS = [ '/etc/homeproxy-pro/certs/', '/etc/acme/', '/etc/ssl/' ];

/* Rule-set source files: a `type: local` rule-set's `path` and a `type: remote`
   one's `initial_path`. This list mirrors RULE_PATH_ROOTS in
   /etc/homeproxy-pro/scripts/homeproxy-pro.uc, and tests/arch-guard.sh guard 50 fails
   when the two drift apart - the same lock guard 29 puts on the certificate
   list, for the same reason: the UI's check is only UX, UCI can be set from
   anywhere on the LAN, and a path the UI accepted but the backend dropped made
   the field vanish from the generated configuration with nothing pointing at
   the path.

   It is deliberately a single root, and deliberately narrower than the
   general HP_DIR-shaped gate the backend also has: a rule-set belongs in the
   archive, which the package creates at install time
   (/etc/uci-defaults/luci-homeproxy-pro) and before every generation
   (runtime/service.sh's hp_prepare_ruleset_dir). */
const HP_RULE_PATH_ROOTS = [ '/etc/homeproxy-pro/ruleset/' ];

/* The archive path offered as the datalist entry on the rule-set path fields,
   so the default the backend expects is one click away instead of something
   the user has to know. Kept as its own constant so the placeholder, the
   datalist and the validator's message all quote the same directory - a
   placeholder that named a path the validator then refused would be its own
   small version of the bug this list exists to prevent. */
const HP_RULE_PATH_DEFAULT = '/etc/homeproxy-pro/ruleset/example.srs';

/* Methods whose failure has already been reported, so that a polled call
   cannot repeat the same notification every few seconds. */
const rpc_warned = new Set();

/* RFC 1321 section 3.4's two per-round tables, for calcStringMD5() below.
 *
 * Both are derived constants, so they are built once here rather than per
 * call: the node view hashes every subscription URL on every render.
 *
 *   MD5_S - the per-operation left-rotation amounts.
 *   MD5_K - floor(abs(sin(i + 1)) * 2^32), the standard way to spell the
 *           table without transcribing 64 magic numbers. */
const MD5_S = [
	7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
	5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
	4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
	6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

const MD5_K = new Uint32Array(64);
for (let i = 0; i < 64; i++)
	MD5_K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296);

return baseclass.extend({
	/* The archive path the rule-set form offers as its datalist entry and
	   placeholder. Exported rather than left module-local so the view quotes
	   this one string instead of repeating the path: a placeholder naming a
	   directory the validator then refuses is its own small version of the
	   drift guard 50 exists to catch, and the placeholder is exactly what a
	   user copies. */
	rule_path_default: HP_RULE_PATH_DEFAULT,

	dns_strategy: {
		'': _('Default'),
		'prefer_ipv4': _('Prefer IPv4'),
		'prefer_ipv6': _('Prefer IPv6'),
		'ipv4_only': _('IPv4 only'),
		'ipv6_only': _('IPv6 only')
	},

	shadowsocks_encrypt_length: {
		/* AEAD */
		'aes-128-gcm': 0,
		'aes-192-gcm': 0,
		'aes-256-gcm': 0,
		'chacha20-ietf-poly1305': 0,
		'xchacha20-ietf-poly1305': 0,
		/* AEAD 2022 */
		'2022-blake3-aes-128-gcm': 16,
		'2022-blake3-aes-256-gcm': 32,
		'2022-blake3-chacha20-poly1305': 32
	},

	shadowsocks_encrypt_methods: [
		/* Stream */
		'none',
		/* AEAD */
		'aes-128-gcm',
		'aes-192-gcm',
		'aes-256-gcm',
		'chacha20-ietf-poly1305',
		'xchacha20-ietf-poly1305',
		/* AEAD 2022 */
		'2022-blake3-aes-128-gcm',
		'2022-blake3-aes-256-gcm',
		'2022-blake3-chacha20-poly1305'
	],

	/* Legacy stream ciphers.  Every entry here was checked against the target
	   `sing-box 1.14.1` with `sing-box check`; `chacha20` (the non-IETF
	   variant) is NOT in the list because sing-box rejects it outright
	   ("unknown method: chacha20") - offering it let a user pick a method
	   that made the generated configuration fail to validate.  The IETF
	   variant is accepted and is kept.
	   The server form does not offer these; that asymmetry is deliberate:
	   it is data here rather than two hand-maintained lists, so changing it
	   is one line rather than a hunt for a second copy. */
	shadowsocks_stream_methods: [
		'aes-128-ctr',
		'aes-192-ctr',
		'aes-256-ctr',
		'aes-128-cfb',
		'aes-192-cfb',
		'aes-256-cfb',
		'chacha20-ietf',
		'rc4-md5'
	],

	/* Single source of truth for the protocol surface the forms offer.
	   `sides` says which form lists the protocol, `feature` names the
	   capability that gates it (an array means every entry must be present).
	   The ORDER matters: filtering this table by side has to reproduce the
	   order the forms used to hard-code, so adding an entry changes the form.
	   Every `type` here must exist in the backend's parser/mapping.uc
	   PROTOCOL_TO_UCI table - tests/i18n-coverage.py's sibling check
	   tests/frontend-protocol-inventory.js enforces it.
	   `shadowtls` is client-only on purpose: the backend models the inbound
	   side (INBOUND_CREDENTIALS, REQUIRED_INBOUND_CREDENTIALS) but the inbound
	   generation path has no fixture/golden coverage yet, so the server form
	   must not offer it until that coverage exists. */
	protocols: [
		{ type: 'direct',      label: _('Direct'),        sides: ['client'] },
		{ type: 'anytls',      label: _('AnyTLS'),        sides: ['client', 'server'] },
		{ type: 'http',        label: _('HTTP'),          sides: ['client', 'server'] },
		{ type: 'hysteria',    label: _('Hysteria'),      sides: ['client', 'server'], feature: 'with_quic' },
		{ type: 'hysteria2',   label: _('Hysteria2'),     sides: ['client', 'server'], feature: 'with_quic' },
		{ type: 'naive',       label: _('NaïveProxy'),    sides: ['server'],           feature: 'with_quic' },
		{ type: 'mixed',       label: _('Mixed'),         sides: ['server'] },
		{ type: 'shadowsocks', label: _('Shadowsocks'),   sides: ['client', 'server'] },
		{ type: 'shadowtls',   label: _('ShadowTLS'),     sides: ['client'] },
		{ type: 'snell',       label: _('Snell (1.14)'),  sides: ['client', 'server'] },
		{ type: 'socks',       label: _('Socks'),         sides: ['client', 'server'] },
		{ type: 'ssh',         label: _('SSH'),           sides: ['client'] },
		{ type: 'trojan',      label: _('Trojan'),        sides: ['client', 'server'] },
		{ type: 'tuic',        label: _('Tuic'),          sides: ['client', 'server'], feature: 'with_quic' },
		{ type: 'wireguard',   label: _('WireGuard'),     sides: ['client'],           feature: ['with_wireguard', 'with_gvisor'] },
		{ type: 'vless',       label: _('VLESS'),         sides: ['client', 'server'] },
		{ type: 'vmess',       label: _('VMess'),         sides: ['client', 'server'] }	],

	/* Multiplexing is configured the same way on both sides: the flag and its
	   dependency set, padding, and the TCP Brutal group.  The client form adds
	   its dialling knobs (protocol, connection/stream limits) separately - the
	   adapter's inbound multiplex deliberately has no such fields.
	   The Brutal group is gated on the capability for BOTH sides; the node form
	   used to build it unconditionally, so a sing-box without TCP Brutal still
	   showed the option.  `features` therefore has to be passed in. */
	renderMuxOptions(section, options) {
		const features = options.features || {};
		let o;

		o = section.option(form.Flag, 'multiplex', _('Multiplex'));
		o.depends('type', 'shadowsocks');
		o.depends('type', 'trojan');
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.modalonly = true;

		o = section.option(form.Flag, 'multiplex_padding', _('Enable padding'));
		o.depends('multiplex', '1');
		o.modalonly = true;

		if (!features.hp_has_tcp_brutal)
			return;

		o = section.option(form.Flag, 'multiplex_brutal', _('Enable TCP Brutal'),
			_('Enable TCP Brutal congestion control algorithm'));
		o.depends('multiplex', '1');
		o.modalonly = true;

		o = section.option(form.Value, 'multiplex_brutal_down', _('Download bandwidth'),
			_('Download bandwidth in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('multiplex_brutal', '1');
		o.modalonly = true;

		o = section.option(form.Value, 'multiplex_brutal_up', _('Upload bandwidth'),
			_('Upload bandwidth in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('multiplex_brutal', '1');
		o.modalonly = true;
	},

	/* The password field's validator, shared by both forms.
	 *
	 * `required_types` is genuinely per-side (the two forms offer different
	 * protocols, and the server only shows the field when a user name is set),
	 * so it stays at the call site.  What must not differ is the 2022 check:
	 * the server form validated that a 2022-blake3 key has the base64 length
	 * sing-box insists on, the node form did not - so a client could save a key
	 * that makes the generated configuration fail to decode ("decode key:
	 * illegal base64 data"), which only shows up when generation runs. */
	validatePassword(required_types) {
		const self = this;

		return function(section_id, value) {
			if (section_id) {
				const type = this.section.formvalue(section_id, 'type');

				if (required_types.includes(type)) {
					if (type === 'shadowsocks') {
						const encmode = this.section.formvalue(section_id, 'shadowsocks_encrypt_method');

						if (encmode === 'none')
							return true;
						else if (encmode === '2022-blake3-aes-128-gcm')
							return self.validateBase64Key(24, section_id, value);
						else if (['2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'].includes(encmode))
							return self.validateBase64Key(44, section_id, value);
					}

					if (!value)
						return _('Expecting: %s').format(_('non-empty value'));
				}
			}

			return true;
		};
	},

	/* Hysteria's bandwidth caps.  A separate renderer because the two forms
	   place the pair at different points in the section; calling it where each
	   form used to declare them preserves both option orders exactly. */
	renderHysteriaBandwidth(section) {
		let o;

		o = section.option(form.Value, 'hysteria_down_mbps', _('Max download speed'),
			_('Max download speed in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria');
		o.depends('type', 'hysteria2');
		o.modalonly = true;

		o = section.option(form.Value, 'hysteria_up_mbps', _('Max upload speed'),
			_('Max upload speed in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria');
		o.depends('type', 'hysteria2');
		o.modalonly = true;
	},

	/* Hysteria's authentication and obfuscation options, contiguous in both
	   forms.  The obfuscate-password widget is the one asymmetry - the server
	   can generate one - so it is passed in, exactly like the TUIC UUID. */
	renderHysteriaAuthObfs(section, options) {
		const obfsPasswordWidget = options.obfsPasswordWidget || form.Value;
		let o;

		o = section.option(form.ListValue, 'hysteria_auth_type', _('Authentication type'));
		o.value('', _('Disable'));
		o.value('base64', _('Base64'));
		o.value('string', _('String'));
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = section.option(form.Value, 'hysteria_auth_payload', _('Authentication payload'));
		o.password = true;
		o.depends({'type': 'hysteria', 'hysteria_auth_type': /[\s\S]/});
		o.rmempty = false;
		o.modalonly = true;

		o = section.option(form.ListValue, 'hysteria_obfs_type', _('Obfuscate type'));
		o.value('', _('Disable'));
		o.value('salamander', _('Salamander'));
		o.value('gecko', _('Gecko (1.14)'));
		o.depends('type', 'hysteria2');
		o.modalonly = true;

		o = section.option(obfsPasswordWidget, 'hysteria_obfs_password', _('Obfuscate password'));
		o.password = true;
		o.depends('type', 'hysteria');
		o.depends({'type': 'hysteria2', 'hysteria_obfs_type': /[\s\S]/});
		o.modalonly = true;

		o = section.option(form.Value, 'hysteria_obfs_min_packet_size', _('Min obfs packet size (1.14)'),
			_('Minimum on-wire packet size in bytes. Gecko only.'));
		o.datatype = 'uinteger';
		o.placeholder = '512';
		o.depends({'type': 'hysteria2', 'hysteria_obfs_type': 'gecko'});
		o.modalonly = true;

		o = section.option(form.Value, 'hysteria_obfs_max_packet_size', _('Max obfs packet size (1.14)'),
			_('Maximum on-wire packet size in bytes. Gecko only.'));
		o.datatype = 'uinteger';
		o.placeholder = '1200';
		o.depends({'type': 'hysteria2', 'hysteria_obfs_type': 'gecko'});
		o.modalonly = true;
	},

	/* TUIC.  Both sides share the congestion control, the 0-RTT flag and the
	   heartbeat; the client adds its dialling knobs (UDP relay mode, UDP over
	   stream) and the server its auth timeout.  The UUID widget is the one real
	   asymmetry - the server can mint one, the client has to be handed one - so
	   it is passed in rather than duplicated (`options.uuidWidget`, defaulting
	   to a plain value field).  Emitting in this order reproduces both forms'
	   previous option order exactly. */
	renderTuicOptions(section, options) {
		const side = options.side || 'client';
		const uuidWidget = options.uuidWidget || form.Value;
		let o;

		o = section.option(uuidWidget, 'uuid', _('UUID'));
		o.password = true;
		o.depends('type', 'tuic');
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.validate = this.validateUUID;
		o.modalonly = true;

		/* The labels are shared: the server form used to show the raw values
		   ('cubic', 'new_reno', 'bbr') for the same option the node form
		   labelled CUBIC / New Reno / BBR, which is the kind of drift a single
		   definition prevents. */
		o = section.option(form.ListValue, 'tuic_congestion_control', _('Congestion control algorithm'),
			_('QUIC congestion control algorithm.'));
		o.value('cubic', _('CUBIC'));
		o.value('new_reno', _('New Reno'));
		o.value('bbr', _('BBR'));
		o.default = 'cubic';
		o.depends('type', 'tuic');
		o.rmempty = false;
		o.modalonly = true;

		if (side === 'client') {
			o = section.option(form.ListValue, 'tuic_udp_relay_mode', _('UDP relay mode'),
				_('UDP packet relay mode.'));
			o.value('', _('Default'));
			o.value('native', _('Native'));
			o.value('quic', _('QUIC'));
			o.depends('type', 'tuic');
			o.modalonly = true;

			o = section.option(form.Flag, 'tuic_udp_over_stream', _('UDP over stream'),
				_('This is the TUIC port of the UDP over TCP protocol, designed to provide a QUIC stream based UDP relay mode that TUIC does not provide.'));
			o.depends({'type': 'tuic', 'tuic_udp_relay_mode': ''});
			o.modalonly = true;
		}
		else {
			o = section.option(form.Value, 'tuic_auth_timeout', _('Auth timeout'),
				_('How long the server should wait for the client to send the authentication command (in seconds).'));
			o.datatype = 'uinteger';
			o.default = '3';
			o.depends('type', 'tuic');
			o.modalonly = true;
		}

		o = section.option(form.Flag, 'tuic_enable_zero_rtt', _('Enable 0-RTT handshake'),
			_('Enable 0-RTT QUIC connection handshake on the client side. This is not impacting much on the performance, as the protocol is fully multiplexed.<br/>' +
				'Disabling this is highly recommended, as it is vulnerable to replay attacks.'));
		o.depends('type', 'tuic');
		o.modalonly = true;

		o = section.option(form.Value, 'tuic_heartbeat', _('Heartbeat interval'),
			_('Interval for sending heartbeat packets for keeping the connection alive (in seconds).'));
		o.datatype = 'uinteger';
		o.default = '10';
		o.depends('type', 'tuic');
		o.modalonly = true;
	},

	/* Render the protocol picker from `protocols`.  This is what keeps the
	   two forms from drifting: they used to carry a hand-written value list
	   each, which is how `snell` ended up with a complete form block (and a
	   place in the credential lists) but no way to select it. */
	/* The view-level status poll, registered exactly once.
	 *
	 * The "registered" flag is module state shared by every render of a view:
	 * without it each re-render added another poll handler and LuCI keeps them
	 * all, so every UCI write scheduled one more. The flag used to live in
	 * client.js and server.js separately - two copies of the same state, free
	 * to drift.
	 *
	 * It takes its collaborators as arguments and returns the registrar, so
	 * "exactly once" can be asserted without a DOM or a browser. The form
	 * snapshots never reach this code at all, which is why it was left alone
	 * until there was something that could fail.
	 *
	 * paint() owns its element lookup: by the time the promise settles LuCI
	 * may have swapped the DOM, and getElementById returns null then. */
	statusPoller(options) {
		const poll = options.poll;
		const read = options.read;
		const paint = options.paint;
		let registered = false;

		return function registerStatusPoll() {
			if (registered)
				return false;

			registered = true;
			poll.add(function () {
				return read().then(paint);
			});

			return true;
		};
	},

	/* The service status has three states, not two.
	 *
	 * `null` means the status query did not come back - rpcCall() resolves to
	 * its fallback when the call fails. Treating that as "not running" painted
	 * the status bar red NOT RUNNING, which is indistinguishable from the
	 * service genuinely being down. The strings live inside _() here so the
	 * translation scanner sees the literals; a helper that returned a key for
	 * the caller to translate would drop out of the template, which is the
	 * trap the protocol labels fell into. */
	statusLabel(isRunning) {
		if (isRunning === true)
			return { color: 'green', text: _('RUNNING') };
		if (isRunning === false)
			return { color: 'red', text: _('NOT RUNNING') };

		return { color: '#b8860b', text: _('STATUS UNKNOWN') };
	},

	/* Which protocol entries to offer for one side.
	 *
	 * The feature map comes from the singbox_get_features RPC, and rpcCall()
	 * resolves to `{}` when that call does not come back. Filtering on an
	 * empty map hides every feature-gated protocol (hysteria, hysteria2,
	 * naive, tuic, wireguard), so a node already saved as one of them renders
	 * with no matching Select option - and the next Save & Apply rewrites its
	 * `type` to whatever happens to be first in the list, silently changing
	 * the node's protocol.
	 *
	 * An empty map therefore means "features unknown", not "no features", and
	 * nothing is filtered. Kept as a pure function so this can be asserted
	 * without a browser: the form harness always supplies the full feature
	 * map, which is why the faulty path was never reached by a test. */
	protocolChoices(side, features) {
		const known = features && Object.keys(features).length > 0;
		const out = [];

		for (const p of this.protocols) {
			if (p.sides.indexOf(side) === -1)
				continue;

			if (known) {
				if (typeof p.feature === 'string' && !features[p.feature])
					continue;
				if (Array.isArray(p.feature) && !p.feature.every(f => features[f]))
					continue;
			}

			out.push(p);
		}

		return out;
	},

	renderProtocolOptions(section, options) {
		const side = options.side || 'client';
		const o = section.option(form.ListValue, 'type', _('Type'));

		for (const p of this.protocolChoices(side, options.features))
			o.value(p.type, p.label);

		o.rmempty = false;

		return o;
	},

	tls_cipher_suites: [
		'TLS_RSA_WITH_AES_128_CBC_SHA',
		'TLS_RSA_WITH_AES_256_CBC_SHA',
		'TLS_RSA_WITH_AES_128_GCM_SHA256',
		'TLS_RSA_WITH_AES_256_GCM_SHA384',
		'TLS_AES_128_GCM_SHA256',
		'TLS_AES_256_GCM_SHA384',
		'TLS_CHACHA20_POLY1305_SHA256',
		'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA',
		'TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA',
		'TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA',
		'TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA',
		'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256',
		'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384',
		'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256',
		'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384',
		'TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256',
		'TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256'
	],

	tls_versions: [
		'1.0',
		'1.1',
		'1.2',
		'1.3'
	],

	CBIStaticList: form.DynamicList.extend({
		__name__: 'CBI.StaticList',

		renderWidget: function(/* ... */) {
			let dl = form.DynamicList.prototype.renderWidget.apply(this, arguments);
			dl.querySelector('.add-item ul > li[data-value="-"]')?.remove();
			return dl;
		}
	}),

	/* Build the transport option group shared by the node (client) and server
	   forms. `options.side` selects the client/server wording and the handful of
	   fields that only exist on one side; option names, defaults and dependency
	   sets are otherwise identical. */
	renderTransportOptions(section, options) {
		const features = options.features || {},
		      side = options.side || 'client';
		let o;

		o = section.option(form.ListValue, 'transport', _('Transport'), TRANSPORT_NONE_HINT);
		o.value('', _('None'));
		o.value('grpc', _('gRPC'));
		o.value('http', _('HTTP'));
		o.value('httpupgrade', _('HTTPUpgrade'));
		o.value('quic', _('QUIC'));
		o.value('ws', _('WebSocket'));
		o.depends('type', 'trojan');
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.onchange = function(ev, section_id, value) {
			let desc = this.map.findElement('id', 'cbid.homeproxy-pro.%s.transport'.format(section_id)).nextElementSibling;
			if (value === 'http')
				desc.innerHTML = TRANSPORT_HTTP_HINT;
			else if (value === 'quic')
				desc.innerHTML = TRANSPORT_QUIC_HINT;
			else
				desc.innerHTML = TRANSPORT_NONE_HINT;

			let tls = this.map.findElement('id', 'cbid.homeproxy-pro.%s.tls'.format(section_id)).firstElementChild;
			if ((value === 'http' && tls.checked) || (value === 'grpc' && !features.with_grpc)) {
				this.map.findElement('id', 'cbid.homeproxy-pro.%s.http_idle_timeout'.format(section_id)).nextElementSibling.innerHTML =
					(side === 'server') ? HTTP_IDLE_GOAWAY_HINT : HTTP_IDLE_HEALTH_CHECK_HINT;

				if (side !== 'server')
					this.map.findElement('id', 'cbid.homeproxy-pro.%s.http_ping_timeout'.format(section_id)).nextElementSibling.innerHTML =
						HTTP_PING_HEALTH_CHECK_HINT;
			} else if (value === 'grpc' && features.with_grpc) {
				this.map.findElement('id', 'cbid.homeproxy-pro.%s.http_idle_timeout'.format(section_id)).nextElementSibling.innerHTML =
					HTTP_IDLE_KEEPALIVE_HINT;

				if (side !== 'server')
					this.map.findElement('id', 'cbid.homeproxy-pro.%s.http_ping_timeout'.format(section_id)).nextElementSibling.innerHTML =
						HTTP_PING_KEEPALIVE_HINT;
			}
		}
		o.modalonly = true;

		o = section.option(form.Value, 'grpc_servicename', _('gRPC service name'));
		o.depends('transport', 'grpc');
		o.modalonly = true;

		if (side !== 'server' && features.with_grpc) {
			o = section.option(form.Flag, 'grpc_permit_without_stream', _('gRPC permit without stream'),
				_('If enabled, the client transport sends keepalive pings even with no active connections.'));
			o.depends('transport', 'grpc');
			o.modalonly = true;
		}

		o = section.option(form.DynamicList, 'http_host', _('Host'));
		o.datatype = 'hostname';
		o.depends('transport', 'http');
		o.modalonly = true;

		o = section.option(form.Value, 'httpupgrade_host', _('Host'));
		o.datatype = 'hostname';
		o.depends('transport', 'httpupgrade');
		o.modalonly = true;

		o = section.option(form.Value, 'http_path', _('Path'));
		o.depends('transport', 'http');
		o.depends('transport', 'httpupgrade');
		o.modalonly = true;

		o = section.option(form.Value, 'http_method', _('Method'));
		if (side !== 'server') {
			o.value('GET', _('GET'));
			o.value('PUT', _('PUT'));
		}
		o.depends('transport', 'http');
		o.modalonly = true;

		o = section.option(form.Value, 'http_idle_timeout', _('Idle timeout'),
			(side === 'server') ? HTTP_IDLE_GOAWAY_HINT : HTTP_IDLE_HEALTH_CHECK_HINT);
		o.datatype = 'uinteger';
		o.depends('transport', 'grpc');
		o.depends({'transport': 'http', 'tls': '1'});
		o.modalonly = true;

		if (side !== 'server' || features.with_grpc) {
			o = section.option(form.Value, 'http_ping_timeout', _('Ping timeout'),
				(side === 'server') ? HTTP_PING_KEEPALIVE_HINT : HTTP_PING_HEALTH_CHECK_HINT);
			o.datatype = 'uinteger';
			o.depends('transport', 'grpc');
			if (side !== 'server')
				o.depends({'transport': 'http', 'tls': '1'});
			o.modalonly = true;
		}

		o = section.option(form.Value, 'ws_host', _('Host'));
		o.depends('transport', 'ws');
		o.modalonly = true;

		o = section.option(form.Value, 'ws_path', _('Path'));
		o.depends('transport', 'ws');
		o.modalonly = true;

		o = section.option(form.Value, 'websocket_early_data', _('Early data'),
			_('Allowed payload size is in the request.'));
		o.datatype = 'uinteger';
		o.value('2048');
		o.depends('transport', 'ws');
		o.modalonly = true;

		o = section.option(form.Value, 'websocket_early_data_header', _('Early data header name'),
			(side === 'server') ? (_('Early data is sent in path instead of header by default.') +
				'<br/>' +
				_('To be compatible with Xray-core, set this to <code>Sec-WebSocket-Protocol</code>.')) : undefined);
		o.value('Sec-WebSocket-Protocol');
		o.depends('transport', 'ws');
		o.modalonly = true;

		if (side !== 'server') {
			o = section.option(form.ListValue, 'packet_encoding', _('Packet encoding'));
			o.value('', _('none'));
			o.value('packetaddr', _('packet addr (v2ray-core v5+)'));
			o.value('xudp', _('Xudp (Xray-core)'));
			o.depends('type', 'vless');
			o.depends('type', 'vmess');
			o.modalonly = true;
		}

		return o;
	},

	/* Build the TLS option group shared by the node (client) and server forms.
	   `options.type_depends` lists the node types the TLS flag applies to,
	   `options.tls_forced_types` the types that force TLS on, and
	   `options.oninsecurechange` the client-side confirm handler. */
	renderTlsOptions(section, options) {
		const side = options.side || 'client';
		let o;

		o = section.option(form.Flag, 'tls', _('TLS'));
		for (let t of (options.type_depends || []))
			o.depends('type', t);
		if (side === 'server')
			o.rmempty = false;
		o.validate = function(section_id, _value) {
			if (section_id) {
				let type = this.map.lookupOption('type', section_id)[0].formvalue(section_id);
				let tls = this.map.findElement('id', 'cbid.homeproxy-pro.%s.tls'.format(section_id)).firstElementChild;

				if ((options.tls_forced_types || []).includes(type)) {
					tls.checked = true;
					tls.disabled = true;
				} else {
					tls.disabled = null;
				}
			}

			return true;
		}
		o.modalonly = true;

		o = section.option(form.Value, 'tls_sni', _('TLS SNI'),
			_('Used to verify the hostname on the returned certificates unless insecure is given.'));
		o.depends('tls', '1');
		o.modalonly = true;

		o = section.option(form.DynamicList, 'tls_alpn', _('TLS ALPN'),
			_('List of supported application level protocols, in order of preference.'));
		o.depends('tls', '1');
		o.modalonly = true;

		if (side !== 'server') {
			o = section.option(form.Flag, 'tls_insecure', _('Allow insecure'),
				_('Allow insecure connection at TLS client.') +
				'<br/>' +
				_('This is <strong>DANGEROUS</strong>, your traffic is almost like <strong>PLAIN TEXT</strong>! Use at your own risk!'));
			o.depends('tls', '1');
			o.onchange = options.oninsecurechange;
			o.modalonly = true;
		}

		o = section.option(form.ListValue, 'tls_min_version', _('Minimum TLS version'),
			_('The minimum TLS version that is acceptable.'));
		o.value('', _('default'));
		for (let i of this.tls_versions)
			o.value(i);
		o.depends('tls', '1');
		o.modalonly = true;

		o = section.option(form.ListValue, 'tls_max_version', _('Maximum TLS version'),
			_('The maximum TLS version that is acceptable.'));
		o.value('', _('default'));
		for (let i of this.tls_versions)
			o.value(i);
		o.depends('tls', '1');
		o.modalonly = true;

		o = section.option(this.CBIStaticList, 'tls_cipher_suites', _('Cipher suites'),
			_('The elliptic curves that will be used in an ECDHE handshake, in preference order. If empty, the default will be used.'));
		for (let i of this.tls_cipher_suites)
			o.value(i);
		o.depends('tls', '1');
		o.optional = true;
		o.modalonly = true;

		if (side !== 'server') {
			o = section.option(form.Value, 'tls_handshake_timeout', _('Handshake timeout (1.14)'),
				_('TLS handshake timeout in seconds. 15s is used by default.'));
			o.datatype = 'uinteger';
			o.placeholder = '15';
			o.depends('tls', '1');
			o.modalonly = true;
		}

		return o;
	},

	/* MD5 of the UTF-8 bytes of `input`, as 32 lowercase hex characters.
	 *
	 * WHY STILL HAND-ROLLED.  The obvious replacement, crypto.subtle.digest(),
	 * does not do MD5: the Web Crypto specification requires only SHA-1,
	 * SHA-256, SHA-384 and SHA-512, and browsers reject
	 * crypto.subtle.digest('MD5', ...) with NotSupportedError - MD5 was left
	 * out deliberately, being collision-broken.  Nor can this switch to
	 * SHA-256: the value is compared against the `grouphash` option that
	 * update_subscriptions.uc writes with ucode's own md5() (over the URL with
	 * its fragment stripped) and repository.uc names each node section
	 * md5(grouphash + label).  A different hash on either side stops matching,
	 * and every existing install's subscription nodes would drop out of their
	 * tabs.  MD5 is part of that cross-language contract, so it stays MD5.
	 *
	 * What the previous body got wrong, besides being an unreadable minified
	 * snippet with h/k/l/m/n/p for names:
	 *
	 *   - it normalised CRLF to LF before hashing, which is not part of RFC
	 *     1321 and cannot match ucode's md5() for an input containing CRLF;
	 *   - it encoded UTF-8 one UTF-16 code unit at a time, so an astral
	 *     character (any emoji) became invalid UTF-8 and a digest that could
	 *     not match ucode's.
	 *
	 * Both are gone: the bytes hashed here are exactly TextEncoder's, the same
	 * UTF-8 ucode's md5() hashes.  tests/frontend-md5.js pins this to the RFC
	 * 1321 vectors and cross-checks it against Node's
	 * crypto.createHash('md5'), so a future edit cannot drift unnoticed.
	 *
	 * Throws on a non-string.  The old body did too, but only by accident
	 * (`null.replace` is a TypeError); TextEncoder would instead encode the
	 * text "null" and return a digest, silently naming a section after a
	 * string nobody asked for.  Hence the explicit check. */
	calcStringMD5(input) {
		if (typeof(input) !== 'string')
			throw new TypeError('calcStringMD5: expected a string, got ' +
				(input === null ? 'null' : typeof(input)));

		/* RFC 1321 sections 3.1/3.2: append 0x80, pad with zeros, then write
		 * the original length in bits as a little-endian 64-bit integer, out
		 * to the next multiple of 64 bytes. */
		const bytes = new TextEncoder().encode(input);
		const length = bytes.length;
		const paddedLength = (((length + 8) >> 6) + 1) << 6;
		const block = new Uint8Array(paddedLength);
		block.set(bytes);
		block[length] = 0x80;

		const view = new DataView(block.buffer);
		const bitLength = length * 8;
		view.setUint32(paddedLength - 8, bitLength >>> 0, true);
		view.setUint32(paddedLength - 4, Math.floor(bitLength / 4294967296), true);

		let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;

		for (let offset = 0; offset < paddedLength; offset += 64) {
			/* This block as sixteen little-endian 32-bit words. */
			const M = new Uint32Array(16);
			for (let i = 0; i < 16; i++)
				M[i] = view.getUint32(offset + i * 4, true);

			let A = a0, B = b0, C = c0, D = d0;

			for (let i = 0; i < 64; i++) {
				let F, g;

				/* RFC 1321 section 3.4: four rounds of sixteen operations,
				 * each round with its own F() and its own word order. */
				if (i < 16)      { F = (B & C) | (~B & D); g = i; }
				else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
				else if (i < 48) { F = B ^ C ^ D;          g = (3 * i + 5) % 16; }
				else             { F = C ^ (B | ~D);       g = (7 * i) % 16; }

				F = (F + A + MD5_K[i] + M[g]) | 0;
				A = D;
				D = C;
				C = B;
				B = (B + ((F << MD5_S[i]) | (F >>> (32 - MD5_S[i])))) | 0;
			}

			a0 = (a0 + A) | 0;
			b0 = (b0 + B) | 0;
			c0 = (c0 + C) | 0;
			d0 = (d0 + D) | 0;
		}

		/* The four state words are emitted little-endian, in order. */
		let out = '';
		for (let word of [ a0, b0, c0, d0 ])
			for (let i = 0; i < 4; i++)
				out += ((word >>> (i * 8)) & 0xff).toString(16).padStart(2, '0');

		return out;
	},

	/* The single place that declares and calls a backend RPC.
	 *
	 * Most call sites used `L.resolveDefault(call(), {})`, which does NOT
	 * catch a rejection - it only substitutes for a null/undefined *result*.
	 * So when rpcd was unreachable or the method was missing, the caller's
	 * `.then()` simply never ran: the status bar stopped updating, the
	 * capability list quietly became empty and the browser console collected
	 * an unhandled rejection, with nothing said to the user.  Here a failure
	 * resolves to `options.fallback` (default `{}`) and is reported once per
	 * method, so a 5s poll cannot spam the same message.  A backend that
	 * *answers* with an error is a success here and is the caller's business -
	 * this only covers "the call did not come back". */
	rpcCall(method, args, options) {
		options = options || {};
		const object = options.object || 'luci.homeproxy-pro';

		const call = rpc.declare({
			object: object,
			method: method,
			params: options.params || [],
			expect: options.expect
		});

		return Promise.resolve(call.apply(null, args || [])).catch((err) => {
			const key = object + '.' + method;

			if (!rpc_warned.has(key)) {
				rpc_warned.add(key);
				ui.addNotification(null, E('p', [_('The request %s failed: %s.').format(
					key, (err && err.message) || String(err))]));
			}

			return options.fallback !== undefined ? options.fallback : {};
		});
	},

	getBuiltinFeatures() {
		return this.rpcCall('singbox_get_features', [], { expect: { '': {} } });
	},

	/* Parse one share link through the backend parser (parser/uri.uc), the
	 * same code the subscription pipeline runs, so the browser cannot
	 * disagree with the backend about what a URI means.  Resolves to the
	 * parsed node object, or null when the backend rejects the link.
	 *
	 * This replaced a 388-line JavaScript re-implementation of the parser
	 * that had already drifted (its vmess branch lost vmess_global_padding)
	 * and that validated nothing before writing the node into UCI. */
	parseShareLink(uri) {
		/* Backend (luci.homeproxy-pro node_parse) returns one of
		 *   { config: {...the-node-fields}, error: '' }      on success
		 *   { config: null,               error: '...' }   on failure
		 * (rpcParse's `expect` would unpack-and-type-check, which the
		 *  earlier { config: null } got wrong: it coerced the parsed
		 *  config object to null and dropped the whole import.  Leave
		 *  the value alone and pick .config in the then-callback.)
		 * fallback null: a failed call and a rejected link both mean
		 * "no node", and the caller already tells the user which
		 * links were dropped. */
		return this.rpcCall('node_parse', [uri],
				{ params: ['uri'], fallback: null })
			.then((res) => (res && res.config) ? res.config : null);
	},

	generateRand(type, length) {
		let byteArr;
		if (['base64', 'hex'].includes(type))
			byteArr = crypto.getRandomValues(new Uint8Array(length));
		switch (type) {
			case 'base64':
				/* Thanks to https://stackoverflow.com/questions/9267899 */
				return btoa(String.fromCharCode.apply(null, byteArr));
			case 'hex':
				return Array.from(byteArr, (byte) =>
					(byte & 255).toString(16).padStart(2, '0')
				).join('');
			case 'uuid':
				/* Thanks to https://stackoverflow.com/a/2117523 */
				return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, (c) =>
					(c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
				);
			default:
				return null;
		};
	},

	loadDefaultLabel(uciconfig, ucisection) {
		let label = uci.get(uciconfig, ucisection, 'label');
		if (label) {
			return label;
		} else {
			uci.set(uciconfig, ucisection, 'label', ucisection);
			return ucisection;
		}
	},

	/* Escape a value for an HTML sink that decodes exactly once - LuCI renders
	 * a form tab's title as a bare string child of E('a', ...), and
	 * dom.append() assigns a bare string straight to innerHTML.  Nothing
	 * decodes it on the way, so one level of escaping is both necessary and
	 * sufficient. */
	escapeHtml(s) {
		return String(s)
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;')
			.replace(/'/g, '&#39;');
	},

	/* Sanitize a value that will become a *section title*, which is a different
	 * path: LuCI's form.titleFn() runs it through stripTags(), and that
	 * function's contract is "HTML tags removed, and HTML entities decoded" -
	 * it parses `<div>${s}</div>` and returns textContent.  The decoded result
	 * is then handed to the same innerHTML sink.
	 *
	 * So escaping alone is NOT enough, and would in fact make things worse:
	 * `&lt;img onerror=...&gt;` would be decoded back into real markup by
	 * stripTags, and a label that is safe today (a raw `<...>`, which
	 * stripTags strips as a tag) would become an XSS.
	 *
	 * The invariant that actually holds after that single decode is therefore
	 * "no literal '<' survives".  Removing the angle brackets and encoding '&'
	 * gives exactly that: '&lt;' becomes '&amp;lt;', which decodes back to
	 * '&lt;' - still text - and a raw '<' is simply dropped.  A name that
	 * genuinely contained angle brackets loses them on display; that is the
	 * deliberate cost of not letting them be re-decoded into markup. */
	escapeTitleText(s) {
		return String(s)
			.replace(/&/g, '&amp;')
			.replace(/[<>]/g, '');
	},

	/* Repair node references that point at a section which no longer exists.
	 *
	 * Deleting a node from the grid stages a plain `uci.remove`; nothing
	 * rewrites `config.main_node` / `main_udp_node` / the urltest member lists,
	 * and the generator then dies on every later run with
	 *
	 *   cannot build main-out: the node it refers to does not exist (it may
	 *   have been deleted, or the reference is stale).
	 *
	 * so the reload aborts (the running configuration is kept) while the UI
	 * reports the save as applied - measured on the device: generation exit 254
	 * with exactly that message.  `nil` and `urltest` are not section names, and
	 * a reference that still resolves is left alone.
	 *
	 * Takes the cursor as an argument so this is testable without a form;
	 * returns the list of repairs it made.
	 */
	repairNodeRefs(uci, cfg) {
		const repaired = [];

		for (let opt of [ 'main_node', 'main_udp_node' ]) {
			const ref = uci.get(cfg, 'config', opt);

			if (ref && ref !== 'nil' && ref !== 'urltest' && uci.get(cfg, ref) == null) {
				uci.set(cfg, 'config', opt, 'nil');
				repaired.push(opt);
			}
		}

		for (let opt of [ 'main_urltest_nodes', 'main_udp_urltest_nodes' ]) {
			const list = uci.get(cfg, 'config', opt);

			if (!Array.isArray(list) || !list.length)
				continue;

			const kept = list.filter((id) => uci.get(cfg, id) != null);

			if (kept.length !== list.length) {
				uci.set(cfg, 'config', opt, kept);
				repaired.push(opt);
			}
		}

		return repaired;
	},

	loadModalTitle(title, addtitle, uciconfig, ucisection) {
		let label = uci.get(uciconfig, ucisection, 'label');
		return label ? title + ' » ' + this.escapeTitleText(label) : addtitle;
	},

	/* Hash and display title for one subscription URL entry.
	 *
	 * The fragment is attacker-controlled: it comes from a subscription URL
	 * (which anyone can hand you), it is never sent to the server, and LuCI
	 * renders the resulting tab title through the innerHTML path in
	 * escapeHtml().  The decode is also a crash risk on its own - '%' or
	 * '100%' are accepted by the form validator and make decodeURIComponent
	 * throw, which aborted the whole Node Settings render - so both steps are
	 * guarded and a malformed entry degrades to showing the raw text. */
	subscriptionInfo(suburl) {
		if (typeof(suburl) !== 'string' || suburl === '')
			return null;

		const hash = this.calcStringMD5(suburl.replace(/#.*$/, ''));
		let title;

		try {
			const url = new URL(suburl);

			if (url.hash) {
				try {
					title = decodeURIComponent(url.hash.slice(1));
				}
				catch (e) {
					/* Malformed percent-escape: show it verbatim. */
					title = url.hash.slice(1);
				}
			}
			else {
				title = url.hostname;
			}
		}
		catch (e) {
			/* Not a URL at all; any other package may have written this. */
			title = suburl;
		}

		return { 'hash': hash, 'title': this.escapeHtml(title) };
	},

	/* Shared grid "add section" renderer: the stock one plus a uniqueness
	 * validator on the name field. `extra_button` is an optional factory for
	 * a button to append after it; the node page passes one for its "Import
	 * share links" action. That page used to carry a verbatim copy of this
	 * whole method just to append the button, and the section is handed back
	 * to the factory so the caller can bind the handler to itself.
	 *
	 * CALLING CONVENTION - call sites must NOT reach this through L.bind().
	 * LuCI calls a section's renderSectionAdd() as
	 * `this.renderSectionAdd(extra_class)`, so the method takes the section as
	 * its first argument and the instance it is called on is thrown away.
	 * `ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss)` therefore
	 * pins `ss` correctly but leaves the two remaining slots to the *call
	 * site*, which means `ss.renderSectionAdd(factory)` lands the factory in
	 * `extra_class` and hands it to the DOM as a class string:
	 * `InvalidCharacterError` and the whole tab fails to render. That shipped
	 * once (commit e598923 against the r23 baseline 67d2c3a). Use a one-line
	 * wrapper instead, which also keeps `extra_button` reachable:
	 *
	 *   ss.renderSectionAdd = function(extra_class) {
	 *       return hp.renderSectionAdd(ss, extra_class);
	 *   };
	 *
	 * The guard below is the containment half of the fix, for a call site
	 * that has not been converted yet: a lone factory in the `extra_class`
	 * slot is treated as the button factory it was meant to be. */
	renderSectionAdd(section, extra_class, extra_button) {
		if (typeof(extra_button) !== 'function' && typeof(extra_class) === 'function') {
			extra_button = extra_class;
			extra_class = undefined;
		}

		let el = form.GridSection.prototype.renderSectionAdd.apply(section, [ extra_class ]),
			nameEl = el.querySelector('.cbi-section-create-name');
		ui.addValidator(nameEl, 'uciname', true, (v) => {
			let button = el.querySelector('.cbi-section-create > .cbi-button-add');
			let uciconfig = section.uciconfig || section.map.config;

			if (!v) {
				button.disabled = true;
				return true;
			} else if (uci.get(uciconfig, v)) {
				button.disabled = true;
				return _('Expecting: %s').format(_('unique UCI identifier'));
			} else {
				button.disabled = null;
				return true;
			}
		}, 'blur', 'keyup');

		if (typeof(extra_button) === 'function')
			el.appendChild(extra_button(section));

		return el;
	},

	uploadCertificate(type, filename, ev) {
		/* Per-type staging file: the four buttons (server public key /
		 * server private key / client CA / client ECH config) all
		 * shared /tmp/homeproxy_certificate.tmp before, so two uploads
		 * in flight would clobber each other and the wrong file could
		 * land in the certs/ directory. The filename argument is the
		 * UCI option name (e.g. server_publickey), which we map onto
		 * a stable per-button path. The ACL write list in
		 * acl.d/luci-app-homeproxy-pro.json enumerates all four paths.
		 *
		 * The signature is (type, filename, ev) on purpose: L.bind()
		 * binds arguments *in front of* the event the Button hands in
		 * (form.js calls onclick(ev, section_id)), so a leading
		 * parameter that no caller passes shifts every argument by one
		 * and the staging path becomes
		 * /tmp/homeproxy_cert_[object Event].tmp - a path neither the
		 * ACL nor certificate_write knows. tests/arch-guard.sh checks
		 * this argument alignment. */
		const tmpPath = '/tmp/homeproxy_cert_' + filename + '.tmp';

		return ui.uploadFile(tmpPath, ev.target)
		.then(L.bind((_btn, res) => {
			return this.rpcCall('certificate_write', [filename],
					{ params: ['filename'], expect: { '': {} } }).then((ret) => {
				if (ret && ret.result === true)
					ui.addNotification(null, E('p', _('Your %s was successfully uploaded. Size: %sB.').format(type, res.size)));
				else
					ui.addNotification(null, E('p', [_('Failed to upload %s, error: %s.').format(type, (ret && ret.error) || 'unknown error')]));
			});
		}, this, ev.target))
		.catch((e) => { ui.addNotification(null, E('p', [e.message || 'upload failed'])) });
	},

	validateBase64Key(length, section_id, value) {
		/* Thanks to luci-proto-wireguard */
		if (section_id && value)
			if (value.length !== length || !value.match(/^(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?$/) || value[length-1] !== '=')
				return _('Expecting: %s').format(_('valid base64 key with %d characters').format(length));

		return true;
	},

	validateCertificatePath(section_id, value) {
		if (section_id && value)
			/* HP_CERT_PATH_ROOTS is the same list the backend enforces
			   (CERT_PATH_ROOTS, guard 29). The `..` rejection has to be
			   explicit: a prefix match alone accepts
			   /etc/ssl/../shadow, and sing-box reads these paths as root. */
			if (value.match(/(^|\/)\.\.(\/|$)/) ||
			    !HP_CERT_PATH_ROOTS.some((root) => value.indexOf(root) === 0 && value.length > root.length))
				return _('Expecting: %s').format(_('/etc/homeproxy-pro/certs/..., /etc/acme/..., /etc/ssl/...'));

		return true;
	},

	validateRuleSetPath(section_id, value) {
		if (section_id && value)
			/* HP_RULE_PATH_ROOTS is the same list the backend enforces
			   (RULE_PATH_ROOTS, guard 50). The `..` rejection is explicit for
			   the same reason as in validateCertificatePath: a prefix match
			   alone accepts /etc/homeproxy-pro/ruleset/../../etc/shadow, and
			   sing-box opens these files as root. The backend is the authority
			   - this only saves a save that the generator would refuse a
			   moment later with a message the user reads in a log file rather
			   than on the page they are editing. */
			if (value.match(/(^|\/)\.\.(\/|$)/) ||
			    !HP_RULE_PATH_ROOTS.some((root) => value.indexOf(root) === 0 && value.length > root.length))
				return _('Expecting: %s').format(_('/etc/homeproxy-pro/ruleset/...'));

		return true;
	},

	validatePortRange(section_id, value) {
		if (section_id && value) {
			value = value.match(/^(\d+)?\:(\d+)?$/);
			if (value && (value[1] || value[2])) {
				if (!value[1])
					value[1] = 0;
				else if (!value[2])
					value[2] = 65535;

				/* numeric comparison: string '<' does lexicographic ordering */
				if (parseInt(value[1], 10) < parseInt(value[2], 10) && value[2] <= 65535)
					return true;
			}

			return _('Expecting: %s').format( _('valid port range (port1:port2)'));
		}

		return true;
	},

	validateUniqueValue(uciconfig, ucisection, ucioption, section_id, value) {
		if (section_id) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			if (ucioption === 'node' && value === 'urltest')
				return true;

			let duplicate = false;
			uci.sections(uciconfig, ucisection, (res) => {
				if (res['.name'] !== section_id)
					if (res[ucioption] === value)
						duplicate = true
			});
			if (duplicate)
				return _('Expecting: %s').format(_('unique value'));
		}

		return true;
	},

	validateUUID(section_id, value) {
		if (section_id) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			else if (value.match('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') === null)
				return _('Expecting: %s').format(_('valid uuid'));
		}

		return true;
	}
});
