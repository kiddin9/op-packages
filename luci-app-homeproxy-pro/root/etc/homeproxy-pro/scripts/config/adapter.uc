/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Stage A1.1 of the architecture refactor:
 *
 *     Node -> Protocol Adapter -> SingBox Outbound
 *
 * This replaces the single 110-line `generate_outbound()` whose protocol
 * branches were expressed as ~60 ternaries inside one object literal. Three
 * properties are deliberate:
 *
 *   kept     the shared TLS/transport/multiplex code is still the existing
 *            production builders - the adapter only supplies them a
 *            Node-shaped view instead of a flat UCI dict.
 *   pinned   the emitted JSON is frozen by tests/snapshots/generator/
 *            outbounds.json, so a field change for any protocol is a
 *            reviewable diff (test_golden_outbounds.sh).
 *   dropped  a per-protocol Adapter class hierarchy. The protocols differ by
 *            which *fields* they carry, not by behaviour, so the honest
 *            extension point is the field tables below, not eleven classes.
 *
 * Adding a protocol means adding three entries: CREDENTIALS (model.uc),
 * PROTOCOL_OPTIONS (loader.uc) and OPTION_FIELDS here - and a node in
 * tests/fixtures/generators/outbounds.uci, which
 * tests/ucode/test_protocol_inventory.sh enforces.
 */

'use strict';

import {
	isEmpty, strToBool, strToInt, strToTime, removeBlankAttrs,
	buildTLSObject, buildTransportObject, parse_port
} from '../homeproxy-pro.uc';

import { Node, Inbound, INBOUND_TLS_SERVER } from './model.uc';

/* Per-protocol required credential fields. Node.validate() covers the
 * cross-protocol rules (type/address/port/TLS); this table is the
 * per-protocol half - "vless needs uuid, vmess needs uuid, trojan needs
 * password, snell needs psk, ..." - and it is the Adapter's job because
 * the requirement is shaped by what the sing-box outbound for each
 * protocol will actually accept, not by anything the model knows about
 * UCI. The keys are the canonical credential names the Loader uses
 * (see CREDENTIALS in model.uc), so the check is data-driven and adding
 * a protocol is a one-line change. */
export const REQUIRED_CREDENTIALS = {
	vless:     ['uuid'],
	vmess:     ['uuid'],
	trojan:    ['password'],
	hysteria2: ['password'],
	tuic:      ['uuid', 'password'],
	shadowsocks: ['password'],
	snell:     ['psk'],
	anytls:    ['password'],
	shadowtls: ['password'],
	ssh:       ['user'],
	/* These three have no hard required credential - the protocol can
	 * run anonymously (http / socks) or the auth is delivered out of
	 * band (hysteria, direct). Node.validate()'s address/port check
	 * is enough. */
	hysteria:  [],
	http:      [],
	socks:     [],
	direct:    []
};

/* Run a Node through the per-protocol required-field check. Returns
 * the (possibly empty) list of human-readable problems.
 *
 * The same ucode quirk that bit Node.validate() bites here too: push()
 * returns the value pushed, not the new array, so we build the result
 * via spread instead of the obvious `problems = push(problems, X)`. */
function protocol_problems(node) {
	const required = REQUIRED_CREDENTIALS[node.type] || [];
	const creds = node.credentials || {};
	let problems = [];

	for (let field in required) {
		if (!creds[field])
			problems = [...problems, `${node.type} requires ${field}`];
	}

	/* WireGuard is the one protocol whose material does not live in
	 * `credentials`: the endpoint builder reads node.protocol_options.
	 * Checking it here means a broken WireGuard node is caught by the
	 * same "is this node buildable?" path as every other protocol, which
	 * is what lets a urltest list prune it instead of failing the whole
	 * configuration. */
	if (node.type === 'wireguard') {
		const opts = node.protocol_options || {};
		for (let field in ['local_address', 'private_key', 'peer_public_key'])
			if (!opts[field])
				problems = [...problems, `wireguard requires ${field}`];
	}

	return problems;
}

/* --- field transforms --------------------------------------------------- */

