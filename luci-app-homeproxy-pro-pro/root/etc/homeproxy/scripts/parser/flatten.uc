/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * The inverse of
 * parser/normalize.uc. Where normalize() turns the parser's flat
 * UCI-key output into the canonical Node shape the Adapter reads,
 * flatten() turns a canonical Node back into the flat UCI-key dict
 * UCI needs.
 *
 * The Repository's apply_nodes() is the only production caller: it is
 * the one boundary where a canonical Node becomes UCI keys, which is
 * what lets the orchestrator, the filter and the policy step work on
 * canonical Nodes alone.
 *
 * Same single-source-of-truth discipline: every canonical -> UCI
 * mapping comes from parser/mapping.uc's PROTOCOL_TO_UCI. Adding a
 * protocol option is a one-place change in mapping.uc, and both
 * directions pick it up.
 *
 * The output is the same shape the parser emits plus whatever
 * metadata fields the orchestrator (or Repository) added
 * (label, grouphash, isExisting). flatten() does not invent or
 * strip them: it only does the canonical-sub-object -> flat-key
 * expansion, then layers identity on top, then copies metadata
 * through unchanged.
 *
 * `null` / `undefined` canonical values are written as null too -
 * UCI serialises null as an empty option, which the Loader reads
 * back as null, so the round-trip is preserved.
 */

'use strict';

import { PROTOCOL_TO_UCI } from './mapping.uc';

/* Per-protocol option fields: canonical -> UCI keys. Mirrors the
 * loader's load_protocol_options() / normalize.uc's
 * build_protocol_options(). */
function flatten_protocol_options(protocol, node) {
	const map = PROTOCOL_TO_UCI[protocol] || {};
	const opts = node.protocol_options || {};
	const out = {};

	for (let canonical, uci in map)
		out[uci] = opts[canonical];

	return out;
}

/* TLS fields: shared across protocols, sourced from the canonical
 * `tls` sub-object. Mirrors normalize.uc's build_tls(). */
function flatten_tls(node) {
	const tls = node.tls || {};
	const ech = tls.ech || {};
	const utls = tls.utls || {};
	const reality = tls.reality || {};

	return {
		tls: tls.enabled,
		tls_sni: tls.server_name,
		tls_insecure: tls.insecure,
		tls_alpn: tls.alpn,
		tls_min_version: tls.min_version,
		tls_max_version: tls.max_version,
		tls_handshake_timeout: tls.handshake_timeout,
		tls_cipher_suites: tls.cipher_suites,
		tls_cert_path: tls.cert_path,
		tls_ech: ech.enabled,
		tls_ech_config: ech.config,
		tls_ech_config_path: ech.config_path,
		tls_utls: utls.fingerprint,
		tls_reality: reality.enabled,
		tls_reality_public_key: reality.public_key,
		tls_reality_short_id: reality.short_id
	};
}

/* Transport: share-link parsers spread transport fields across
 * multiple UCI keys (http_host, ws_host, ws_path, httpupgrade_host,
 * http_path, http_method, websocket_early_data(_header),
 * grpc_servicename, http_idle_timeout, http_ping_timeout,
 * grpc_permit_without_stream). Mirrors normalize.uc's
 * build_transport(). */
function flatten_transport(node) {
	const t = (node.transport || {}).type;
	const out = { transport: t || null };

	if (!t)
		return out;

	/* The host / path UCI option names depend on the transport: a ws
	 * transport stores them as ws_path / ws_host, an httpupgrade as
	 * http_path / httpupgrade_host, plain http as http_host / http_path.
	 * normalize() collapses both path spellings into transport.path, so
	 * flatten() has to pick the right one back or a re-written node
	 * would sprout an http_path the parser never produced (and drop the
	 * ws_path the loader's `http_path || ws_path` fallback had read). */
	if (t === 'ws') {
		out.ws_host = node.transport.headers?.Host;
		out.ws_path = node.transport.path;
	}

	if (t === 'httpupgrade') {
		out.httpupgrade_host = node.transport.host;
		out.http_path = node.transport.path;
	}

	if (t === 'http') {
		out.http_host = node.transport.host;
		out.http_path = node.transport.path;
		out.http_method = node.transport.method;
	}

	if (t === 'grpc')
		out.grpc_servicename = node.transport.service_name;

	out.http_idle_timeout = node.transport.idle_timeout;
	out.http_ping_timeout = node.transport.ping_timeout;
	out.grpc_permit_without_stream = node.transport.permit_without_stream;
	out.websocket_early_data_header = node.transport.early_data_header_name;
	out.websocket_early_data = node.transport.max_early_data;

	return out;
}

