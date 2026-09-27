/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * The per-scheme parsers in
 * parser/protocols.uc produce a FLAT UCI-key dict; that is their output
 * shape. The Adapter, the Loader, the policy step and the Repository's
 * write path all think in the canonical Node shape instead: nested tls /
 * transport / multiplex / credentials / protocol_options sub-objects.
 *
 * normalize() is the crossing point: every caller that needs the
 * canonical Node - the subscription orchestrator, the RPC that imports a
 * share link, tests - runs the parsed config through it. parser/flatten.uc
 * is the inverse and is used only where UCI has to be written, which is
 * the Repository's apply_nodes().
 *
 * The mapping is sourced from parser/mapping.uc (canonical -> UCI)
 * so the Loader, the Adapter and the parser cannot drift apart.
 */

'use strict';

import { PROTOCOL_TO_UCI } from './mapping.uc';

/* Pick every field that PROTOCOL_TO_UCI maps for this protocol off
 * the flat config and rename it from UCI to its canonical name. The
 * result is the protocol_options sub-object. Fields the parser wrote
 * that are not mapped (e.g. a stale `vless_udp_over_tcp` left over
 * from a shadowsocks -> vless type switch) are dropped here, which is
 * the same "stale UCI option becomes a config error" failure the
 * Loader has been guarding against via PROTOCOL_OPTIONS. */
function build_protocol_options(protocol, flat) {
	const map = PROTOCOL_TO_UCI[protocol] || {};
	const out = {};

	for (let canonical, uci in map) {
		if (uci in flat) {
			const value = flat[uci];
			/* Empty-string or null means "absent": do not propagate
			 * to the canonical side either. */
			if (value !== '' && value !== null)
				out[canonical] = value;
		}
	}

	return out;
}

/* TLS fields are shared across protocols, not per-protocol, so they
 * live outside PROTOCOL_TO_UCI. The Loader uses the same shape
 * (load_tls() in config/loader.uc), so we mirror it. */
function build_tls(flat) {
	const tls = {
		enabled: flat.tls,
		server_name: flat.tls_sni,
		insecure: flat.tls_insecure,
		alpn: flat.tls_alpn,
		min_version: flat.tls_min_version,
		max_version: flat.tls_max_version,
		handshake_timeout: flat.tls_handshake_timeout,
		cipher_suites: flat.tls_cipher_suites,
		cert_path: flat.tls_cert_path,
		ech: {
			enabled: flat.tls_ech,
			config: flat.tls_ech_config,
			config_path: flat.tls_ech_config_path
		},
		utls: {
			fingerprint: flat.tls_utls
		},
		reality: {
			enabled: flat.tls_reality,
			public_key: flat.tls_reality_public_key,
			short_id: flat.tls_reality_short_id
		}
	};

	return tls;
}

/* Transport fields are also shared; mirror the shape the Loader's
 * load_transport() produces. Returns `{ type: null }` when the parser
 * did not write a transport. */
function build_transport(flat) {
	const t = flat.transport;
	if (t == null || t === '')
		return { type: null };

	return {
		type: t,
		host: flat.http_host || flat.httpupgrade_host,
		path: flat.http_path || flat.ws_path,
		headers: flat.ws_host ? { Host: flat.ws_host } : null,
		method: flat.http_method,
		max_early_data: flat.websocket_early_data,
		early_data_header_name: flat.websocket_early_data_header,
		service_name: flat.grpc_servicename,
		idle_timeout: flat.http_idle_timeout,
		ping_timeout: flat.http_ping_timeout,
		permit_without_stream: flat.grpc_permit_without_stream
	};
}

/* Common fields that every outbound protocol carries. Mirrors the
 * Loader's load_common(). */
function build_common(flat) {
	return {
		proxy_protocol: flat.proxy_protocol,
		tcp_fast_open: flat.tcp_fast_open,
		tcp_multi_path: flat.tcp_multi_path,
		udp_fragment: flat.udp_fragment
	};
}

/* Multiplex fields - mirrors the Loader's load_multiplex(). */
function build_multiplex(flat) {
	return {
		enabled: flat.multiplex,
		protocol: flat.multiplex_protocol,
		max_connections: flat.multiplex_max_connections,
		min_streams: flat.multiplex_min_streams,
		max_streams: flat.multiplex_max_streams,
		padding: flat.multiplex_padding,
		brutal: {
			enabled: flat.multiplex_brutal,
			up_mbps: flat.multiplex_brutal_up,
			down_mbps: flat.multiplex_brutal_down
		}
	};
}

/* Credentials: pull every UCI key the protocol's CREDENTIALS row lists
 * (canonical -> UCI) and put them under the canonical name. Empty /
 * null values stay null so the Adapter's null-strip pass keeps the
 * field out of the emitted sing-box JSON. */
const CREDENTIALS = {
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
	ssh:     { user: 'username', password: 'password',
	           private_key: 'ssh_priv_key', private_key_passphrase: 'ssh_priv_key_pp' },
	anytls:  { password: 'password' },
	shadowtls: { password: 'password' },
	direct:  {}
};

function build_credentials(protocol, flat) {
	const map = CREDENTIALS[protocol] || {};
	const out = {};

	for (let canonical, uci in map)
		out[canonical] = flat[uci];

	return out;
}

/* Top-level: produce a Node-shaped object from the parser's flat
 * output. Returns null when the input is null / empty so callers can
 * do `normalize(parse_uri(uri))` and propagate parse failures
 * unchanged. */
export function normalize(flat) {
	if (!flat)
		return null;

	const protocol = flat.type;

	return {
		/* identity */
		id: null,
		name: flat.label,
		type: protocol,

		/* endpoint */
		address: flat.address,
		port: flat.port,

		/* sub-objects */
		common: build_common(flat),
		credentials: build_credentials(protocol, flat),
		tls: build_tls(flat),
		transport: build_transport(flat),
		multiplex: build_multiplex(flat),
		protocol_options: build_protocol_options(protocol, flat)
	};
};