/* A table value is either a function of the domain object (a Node for the
 * outbound tables, an Inbound for the server tables), a literal, or a
 * string naming a transform (in which case the value is null - the spec
 * is present so the key still gets emitted, but the value will be
 * stripped by removeBlankAttrs()). */
const TRANSFORMS = {
	raw: (value) => value,
	bool: (value) => strToBool(value),
	int: (value) => strToInt(value),
	time: (value) => strToTime(value)
};

/* Shared by the outbound and the inbound field tables: the spec is a
 * plain function in every table except the outbound one, which carries a
 * few TRANSFORMS markers for keys that exist but are runtime-owned. */
function resolve(spec, subject) {
	if (type(spec) === 'function')
		return spec(subject);

	if (type(spec) === 'string' && spec in TRANSFORMS)
		return null;

	return spec;
}

/* --- field tables ------------------------------------------------------- */

/* Fields every protocol emits. Each is null when absent, and nulls are
 * stripped once, at the end, by removeBlankAttrs(). Cross-protocol common
 * fields live in node.common (Loader's load_common); protocol-specific
 * canonical names live in node.protocol_options. The legacy
 * `node.raw` opaque bag was dropped - the Adapter reads only the explicit
 * sub-objects, so no escape hatch exists.
 *
 * This table is applied AFTER the literal in build_outbound(), so a key
 * listed here wins over whatever that literal set. A field the runtime owns
 * (routing_mark, from the `mark` argument) therefore must NOT be listed
 * here, not even as `null`: the loop would overwrite the value with null and
 * removeBlankAttrs() would drop the field entirely. routing_mark is what
 * exempts sing-box's own proxy connections from the nft redirect chain, so
 * losing it loops the traffic back into the redirect inbound. Guard 32 in
 * tests/arch-guard.sh keeps the literal's keys and this table disjoint. */
const COMMON_FIELDS = {
	server: (node) => node.address,
	server_port: (node) => strToInt(node.port),
	proxy_protocol: (node) => strToInt(node.common.proxy_protocol),
	tcp_fast_open: (node) => strToBool(node.common.tcp_fast_open),
	tcp_multi_path: (node) => strToBool(node.common.tcp_multi_path),
	udp_fragment: (node) => strToBool(node.common.udp_fragment),
	packet_encoding: (node) => node.protocol_options.packet_encoding || null
};

/* The node form stores an SSH private key in a DynamicList, i.e. one UCI
 * list entry per line of the OpenSSH/PEM blob (a UCI option cannot hold
 * newlines).  sing-box wants the whole key as one string, so re-join the
 * lines.  A single-entry value is passed through unchanged.
 *
 * Declared before CLAIM_FIELDS on purpose: ucode resolves module-level names
 * lexically, so a callee has to appear above its caller in the file. */
function ssh_private_key(value) {
	if (type(value) === 'array')
		return length(value) ? join('\n', value) : null;

	return value || null;
}

/* Credential fields: one canonical set, emitted under the name each protocol
 * wants. This is where the old builder repeated itself. */
function CLAIM_FIELDS(node) {
	switch (node.type) {
	case 'snell':
		return {
			psk: node.credentials.psk,
			userkey: node.credentials.userkey,
			reuse: strToBool(node.protocol_options.reuse)
		};
	case 'ssh':
		return {
			user: node.credentials.user,
			password: node.credentials.password,
			private_key: ssh_private_key(node.credentials.private_key),
			private_key_passphrase: node.credentials.private_key_passphrase
		};
	case 'hysteria':
		return {
			auth: (node.protocol_options.auth_type === 'base64') ? node.protocol_options.auth_payload : null,
			auth_str: (node.protocol_options.auth_type === 'string') ? node.protocol_options.auth_payload : null
		};
	default:
		return {
			username: node.credentials.username,
			uuid: node.credentials.uuid,
			password: node.credentials.password,
			method: node.credentials.method
		};
	}
}