/* Common: every outbound protocol carries these. */
function flatten_common(node) {
	const c = node.common || {};
	return {
		proxy_protocol: c.proxy_protocol,
		tcp_fast_open: c.tcp_fast_open,
		tcp_multi_path: c.tcp_multi_path,
		udp_fragment: c.udp_fragment
	};
}

/* Multiplex: shares a brutal nested sub-shape with normalize.uc. */
function flatten_multiplex(node) {
	const m = node.multiplex || {};
	const brutal = m.brutal || {};

	return {
		multiplex: m.enabled,
		multiplex_protocol: m.protocol,
		multiplex_max_connections: m.max_connections,
		multiplex_min_streams: m.min_streams,
		multiplex_max_streams: m.max_streams,
		multiplex_padding: m.padding,
		multiplex_brutal: brutal.enabled,
		multiplex_brutal_up: brutal.up_mbps,
		multiplex_brutal_down: brutal.down_mbps
	};
}

/* Credentials: same CREDENTIALS table as normalize.uc, traversed
 * in reverse: canonical credential name -> UCI option. */
const CREDENTIALS = {
	vless: { uuid: 'uuid' },
	vmess: { uuid: 'uuid' },
	trojan: { password: 'password' },
	hysteria: { auth_str: 'auth', auth_base64: 'auth' },
	hysteria2: { password: 'password' },
	tuic: { uuid: 'uuid', password: 'password' },
	shadowsocks: { password: 'password', method: 'shadowsocks_encrypt_method' },
	socks: { username: 'username', password: 'password' },
	http: { username: 'username', password: 'password' },
	snell: { psk: 'password', userkey: 'snell_userkey' },
	ssh: { user: 'username', password: 'password',
	       private_key: 'ssh_priv_key', private_key_passphrase: 'ssh_priv_key_pp' },
	anytls: { password: 'password' },
	shadowtls: { password: 'password' },
	direct: {}
};

function flatten_credentials(protocol, node) {
	const map = CREDENTIALS[protocol] || {};
	const creds = node.credentials || {};
	const out = {};

	for (let canonical, uci in map)
		out[uci] = creds[canonical];

	return out;
}

/* The full pipeline, returning a flat UCI-key dict. Metadata that
 * the orchestrator / Repository attaches to the canonical Node
 * (label, grouphash) is not a canonical sub-object, so we copy
 * those fields through explicitly rather than walk `keys(node)`
 * and pull whatever happens to be there.
 *
 * `isExisting` is deliberately NOT copied: it is a within-run
 * marker Repository sets after a successful write, used to skip
 * re-adding in the same loop. It is never written to / read from
 * UCI. Identity (id / type / address / port) and `name` (which
 * becomes the UCI `label` option) are the Adapter's identity
 * half; everything else is the metadata tail. */
function copy_meta(out, node) {
	if ('label' in node)
		out.label = node.label;
	if ('grouphash' in node)
		out.grouphash = node.grouphash;
}

/* Top-level: take a canonical Node, return a flat UCI-key dict
 * suitable for uci.set() per key. Returns null when the input is
 * null / empty, mirroring normalize()'s `null -> null` contract
 * so callers can compose `flatten(normalize(parse_uri(uri)))`. */
export function flatten(node) {
	if (!node)
		return null;

	const protocol = node.type;
	const out = {
		type: protocol,
		address: node.address,
		port: node.port,
		label: node.name
	};

	/* Identity sub-fields: drop empties so a freshly-saved
	 * canonical Node (which always carries the full shape, even
	 * when `null`) does not suddenly litter /etc/config with
	 * `multiplex_max_connections ''` entries. The Loader treats
	 * null and absent the same, so this is observably equivalent. */
	const sub = {
		...flatten_common(node),
		...flatten_credentials(protocol, node),
		...flatten_tls(node),
		...flatten_transport(node),
		...flatten_multiplex(node),
		...flatten_protocol_options(protocol, node)
	};

	/* ucode has no `undefined`: an absent key reads as null, so a
	 * single null check covers both. */
	for (let k, v in sub)
		if (v !== null)
			out[k] = v;

	copy_meta(out, node);

	return out;
};