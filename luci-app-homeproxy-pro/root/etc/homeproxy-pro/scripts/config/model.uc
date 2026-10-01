/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Stage A1.1 of the architecture refactor:
 *
 *     UCI -> Config Loader -> HomeProxyConfig / Node -> Adapter -> sing-box
 *
 * The point of this layer is that nothing below it may touch UCI, and nothing
 * in it may know about sing-box JSON. A Node therefore describes *what the
 * user configured*, not what sing-box wants: no `outbound`, no `type` field
 * named after a sing-box outbound kind, no `tag` arithmetic.
 *
 * Every field the Adapter used to read off
 * `node.raw.*` has been promoted to an explicit Node sub-object
 * (`credentials`, `tls`, `transport`, `multiplex`, `common`,
 * `protocol_options`), so the legacy `raw` opaque bag was dropped - no code
 * reads it and leaving it in only made the next reader assume it was
 * authoritative.
 */

'use strict';

import { isEmpty, isValidCIDR } from '../homeproxy-pro.uc';

/* Canonical credential multiplexing for a Node. The current generator picks
 * these apart with ternaries per field (`username` vs `user` vs `password` vs
 * `psk`, keyed on every protocol); expressing them as data is what makes a new
 * protocol a table entry instead of another branch.
 *
 * The value is the UCI option name (as the loader sees it on the flat UCI
 * section), the key is the canonical credential name. The adapter later
 * emits the field under whatever name the sing-box outbound wants
 * (e.g. snell: credentials.psk is emitted as the outbound `psk` field,
 * shadowsocks: credentials.method becomes outbound `method`).
 *
 * Fixed during Stage A1.1: snell `userkey` actually comes from the
 * `snell_userkey` UCI option (not `username`), and shadowsocks `method`
 * actually comes from `shadowsocks_encrypt_method` (not `method`).
 * The earlier table assumed both mapped to bare option names and failed
 * the skeleton test against the real fixture. */
export const CREDENTIALS = {
	vless:   { uuid: 'uuid' },
	vmess:   { uuid: 'uuid' },
	trojan:  { password: 'password' },
	hysteria: { auth_str: 'auth', auth_base64: 'auth' },
	hysteria2: { password: 'password' },
	tuic:    { uuid: 'uuid', password: 'password' },
	shadowsocks: { password: 'password', method: 'shadowsocks_encrypt_method' },
	socks:   { username: 'username', password: 'password' },
	http:    { username: 'username', password: 'password' },
	snell:   { psk: 'password', userkey: 'snell_userkey' },
	/* The node form writes ssh_priv_key / ssh_priv_key_pp, not the bare
	 * private_key this table used to claim, so the key the user pasted was
	 * never read.  (There was also no PROTOCOL_OPTIONS row for ssh, so the
	 * rest of the SSH options were dropped as well.) */
	ssh:     { user: 'username', password: 'password',
	           private_key: 'ssh_priv_key', private_key_passphrase: 'ssh_priv_key_pp' },
	anytls:  { password: 'password' },
	shadowtls: { password: 'password' },
	direct:  {}
};

/* Canonical credentials for a server Inbound. A different table from
 * the client's CREDENTIALS because the server form exposes a smaller
 * set (no ssh material, no snell userkey) and because snell's server
 * side reads the psk off the same `password` UCI option the client
 * node uses for its own psk. Keeping the two tables separate means a
 * change to one side cannot silently alter the other.
 */
export const INBOUND_CREDENTIALS = {
	vless:     { uuid: 'uuid' },
	vmess:     { uuid: 'uuid' },
	trojan:    { password: 'password' },
	hysteria:  { auth_str: 'hysteria_auth_payload', auth_base64: 'hysteria_auth_payload' },
	hysteria2: { password: 'password' },
	tuic:      { uuid: 'uuid', password: 'password' },
	shadowsocks: { password: 'password', method: 'shadowsocks_encrypt_method' },
	shadowtls: { password: 'password' },
	snell:     { psk: 'password' },
	anytls:    { password: 'password' },
	http:      { username: 'username', password: 'password' },
	mixed:     { username: 'username', password: 'password' },
	naive:     { username: 'username', password: 'password' },
	socks:     { username: 'username', password: 'password' }
};