/* Per-protocol option fields, keyed by the same canonical names the model
 * exposes. Anything not modelled here is still in node.protocol_options
 * (which is itself populated from the protocol's PROTOCOL_OPTIONS row in
 * the Loader). */
export const OPTION_FIELDS = {
	vless: {
		flow: (node) => node.protocol_options.flow
		/* No udp_over_tcp here: sing-box 1.14 rejects that field on a vless
		 * outbound ("json: unknown field").  It used to be emitted, so a
		 * node whose type was switched from shadowsocks to vless kept the
		 * stale UCI option and produced a config sing-box refused outright.
		 * The node form never offered the option for vless anyway. */
	},
	/* `mode` (snell v6 traffic shaping) is deliberately absent: sing-box
	 * 1.14 rejects it as an outbound field, and the node form only offered
	 * it for snell_version 6, which this sing-box does not support either. */
	snell: {
		version: (node) => strToInt(node.protocol_options.version) || 4,
		obfs_mode: (node) => node.protocol_options.obfs_mode || null,
		obfs_host: (node) => node.protocol_options.obfs_host || null
	},
	/* A4.1: shadowsocks. SIP002 plugin support is emitted only when both
	 * plugin and plugin_opts are present, matching the generator's ternary
	 * that emits `plugin: ...` unconditionally and lets removeBlankAttrs
	 * drop empties. `udp_over_tcp` mirrors the vless shape. */
	shadowsocks: {
		plugin: (node) => node.protocol_options.plugin || null,
		plugin_opts: (node) => node.protocol_options.plugin_opts || null,
		udp_over_tcp: (node) => (node.protocol_options.udp_over_tcp === '1') ? {
			enabled: true,
			version: strToInt(node.protocol_options.udp_over_tcp_version)
		} : null
	},
	/* A4.2: anytls idle session tuning (sing-box 1.14 lets the client probe
	 * upstream sessions and proactively close stuck ones). */
	anytls: {
		idle_session_check_interval: (node) => strToTime(node.protocol_options.idle_session_check_interval),
		idle_session_timeout: (node) => strToTime(node.protocol_options.idle_session_timeout),
		min_idle_session: (node) => strToInt(node.protocol_options.min_idle_session)
	},
	/* A4.3: http - no protocol-specific options; transport / tls / multiplex
	 * are shared. */
	http: {},
	/* A4.4: socks.  The node form offers UDP-over-TCP for socks and sing-box
	 * accepts it on the socks outbound, but the adapter never emitted it, so
	 * the setting was silently ignored. */
	socks: {
		version: (node) => node.protocol_options.version,
		udp_over_tcp: (node) => (node.protocol_options.udp_over_tcp === '1') ? {
			enabled: true,
			version: strToInt(node.protocol_options.udp_over_tcp_version)
		} : null
	},
	/* A4.5: tuic */
	tuic: {
		congestion_control: (node) => node.protocol_options.congestion_control,
		udp_relay_mode: (node) => node.protocol_options.udp_relay_mode,
		udp_over_stream: (node) => strToBool(node.protocol_options.udp_over_stream),
		zero_rtt_handshake: (node) => strToBool(node.protocol_options.zero_rtt_handshake),
		heartbeat: (node) => strToTime(node.protocol_options.heartbeat)
	},
	/* A4.6: trojan - no protocol-specific options. */
	trojan: {},
	/* A4.7: shadowtls */
	shadowtls: {
		version: (node) => strToInt(node.protocol_options.version)
	},
	/* A4.8: hysteria (v1). The generator emits two fields: `auth` when the
	 * payload is base64, `auth_str` when it is a string. Node.validate()
	 * only catches the obvious case; the conditional keeps the table-driven
	 * shape.
	 *
	 * obfs is the plain obfuscation password string here.  The node form
	 * only offers the password for v1 (the type selector is hysteria2-only)
	 * and sing-box rejects the {type, password} object on a hysteria
	 * outbound - that shape belongs to hysteria2.  Emitting the object made
	 * any obfuscated hysteria node produce a config sing-box refused. */
	hysteria: {
		auth: (node) => (node.protocol_options.auth_type === 'base64') ? node.protocol_options.auth_payload : null,
		auth_str: (node) => (node.protocol_options.auth_type === 'string') ? node.protocol_options.auth_payload : null,
		up_mbps: (node) => strToInt(node.protocol_options.up_mbps),
		down_mbps: (node) => strToInt(node.protocol_options.down_mbps),
		hop_interval: (node) => strToTime(node.protocol_options.hop_interval),
		obfs: (node) => node.protocol_options.obfs_password || null
	},
	/* A4.9: hysteria2 - extends hysteria with hop_interval_max /
	 * server_ports / bbr_profile / disable_chrome_parrot. The obfs
	 * shape is the same. Note sing-box 1.14 uses `server_ports`
	 * (port hopping list), not `hopping_port` - the latter is the
	 * UCI option name, so the rename happens here. */
	hysteria2: {
		auth: (node) => (node.protocol_options.auth_type === 'base64') ? node.protocol_options.auth_payload : null,
		auth_str: (node) => (node.protocol_options.auth_type === 'string') ? node.protocol_options.auth_payload : null,
		up_mbps: (node) => strToInt(node.protocol_options.up_mbps),
		down_mbps: (node) => strToInt(node.protocol_options.down_mbps),
		hop_interval: (node) => strToTime(node.protocol_options.hop_interval),
		hop_interval_max: (node) => strToTime(node.protocol_options.hop_interval_max),
		server_ports: (node) => node.protocol_options.hopping_port,
		obfs: (node) => node.protocol_options.obfs_type ? {
			type: node.protocol_options.obfs_type,
			password: node.protocol_options.obfs_password
		} : null,
		bbr_profile: (node) => node.protocol_options.bbr_profile || null,
		disable_chrome_parrot: (node) => (node.protocol_options.disable_chrome_parrot === '1') ? true : null
	},
	/* A4.10: vmess */
	vmess: {
		alter_id: (node) => strToInt(node.protocol_options.alter_id),
		security: (node) => node.protocol_options.security,
		global_padding: (node) => strToBool(node.protocol_options.global_padding)
	},
	/* SSH: host-key pinning and the client banner, matching sing-box's ssh
	 * outbound field names. */
	ssh: {
		client_version: (node) => node.protocol_options.client_version || null,
		host_key: (node) => node.protocol_options.host_key || null,
		host_key_algorithms: (node) => node.protocol_options.host_key_algorithms || null
	}
};

