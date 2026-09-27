/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Single source of truth for the canonical-name <-> UCI-option-name
 * mapping per protocol. The same mapping used to live in three places:
 *
 *   - parse_uri.uc (wrote UCI-flat keys directly: `tls`, `tls_sni`,
 *     `vless_flow`, `shadowsocks_encrypt_method`, ...)
 *   - config/loader.uc PROTOCOL_OPTIONS (canonical -> UCI)
 *   - config/adapter.uc OPTION_FIELDS (canonical -> adapter code)
 *
 * The Loader's PROTOCOL_OPTIONS is derived from the table in this file,
 * and both directions of the pipeline read it: normalize.uc renames UCI
 * keys to canonical names, flatten.uc renames them back on the way to
 * UCI. Adding a protocol option is one edit here, not one per layer.
 *
 * `keys()` direction: every row's left side is the canonical name the
 * Loader hands the Adapter; the right side is the UCI option name the
 * Loader reads and the Repository writes. Keep them sorted by
 * canonical name so a diff that adds a row is obvious.
 */

'use strict';

/* `canonical -> uci` for per-protocol options. Anything not listed here
 * is not part of the domain contract for that protocol (the form might
 * still surface it, the Adapter ignores it). */
export const PROTOCOL_TO_UCI = {
	vless: {
		flow: 'vless_flow',
		packet_encoding: 'packet_encoding'
		/* udp_over_tcp used to be here.  It is a shadowsocks/socks
		 * option: sing-box 1.14 rejects it on a vless outbound, so
		 * mapping it here turned a stale UCI option into an
		 * unusable config. */
	},
	snell: {
		version: 'snell_version',
		reuse: 'snell_reuse',
		obfs_mode: 'snell_obfs_mode',
		obfs_host: 'snell_obfs_host'
		/* snell_mode is not mapped: sing-box 1.14 has no `mode`
		 * field on a snell outbound (or inbound).  It was v6-only
		 * in the form, and v6 is not supported by the target
		 * sing-box. */
	},
	shadowsocks: {
		plugin: 'shadowsocks_plugin',
		plugin_opts: 'shadowsocks_plugin_opts',
		udp_over_tcp: 'udp_over_tcp',
		udp_over_tcp_version: 'udp_over_tcp_version'
	},
	anytls: {
		idle_session_check_interval: 'anytls_idle_session_check_interval',
		idle_session_timeout: 'anytls_idle_session_timeout',
		min_idle_session: 'anytls_min_idle_session'
	},
	http: {},
	socks: {
		version: 'socks_version',
		udp_over_tcp: 'udp_over_tcp',
		udp_over_tcp_version: 'udp_over_tcp_version'
	},
	tuic: {
		congestion_control: 'tuic_congestion_control',
		udp_relay_mode: 'tuic_udp_relay_mode',
		udp_over_stream: 'tuic_udp_over_stream',
		zero_rtt_handshake: 'tuic_enable_zero_rtt',
		heartbeat: 'tuic_heartbeat'
	},
	trojan: {},
	shadowtls: {
		version: 'shadowtls_version'
	},
	hysteria: {
		protocol: 'hysteria_protocol',
		auth_type: 'hysteria_auth_type',
		auth_payload: 'hysteria_auth_payload',
		up_mbps: 'hysteria_up_mbps',
		down_mbps: 'hysteria_down_mbps',
		obfs_password: 'hysteria_obfs_password',
		hopping_port: 'hysteria_hopping_port',
		hop_interval: 'hysteria_hop_interval'
	},
	hysteria2: {
		obfs_type: 'hysteria_obfs_type',
		obfs_password: 'hysteria_obfs_password',
		up_mbps: 'hysteria_up_mbps',
		down_mbps: 'hysteria_down_mbps',
		hop_interval: 'hysteria_hop_interval',
		hop_interval_max: 'hysteria_hop_interval_max',
		hopping_port: 'hysteria_hopping_port',
		auth_payload: 'hysteria_auth_payload',
		bbr_profile: 'hysteria_bbr_profile',
		disable_chrome_parrot: 'hysteria_disable_chrome_parrot'
	},
	vmess: {
		alter_id: 'vmess_alterid',
		security: 'vmess_encrypt',
		global_padding: 'vmess_global_padding',
		auth_payload: 'vmess_auth_payload',
		/* packet_encoding was missing here, so a vmess node's UCI option
		 * never reached protocol_options and the outbound had none - even
		 * though the node form offers the option for vmess and the
		 * subscription default is applied to it. vless declares it too. */
		packet_encoding: 'packet_encoding'
	},
	ssh: {
		client_version: 'ssh_client_version',
		host_key: 'ssh_host_key',
		host_key_algorithms: 'ssh_host_key_algo'
	},
	wireguard: {
		local_address: 'wireguard_local_address',
		private_key: 'wireguard_private_key',
		peer_public_key: 'wireguard_peer_public_key',
		pre_shared_key: 'wireguard_pre_shared_key',
		reserved: 'wireguard_reserved',
		mtu: 'wireguard_mtu',
		persistent_keepalive_interval: 'wireguard_persistent_keepalive_interval'
	},
	direct: {
		override_address: 'override_address',
		override_port: 'override_port'
	}
};

/* Reverse direction: uci -> canonical. Built once at module load so
 * the parser can look up "what canonical name is `tls_sni` for
 * <protocol>" without hand-coding the inverse in protocols.uc.
 *
 * A protocol with no per-protocol options maps to an empty object,
 * which is intentional: `for ... in {}` is a no-op and the loader
 * still has the protocol-shape boundary on the Node. */
export const UCI_TO_PROTOCOL = {};
for (let proto, row in PROTOCOL_TO_UCI) {
	UCI_TO_PROTOCOL[proto] = {};
	for (let canonical, uci in row)
		UCI_TO_PROTOCOL[proto][uci] = canonical;
}