/* Per-protocol options on a server Inbound, canonical -> UCI. This is
 * the server-side counterpart of parser/mapping.uc's PROTOCOL_TO_UCI;
 * the two are NOT identical - the server side exposes inbound-only
 * knobs (anytls padding_scheme, hysteria masquerade / packet sizes /
 * ignore_client_bandwidth, tuic auth_timeout) and does not expose the
 * client's port-hopping options - so they stay separate tables. A
 * protocol whose server-side row is missing here produces no
 * protocol_options rather than reading a flat UCI key. */
export const INBOUND_OPTIONS = {
	anytls: {
		padding_scheme: 'anytls_padding_scheme'
	},
	hysteria: {
		auth_type: 'hysteria_auth_type',
		up_mbps: 'hysteria_up_mbps',
		down_mbps: 'hysteria_down_mbps',
		obfs_password: 'hysteria_obfs_password',
		masquerade: 'hysteria_masquerade',
		ignore_client_bandwidth: 'hysteria_ignore_client_bandwidth'
	},
	hysteria2: {
		up_mbps: 'hysteria_up_mbps',
		down_mbps: 'hysteria_down_mbps',
		obfs_type: 'hysteria_obfs_type',
		obfs_password: 'hysteria_obfs_password',
		obfs_min_packet_size: 'hysteria_obfs_min_packet_size',
		obfs_max_packet_size: 'hysteria_obfs_max_packet_size',
		masquerade: 'hysteria_masquerade',
		ignore_client_bandwidth: 'hysteria_ignore_client_bandwidth'
	},
	shadowsocks: {
		method: 'shadowsocks_encrypt_method'
	},
	snell: {
		version: 'snell_version',
		obfs_mode: 'snell_obfs_mode'
	},
	tuic: {
		congestion_control: 'tuic_congestion_control',
		auth_timeout: 'tuic_auth_timeout',
		zero_rtt_handshake: 'tuic_enable_zero_rtt',
		heartbeat: 'tuic_heartbeat'
	},
	vless: {
		flow: 'vless_flow'
	},
	vmess: {
		alter_id: 'vmess_alterid'
	}
};

/* Listener-level fields every server inbound carries. Inbound-only
 * (no client outbound emits them), so they are not part of the
 * client's load_common() table. */
export const INBOUND_COMMON = {
	bind_interface: 'bind_interface',
	reuse_addr: 'reuse_addr',
	tcp_fast_open: 'tcp_fast_open',
	tcp_multi_path: 'tcp_multi_path',
	udp_fragment: 'udp_fragment',
	udp_timeout: 'udp_timeout',
	network: 'network'
};

/* The server-only TLS tail. These options exist because a client
 * outbound never needs them (key material, ACME, the server half of
 * the REALITY handshake), so they live on the Inbound rather than
 * being folded into the shared `tls` sub-object the Loader builds for
 * both sides. Canonical -> UCI; the Adapter re-keys them back to the
 * UCI names buildTLSObject() reads, which is the one place the flat
 * names still exist. */
export const INBOUND_TLS_SERVER = {
	key_path: 'tls_key_path',
	ech_key: 'tls_ech_key',
	reality_private_key: 'tls_reality_private_key',
	reality_max_time_difference: 'tls_reality_max_time_difference',
	reality_server_addr: 'tls_reality_server_addr',
	reality_server_port: 'tls_reality_server_port',
	acme: 'tls_acme',
	acme_domain: 'tls_acme_domain',
	acme_dsn: 'tls_acme_dsn',
	acme_email: 'tls_acme_email',
	acme_provider: 'tls_acme_provider',
	acme_account_key: 'tls_acme_account_key',
	acme_key_type: 'tls_acme_key_type',
	acme_profile: 'tls_acme_profile',
	acme_disable_http_challenge: 'tls_acme_dhc',
	acme_disable_tls_alpn_challenge: 'tls_acme_dtac',
	acme_alternative_http_port: 'tls_acme_ahp',
	acme_alternative_tls_port: 'tls_acme_atp',
	acme_external_account: 'tls_acme_external_account',
	acme_external_account_key_id: 'tls_acme_ea_keyid',
	acme_external_account_mac_key: 'tls_acme_ea_mackey',
	dns01_challenge: 'tls_dns01_challenge',
	dns01_provider: 'tls_dns01_provider',
	dns01_access_key_id: 'tls_dns01_ali_akid',
	dns01_access_key_secret: 'tls_dns01_ali_aksec',
	dns01_region_id: 'tls_dns01_ali_rid',
	dns01_api_token: 'tls_dns01_cf_api_token'
};