/* --- shared builders ---------------------------------------------------- */

function build_multiplex(mux) {
	if (!mux || mux.enabled !== '1')
		return null;

	return {
		enabled: true,
		protocol: mux.protocol,
		max_connections: strToInt(mux.max_connections),
		min_streams: strToInt(mux.min_streams),
		max_streams: strToInt(mux.max_streams),
		padding: strToBool(mux.padding),
		brutal: (mux.brutal && mux.brutal.enabled === '1') ? {
			enabled: true,
			up_mbps: strToInt(mux.brutal.up_mbps),
			down_mbps: strToInt(mux.brutal.down_mbps)
		} : null
	};
}

/* --- adapter ------------------------------------------------------------ */

/* Both validation layers as one list. Standalone (not a method) because the
 * OutboundFactory literal below cannot reference itself during its own
 * initialisation: ucode resolves the binding lexically and throws
 * "Can't access lexical declaration before initialization". */
function outbound_problems(node) {
	return [
		...Node.validate(node),
		...protocol_problems(node)
	];
}

/* Node -> sing-box outbound object.  Pure: no UCI, no module state, no file
 * access; `mark` is passed in instead of read from a global.
 *
 * Standalone for the same reason outbound_problems() is: the literal below
 * cannot name OutboundFactory in any nested scope, not even inside an arrow
 * body, without tripping ucode's "Can't access lexical declaration before
 * initialization" check.  Validation is done by the callers. */
