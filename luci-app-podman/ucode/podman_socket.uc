// Copyright 2026 Christopher Söllinger
// Licensed to the public under the Apache License 2.0.
//
// Shared Podman socket helper for the rpcd plugin, the LuCI streaming
// controller, the pull-worker and the podman-api CLI helper. Reads the
// destination once at module load from UCI:
//     luci-podman.globals.socket_path
// Accepted URI schemes:
//     unix:///path/to/socket    AF_UNIX
//     tcp://host:port           AF_INET
//     tcp6://[::1]:port         AF_INET6
//     /path/to/socket           bare path, treated as unix:///path
// Fallback: unix:///run/podman/podman.sock.

'use strict';

import { cursor } from 'uci';
import * as socket from 'socket';

const DEFAULT_DEST = 'unix:///run/podman/podman.sock';

/** Path prefix for all libpod REST API endpoints. */
export const API_BASE = '/v5.0.0/libpod';

const _dest = (() => {
	let c = cursor();
	let v = c.get('luci-podman', 'globals', 'socket_path');
	c.unload('luci-podman');
	return v || DEFAULT_DEST;
})();

const _parsed = (() => {
	if (substr(_dest, 0, 1) === '/')
		return { scheme: 'unix', addr: _dest };
	let m = match(_dest, /^([a-z0-9]+):\/\/(.+)$/i);
	if (!m)
		return null;
	return { scheme: lc(m[1]), addr: m[2] };
})();

/** @returns {?Socket} connected socket, or null on failure */
export function connect() {
	if (!_parsed)
		return null;

	if (_parsed.scheme === 'unix') {
		let sock = socket.create(socket.AF_UNIX, socket.SOCK_STREAM);
		if (!sock) return null;
		if (!sock.connect(socket.sockaddr(_parsed.addr))) {
			sock.close();
			return null;
		}
		return sock;
	}

	if (_parsed.scheme === 'tcp' || _parsed.scheme === 'tcp6') {
		let family = _parsed.scheme === 'tcp6' ? socket.AF_INET6 : socket.AF_INET;
		let raw = _parsed.addr;
		let colon = rindex(raw, ':');
		if (colon < 0) return null;
		let host = substr(raw, 0, colon);
		let port = +substr(raw, colon + 1);
		host = replace(host, /^\[|\]$/g, '');
		if (!port || !host) return null;

		let ai = socket.addrinfo(host, `${port}`, { family, socktype: socket.SOCK_STREAM });
		if (!ai || !length(ai)) return null;
		let sock = socket.create(family, socket.SOCK_STREAM);
		if (!sock) return null;
		if (!sock.connect(ai[0].addr)) {
			sock.close();
			return null;
		}
		return sock;
	}

	return null;
};

/** @returns {boolean} true if destination is a TCP scheme */
export function is_remote() {
	return _parsed && (_parsed.scheme === 'tcp' || _parsed.scheme === 'tcp6');
};

/** @returns {string} the raw URI from UCI (or the default), for logging */
export function get_dest() {
	return _dest;
};

/**
 * @returns {?string} filesystem path of the unix socket, or null for tcp/tcp6.
 *                    Useful for pre-flight stat() checks before connect().
 */
export function get_local_path() {
	if (!_parsed || _parsed.scheme !== 'unix') return null;
	return _parsed.addr;
};