/* --- Domain types ------------------------------------------------------- */

export const Config = {
	create: (name) => ({
		name: name,
		general: {},
		nodes: [],

		/* The five domain sub-objects the Loader fills in from the
		 * corresponding UCI sections (single + list). The Loader now
		 * normalises the list sections; downstream generators read only
		 * these sub-objects. */
		dns: {},
		routing: {},
		access_control: {},
		server: {}
	})
};

export const Node = {
	create: (opts) => ({
		/* identity */
		id: opts.id,
		name: opts.name,
		type: opts.type,

		/* endpoint */
		address: opts.address,
		port: opts.port,

		/* cross-protocol common fields (proxy_protocol, tcp_fast_open,
		 * tcp_multi_path, udp_fragment). The Adapter reads from here so
		 * it never has to reach back into UCI for these. */
		common: opts.common || {},

		/* credentials, already canonical */
		credentials: opts.credentials || {},

		/* transport/TLS are sub-objects, not flat prefixed keys: that is the
		   boundary the adapter needs in order to reuse the shared builders. */
		tls: opts.tls || {},
		transport: opts.transport || {},
		multiplex: opts.multiplex || {},

		/* per-protocol extras, canonical names only */
		protocol_options: opts.protocol_options || {}
	}),

	/* A node is usable only if the adapter can build a valid outbound from it.
	 * The old code discovers this by crashing inside the JSON builder.
	 *
	 * Scope: generic, cross-protocol sanity only. The Adapter layer owns
	 * per-protocol required-field rules (a vless needs uuid, vmess needs
	 * both uuid and a security cipher, snell needs a psk, ...) because
	 * those rules are sing-box-outbound-shaped. Anything the model can
	 * express without naming a protocol or a JSON field goes here.
	 *
	 * Booleans are still raw UCI strings at this layer; this validator
	 * compares against the literal '1' the way UCI emits them.
	 *
	 * Implementation note: ucode's push() returns the value pushed, not
	 * the new array, so the natural-looking `problems = push(problems, X)`
	 * pattern reassigns problems to a string and silently corrupts the
	 * accumulator. Build the array via spread instead - cheap because the
	 * validator is at most four checks. */
	validate: (node) => {
		let problems = [];

		if (!node.type)
			problems = [...problems, 'missing type'];

		/* A direct outbound can run without a server/server_port - sing-box
		 * uses the inbound's destination as the upstream, which is the
		 * transparent-proxy case. For every other protocol the server
		 * and port are mandatory. */
		if (node.type !== 'direct') {
			if (!node.address)
				problems = [...problems, 'missing address'];

			if (node.port == null || int(node.port) < 1 || int(node.port) > 65535)
				problems = [...problems, `invalid port '${node.port}'`];
		}

		/* TLS without an explicit server_name.
		 *
		 * sing-box defaults an outbound's tls.server_name to the
		 * outbound's server address, so a node whose address is a
		 * *hostname* works fine without one: the handshake sends that
		 * hostname as SNI and verifies the certificate against it. That
		 * is the documented default (outbound tls.server_name defaults to
		 * "server address"), not a leniency we invented.
		 *
		 * This check used to fire for both address shapes, and firing
		 * meant die() - OutboundFactory.create() treats a non-empty
		 * problems list as fatal. A trojan:// / anytls:// / hysteria2://
		 * / tuic:// share link with no `sni=` parameter produces exactly
		 * such a node (each parser writes `tls_sni: params.sni` and
		 * nothing else), and so does the node form, whose "TLS SNI"
		 * field is an optional form.Value gated only on tls=1
		 * (homeproxy-pro.js:672). As a main node it then took the whole
		 * client configuration down:
		 *
		 *   node '<section>': TLS enabled without server_name
		 *
		 * Reproduced on a real router (2026-10-01, sing-box 1.14.2):
		 * with the SNI removed from the main node, buildable() is false
		 * and generate() dies - so a reload rolled back to the previous
		 * configuration and a boot start refused to come up, over a node
		 * sing-box would have dialed without complaint.
		 *
		 * The case that IS worth a problem is an IP address: the implicit
		 * SNI is then the literal IP, which no real server presents a
		 * matching certificate for, so the connection cannot succeed.
		 * That stays fatal for a node a rule or the main node points at
		 * (the existing contract for an unbuildable node) and is pruned
		 * with a warning inside a urltest group
		 * (generator/outbound.uc keep_candidate). reality is the escape
		 * hatch: it runs its own handshake and does not use server_name.
		 */
		if (node.tls.enabled === '1' && !node.tls.server_name
			&& node.tls.reality.enabled !== '1'
			&& (isValidCIDR(node.address, 4) || isValidCIDR(node.address, 6)))
			problems = [...problems,
				`TLS enabled on IP address ${node.address} without server_name`];

		return problems;
	},

	/* sing-box tag convention lives here, not scattered through the generator */
	tag: (node) => 'cfg-' + node.id + '-out'
};