function build_outbound(node, mark) {
	const outbound = {
		type: node.type,
		tag: Node.tag(node),
		routing_mark: strToInt(mark)
	};

	for (let field, spec in COMMON_FIELDS)
		outbound[field] = resolve(spec, node);

	const claims = CLAIM_FIELDS(node);
	for (let field, value in claims)
		outbound[field] = value;

	const options = OPTION_FIELDS[node.type] || {};
	for (let field, spec in options)
		outbound[field] = resolve(spec, node);

	outbound.multiplex = build_multiplex(node.multiplex);
	outbound.tls = buildTLSObject(node.tls, false);
	outbound.transport = buildTransportObject(node.transport, false);

	if (node.type === 'direct')
		outbound.proxy_protocol = strToInt(node.common.proxy_protocol);

	/* removeBlankAttrs() is what the generator applies before writing, and
	   it drops every null the field tables produced. Cleaning here means
	   this function returns the final artifact, so a golden-snapshot test
	   can compare it against what sing-box would actually be handed. */
	return removeBlankAttrs(outbound);
}

export const OutboundFactory = {
	/* Validation split out of create() so a caller can decide whether a
	 * broken node is fatal.  Two-layer: Node.validate() covers
	 * cross-protocol rules, protocol_problems() the per-protocol ones. */
	problems: outbound_problems,

	/* True when create() would succeed.  Used to prune optional node lists
	 * (urltest candidates) so one misconfigured node cannot abort the
	 * entire configuration. */
	buildable: (node) => length(outbound_problems(node)) === 0,

	/* Node -> { outbound, problems }.  Same result as create() but never
	 * dies, for nodes the user only *may* route through. */
	tryCreate: (node, mark) => {
		const problems = outbound_problems(node);

		if (length(problems))
			return { outbound: null, problems: problems };

		return { outbound: build_outbound(node, mark), problems: [] };
	},

	/* Node -> sing-box outbound object, or die() when the node is not
	 * buildable.  Use problems()/buildable()/tryCreate() for nodes whose
	 * breakage must not be fatal (urltest candidates). */
	create: (node, mark) => {
		const problems = outbound_problems(node);

		if (length(problems))
			die(`node '${node.id}': ${join(', ', problems)}\n`);

		return build_outbound(node, mark);
	}
};

/* --- WireGuard endpoint ------------------------------------------------- */

/* WireGuard is emitted as a
 * sing-box *endpoint*, not an outbound, so it needs its own builder.
 * That builder used to live in generator/outbound.uc, which meant the
 * generator still held protocol business logic for one protocol. It
 * now lives here, next to the outbound factory, and the generator only
 * decides *when* an endpoint is needed (routing-mode split, urltest
 * resolution).
 *
 * `ctx` carries the process-wide UDP tuning the runtime owns
 * (udp_mapping / udp_filtering / udp_nat_max) - same shape
 * build_outbounds() already passes around, so callers do not change. */
function build_endpoint(node, ctx) {
	const opts = node.protocol_options || {};
	const common = node.common || {};

	return {
		type: node.type,
		tag: 'cfg-' + node.id + '-out',
		address: opts.local_address,
		mtu: strToInt(opts.mtu),
		private_key: opts.private_key,
		peers: (node.type === 'wireguard') ? [
			{
				address: node.address,
				port: strToInt(node.port),
				allowed_ips: [
					'0.0.0.0/0',
					'::/0'
				],
				persistent_keepalive_interval: strToInt(opts.persistent_keepalive_interval),
				public_key: opts.peer_public_key,
				pre_shared_key: opts.pre_shared_key,
				reserved: parse_port(opts.reserved),
			}
		] : null,
		system: (node.type === 'wireguard') ? false : null,
		tcp_fast_open: strToBool(common.tcp_fast_open),
		tcp_multi_path: strToBool(common.tcp_multi_path),
		udp_fragment: strToBool(common.udp_fragment),
		udp_mapping: !isEmpty(ctx.udp_mapping) ? ctx.udp_mapping : null,
		udp_filtering: !isEmpty(ctx.udp_filtering) ? ctx.udp_filtering : null,
		udp_nat_max: ctx.udp_nat_max
	};
}