/* The server-side counterpart of Node. Same layering discipline: it
 * describes what the user configured (listen address/port, protocol,
 * credentials, TLS, transport, per-protocol knobs) and knows nothing
 * about sing-box JSON. The Inbound adapter (config/adapter.uc,
 * InboundFactory) is what turns it into a sing-box inbound.
 *
 * Field grouping mirrors Node deliberately so the Adapter's two halves
 * read the same way:
 *   common           listener-level shared fields (bind_interface,
 *                    reuse_addr, tcp_fast_open, ...)
 *   credentials      canonical credential names
 *   tls              shared TLS shape (same load_tls() the client uses)
 *   tls_server       server-only TLS tail (key material, ACME, the
 *                    server half of the REALITY handshake)
 *   transport        shared transport shape (same load_transport())
 *   multiplex        shared multiplex shape
 *   protocol_options per-protocol knobs
 */
export const Inbound = {
	create: (opts) => ({
		/* identity */
		id: opts.id,
		name: opts.name,
		type: opts.type,
		enabled: opts.enabled,

		/* listener */
		address: opts.address,
		port: opts.port,

		/* firewall is consumed by firewall_pre.uc (which decides the
		 * nft accept rules), not by the inbound adapter. It stays on the
		 * model so the server section is described in one place. */
		firewall: opts.firewall,

		common: opts.common || {},
		credentials: opts.credentials || {},
		tls: opts.tls || {},
		tls_server: opts.tls_server || {},
		transport: opts.transport || {},
		multiplex: opts.multiplex || {},

		protocol_options: opts.protocol_options || {}
	}),

	/* Same scope as Node.validate(): cross-protocol sanity the model
	 * can express without naming a sing-box field. The per-protocol
	 * rules live in the Adapter (InboundFactory.problems). */
	validate: (inbound) => {
		let problems = [];

		if (!inbound.type)
			problems = [...problems, 'missing type'];

		/* An inbound with no listen address is legitimate (sing-box
		 * defaults to all interfaces), but a port is required. */
		if (inbound.port == null || int(inbound.port) < 1 || int(inbound.port) > 65535)
			problems = [...problems, `invalid port '${inbound.port}'`];

		return problems;
	},

	/* sing-box tag convention for a server inbound. Uses `id` (the UCI
	 * section name) rather than `name` (the user's label) so renaming a
	 * label does not change the tag. */
	tag: (inbound) => 'cfg-' + inbound.id + '-in'
};

/* --- Config helpers ----------------------------------------------------- */

export const ConfigQuery = {
	node_by_id: (config, id) => {
		for (let node in config.nodes)
			if (node.id === id)
				return node;

		return null;
	},

	/* Linear search by section name. The Loader normalises list sections so
	 * `name` is the UCI section name; the dotted `.name` UCI uses
	 * internally is gone from the loaded shape. */
	find_by_name: (items, name) => {
		for (let it in items)
			if (it.name === name)
				return it;
		return null;
	},

	/* Which UDP node the routing modes route through. The default (`nil`)
	 * means "no proxy node", which is a legitimate configuration. The
	 * equivalent main_node read is one-liner enough that no helper
	 * exists. */
	main_udp_node_id: (config) => config.general.main_udp_node || 'nil'
};