export const EndpointFactory = {
	/* Node -> sing-box endpoint object, or null when there is nothing to
	 * build. Unlike OutboundFactory.create() this never dies: an endpoint
	 * is only ever reached for a node the routing layer already selected,
	 * and the caller treats null as "skip this endpoint". */
	create: (node, ctx) => {
		if (type(node) !== 'object' || isEmpty(node))
			return null;

		return build_endpoint(node, ctx);
	}
};

/* --- server inbound ----------------------------------------------------- */

/* The server half of the Adapter. Same data-table approach as
 * the outbound side: the protocol differences are *fields*, not
 * behaviour, so they are expressed as tables rather than a branch per
 * protocol. generator/server.uc used to spell every one of these out
 * inline while reading flat UCI keys off the section dict.
 *
 * Adding a protocol means adding two rows: INBOUND_CREDENTIALS and
 * INBOUND_OPTIONS in model.uc, and an INBOUND_OPTION_FIELDS row here. */

/* Listener-level fields every inbound emits. Each value is a function of
 * the Inbound, or null (which removeBlankAttrs() strips). */
const INBOUND_COMMON_FIELDS = {
	listen: (inbound) => inbound.address || '::',
	listen_port: (inbound) => strToInt(inbound.port),
	bind_interface: (inbound) => inbound.common.bind_interface,
	reuse_addr: (inbound) => strToBool(inbound.common.reuse_addr),
	tcp_fast_open: (inbound) => strToBool(inbound.common.tcp_fast_open),
	tcp_multi_path: (inbound) => strToBool(inbound.common.tcp_multi_path),
	udp_fragment: (inbound) => strToBool(inbound.common.udp_fragment),
	udp_timeout: (inbound) => strToTime(inbound.common.udp_timeout),
	network: (inbound) => inbound.common.network
};

/* Listener fields a protocol must NOT be given even when the UCI section
 * happens to carry the option. sing-box 1.14's snell inbound takes no
 * udp_fragment / udp_timeout / network; the previous generator had a
 * dedicated build_snell_inbound() that omitted them, and this table
 * keeps that behaviour instead of relying on the user not setting them. */
const INBOUND_COMMON_OMIT = {
	snell: ['udp_fragment', 'udp_timeout', 'network']
};

/* Protocols whose sing-box inbound has no users[] block. snell carries a
 * single top-level psk, shadowsocks a top-level password + method; giving
 * either of them a users[] entry makes sing-box reject the section
 * ("snell: bad user key" - the users entry is interpreted as an
 * additional user key). */
const INBOUND_NO_USERS = ['shadowsocks', 'snell'];

/* Credential fields the inbound emits, keyed by the sing-box field
 * name. Most protocols put them in the users[] block (below); snell
 * wants a single top-level `psk`, and shadowsocks / shadowtls a
 * top-level password (plus method for shadowsocks), so those are
 * handled here. */
function INBOUND_CLAIM_FIELDS(inbound) {
	switch (inbound.type) {
	case 'snell':
		return { psk: inbound.credentials.psk };
	case 'shadowsocks':
		return {
			method: inbound.credentials.method,
			password: inbound.credentials.password
		};
	case 'shadowtls':
		return { password: inbound.credentials.password };
	default:
		return {};
	}
}

/* The users[] entry. sing-box wants one user per inbound; every
 * protocol not listed in INBOUND_NO_USERS accepts the block. */
function build_inbound_user(inbound) {
	const creds = inbound.credentials || {};
	const opts = inbound.protocol_options || {};

	return {
		name: !(inbound.type in ['http', 'mixed', 'naive', 'socks']) ?
			'cfg-' + inbound.id + '-server' : null,
		username: creds.username,
		password: creds.password,

		/* Hysteria (1) authentication: exactly one of the two
		 * spellings, selected by the auth type. */
		auth: (opts.auth_type === 'base64') ? creds.auth_base64 : null,
		auth_str: (opts.auth_type === 'string') ? creds.auth_str : null,

		uuid: creds.uuid,

		/* VLESS / VMess. Both are per-user fields: sing-box has no
		 * top-level `flow` on a vless inbound nor `alterId` on a vmess
		 * one, which is why INBOUND_OPTION_FIELDS has no row for these
		 * two protocols. */
		flow: opts.flow,
		alterId: strToInt(opts.alter_id)
	};
}

/* Per-protocol inbound fields, keyed by the sing-box field name. Only
 * the protocols whose sing-box inbound carries something beyond the
 * shared listener/credential/TLS/transport set need a row. */
const INBOUND_OPTION_FIELDS = {
	anytls: {
		padding_scheme: (inbound) => inbound.protocol_options.padding_scheme
	},
	/* Hysteria (1) and Hysteria2 share three fields and differ on
	 * obfs: v1 carries the obfuscation as a plain password string,
	 * v2 as a {type, password, min_packet_size, max_packet_size}
	 * object. Emitting v1's obfs as a string is what the generator
	 * always did - the {type, ...} shape on a v1 inbound is a
	 * sing-box rejection. */
	hysteria: {
		up_mbps: (inbound) => strToInt(inbound.protocol_options.up_mbps),
		down_mbps: (inbound) => strToInt(inbound.protocol_options.down_mbps),
		obfs: (inbound) => inbound.protocol_options.obfs_password,
		ignore_client_bandwidth: (inbound) => strToBool(inbound.protocol_options.ignore_client_bandwidth),
		masquerade: (inbound) => inbound.protocol_options.masquerade
	},
	hysteria2: {
		up_mbps: (inbound) => strToInt(inbound.protocol_options.up_mbps),
		down_mbps: (inbound) => strToInt(inbound.protocol_options.down_mbps),
		obfs: (inbound) => inbound.protocol_options.obfs_type ? {
			type: inbound.protocol_options.obfs_type,
			password: inbound.protocol_options.obfs_password,
			min_packet_size: strToInt(inbound.protocol_options.obfs_min_packet_size),
			max_packet_size: strToInt(inbound.protocol_options.obfs_max_packet_size)
		/* hysteria2 takes an obfs *object* here.  Falling back to the bare
		 * password string (which is what hysteria v1 wants) makes sing-box
		 * reject the inbound with "cannot unmarshal string into Go struct
		 * field Hysteria2InboundOptions.obfs" - so no type means no obfs. */
		} : null,
		ignore_client_bandwidth: (inbound) => strToBool(inbound.protocol_options.ignore_client_bandwidth),
		masquerade: (inbound) => inbound.protocol_options.masquerade
	},
	snell: {
		version: (inbound) => strToInt(inbound.protocol_options.version) || 5,
		obfs_mode: (inbound) => inbound.protocol_options.obfs_mode
		/* no `mode`: sing-box 1.14 rejects it on a snell inbound; it
		 * was a v6-only option and v6 is not supported. */
	},
	tuic: {
		congestion_control: (inbound) => inbound.protocol_options.congestion_control,
		auth_timeout: (inbound) => strToTime(inbound.protocol_options.auth_timeout),
		zero_rtt_handshake: (inbound) => strToBool(inbound.protocol_options.zero_rtt_handshake),
		heartbeat: (inbound) => strToTime(inbound.protocol_options.heartbeat)
	}
	/* No row for vless / vmess: both protocols' only per-protocol knobs
	 * (flow, alterId) are per-user fields, emitted by
	 * build_inbound_user() above. sing-box has no top-level `flow` on a
	 * vless inbound nor `alterId` on a vmess one, so adding a row here
	 * would emit a field sing-box rejects. The Loader still loads them
	 * into inbound.protocol_options (INBOUND_OPTIONS in model.uc), which
	 * is where build_inbound_user() reads them from.
	 *
	 * No row for trojan / shadowtls either: everything they carry is
	 * shared (credentials / TLS / transport). */
};

/* The server-only TLS tail, re-keyed from the Inbound's canonical
 * names into the UCI option names buildTLSObject() reads. That shared
 * builder is exercised directly by tests/ucode/test_tls_transport.uc
 * and is used by both the client and the server path, so its signature
 * stays as it is; this is the single place the flat names survive. */
function build_tls_server_extras(tls_server) {
	const extras = {};

	for (let canonical, uci in INBOUND_TLS_SERVER)
		extras[uci] = tls_server[canonical];

	return extras;
}

/* Build the inbound `multiplex` block. The server side has no
 * max_connections / min_streams / max_streams (those are client
 * dialling knobs), so this is deliberately a smaller shape than the
 * outbound factory's build_multiplex(). */
function build_inbound_multiplex(mux) {
	if (!mux || mux.enabled !== '1')
		return null;

	return {
		enabled: true,
		padding: strToBool(mux.padding),
		brutal: (mux.brutal && mux.brutal.enabled === '1') ? {
			enabled: true,
			up_mbps: strToInt(mux.brutal.up_mbps),
			down_mbps: strToInt(mux.brutal.down_mbps)
		} : null
	};
}

/* Inbound -> sing-box inbound object. Pure: no UCI, no file access. */
function build_inbound(inbound) {
	const out = {
		type: inbound.type,
		tag: Inbound.tag(inbound)
	};

	const omit = INBOUND_COMMON_OMIT[inbound.type] || [];

	for (let field, spec in INBOUND_COMMON_FIELDS) {
		if (field in omit)
			continue;
		out[field] = resolve(spec, inbound);
	}

	const claims = INBOUND_CLAIM_FIELDS(inbound);
	for (let field, value in claims)
		out[field] = value;

	const options = INBOUND_OPTION_FIELDS[inbound.type] || {};
	for (let field, spec in options)
		out[field] = resolve(spec, inbound);

	out.users = (inbound.type in INBOUND_NO_USERS) ? null : [ build_inbound_user(inbound) ];

	out.multiplex = build_inbound_multiplex(inbound.multiplex);
	out.tls = buildTLSObject(inbound.tls, true, build_tls_server_extras(inbound.tls_server || {}));
	out.transport = buildTransportObject(inbound.transport, true);

	/* Same contract as build_outbound(): return the final artifact so a
	 * golden snapshot can compare it against what sing-box is handed. */
	return removeBlankAttrs(out);
}

/* Per-protocol requirements, mirroring OutboundFactory's
 * REQUIRED_CREDENTIALS: what the sing-box inbound for this protocol
 * needs in order to be usable. */
const REQUIRED_INBOUND_CREDENTIALS = {
	vless:     ['uuid'],
	vmess:     ['uuid'],
	trojan:    ['password'],
	hysteria2: ['password'],
	tuic:      ['uuid', 'password'],
	shadowsocks: ['password'],
	snell:     ['psk'],
	anytls:    ['password'],
	shadowtls: ['password'],
	/* These run without a credential: http / mixed / socks / naive can
	 * be anonymous, and hysteria (1) may carry its auth out of band. */
	hysteria:  [],
	http:      [],
	mixed:     [],
	naive:     [],
	socks:     []
};

function inbound_problems(inbound) {
	let problems = [...Inbound.validate(inbound)];

	const required = REQUIRED_INBOUND_CREDENTIALS[inbound.type] || [];
	const creds = inbound.credentials || {};

	for (let field in required)
		if (!creds[field])
			problems = [...problems, `${inbound.type} requires ${field}`];

	return problems;
}

export const InboundFactory = {
	problems: inbound_problems,

	buildable: (inbound) => length(inbound_problems(inbound)) === 0,

	/* Inbound -> { inbound, problems }. Never dies, so a single broken
	 * server section can be reported by the caller instead of taking
	 * the whole server instance down. */
	tryCreate: (inbound) => {
		const problems = inbound_problems(inbound);

		if (length(problems))
			return { inbound: null, problems: problems };

		return { inbound: build_inbound(inbound), problems: [] };
	},

	/* Inbound -> sing-box inbound object, or die(). */
	create: (inbound) => {
		const problems = inbound_problems(inbound);

		if (length(problems))
			die(`inbound '${inbound.id}': ${join(', ', problems)}\n`);

		return build_inbound(inbound);
	}
};
